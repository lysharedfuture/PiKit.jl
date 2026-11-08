# session-compaction

## Purpose

定义会话 v3 的持久化格式、容错读取、上下文重建、fork 语义，以及 token 估算、压缩与溢出恢复。目标是让一期写出的会话可被 pi 读取，同时能读取 pi 会话与未知 entry，并在上下文超限时恢复运行。

## Requirements

### Requirement: Session v3 persistence

SessionManager SHALL 写入 header `{"type":"session","version":3,"id":...,"timestamp":...,"cwd":...}` 与带 `id`/`parentId`/`timestamp` 的 entry；一期 MUST 只写 `session`、`message`、`model_change`、`thinking_level_change`、`compaction`、`session_info`；entry id MUST 为 8 位小写 hex（冲突时重试，空间耗尽退化为完整 UUID），时间戳 MUST 为 ISO8601 UTC 毫秒；`stop_reason="pending"` 的消息 MUST NOT 写入。

#### Scenario: Session header and entries round-trip

- **WHEN** 创建会话并追加 user/assistant/toolResult 条目后重新加载
- **THEN** header 与所有已知 entry 的字段值保持不变

#### Scenario: Pending assistant is rejected

- **WHEN** 尝试持久化 `stop_reason="pending"` 的 assistant 消息
- **THEN** 写入被拒绝，会话文件不变

#### Scenario: Unknown entry is preserved read-only

- **WHEN** 加载含未知 `type` 的会话
- **THEN** 该行解析为 `UnknownEntry` 并保留 id/parentId/timestamp，重写时不输出该 entry

### Requirement: Tolerant session loading

`load_session` SHALL 要求首行是 session header，跳过无法解析的畸形行；当文件末尾缺少换行且末行可解析时 MUST 补写换行；已知 entry MUST 保留未识别键到 `extra`。

#### Scenario: Malformed line is skipped

- **WHEN** 会话中夹有一行非法 JSON
- **THEN** 加载继续，其余 entry 完整

#### Scenario: Missing trailing newline is repaired

- **WHEN** 文件最后一个 entry 完整但缺少换行
- **THEN** 加载成功并追加换行

#### Scenario: Unknown keys survive fork

- **WHEN** compaction entry 含 `details`/`fromHook`/`usage` 等未建模键并执行 fork
- **THEN** 新会话中的该 entry 仍含这些键

### Requirement: Context rebuild with compaction and context_edit

`build_context` SHALL 从 leaf 回溯到 root；若路径含 compaction，MUST 以最新一条的 `systemMessage`（存在时）为首条 system 消息，保留 `firstKeptEntryId` 到该 compaction 之间的非 system 消息，再加上 compaction 之后的消息；`context_edit` 的 `replacement=null` MUST 将目标 entry 从模型上下文排除，目标为 assistant 时 MUST 同时排除其 `toolResult`。

#### Scenario: Compaction rebuilds a shorter context

- **WHEN** 会话在两条消息之间插入 compaction
- **THEN** 重建上下文从 summary system 消息开始，且只保留切点之后的消息

#### Scenario: Context edit excludes a failed assistant

- **WHEN** 会话含 `{"type":"context_edit","targetId":...,"replacement":null}`
- **THEN** 目标 assistant 及其工具结果不出现在重建上下文中

#### Scenario: Compaction without firstKeptEntryId

- **WHEN** 读取旧版 compaction 且没有 `firstKeptEntryId`
- **THEN** 按回退规则保留全部消息，不丢历史

### Requirement: Session discovery and fork

`list_sessions` SHALL 按 mtime 倒序返回；`find_session` MUST 支持完整路径、完整 id 与唯一前缀；`fork_session` MUST 复制 active branch 到新文件、重写 id/parentId、在 header 记录 `parentSession`，并 MUST 重映射 compaction 的 `firstKeptEntryId`，目标不在复制范围时丢弃该 compaction 并保留全部消息。

#### Scenario: Fork copies the active branch

- **WHEN** 对某个 entry 执行 fork
- **THEN** 新会话只含从 root 到该 entry 的路径，父子链连续

#### Scenario: Compaction remap is dropped when out of range

- **WHEN** fork 范围不包含 compaction 的 `firstKeptEntryId`
- **THEN** 新会话不写该 compaction，历史消息全部保留

#### Scenario: Session lookup by prefix

- **WHEN** 使用唯一 id 前缀查找会话
- **THEN** 返回对应会话路径

### Requirement: Session location and naming

`session_root()` SHALL 依次取 `--session-dir`、`PIKIT_SESSION_DIR`、`~/.pikit/agent/sessions`；cwd 目录名 MUST 按 `--<cwd>` 的规则将 `/`、`\`、`:` 替换为 `-` 后加 `--`；文件名 MUST 为 `<yyyy-mm-ddTHH-MM-SS>_<uuid>.jsonl`（时间戳冒号替换为 `-`）；`--no-session` MUST 使用内存会话且不创建文件。

#### Scenario: Cwd directory encoding

- **WHEN** 会话 cwd 为 `/home/u/proj`
- **THEN** 会话位于 `--home-u-proj--` 子目录下

#### Scenario: Session directory override

- **WHEN** 传入 `--session-dir /tmp/sessions`
- **THEN** 新会话文件创建在 `/tmp/sessions` 下

#### Scenario: In-memory session writes nothing

- **WHEN** 使用 `--no-session`
- **THEN** 消息仍可读写于内存 manager，但磁盘上没有会话文件

### Requirement: Token estimation and compaction

`estimate_tokens` SHALL 按字符数除以 4 向上取整估算，并对 system/sections/tools、assistant 内容、工具结果、bash 输出、summary 与图片（4800 字符）分别计数；压缩 MUST 在 `context_tokens > context_window - reserve_tokens` 时触发；切点 MUST 落在 user/assistant/bashExecution/custom，且切开一轮时回退到该轮 user 起始。

#### Scenario: Usage anchor avoids full re-estimation

- **WHEN** 最后一条有效 assistant 带有 usage
- **THEN** 只对其后的消息做 chars/4 估算

#### Scenario: Compaction writes a summary entry

- **WHEN** 摘要请求以 `stop` 成功结束
- **THEN** 追加含 `summary`、`firstKeptEntryId`、`tokensBefore`、`systemMessage` 与 `usage` 的 compaction entry

#### Scenario: Failed summary writes nothing

- **WHEN** 摘要请求失败、中止或被长度截断
- **THEN** 不写 compaction entry，并发出带 `errorMessage` 或 `aborted=true` 的 `compaction_end`

### Requirement: Overflow recovery

溢出恢复 SHALL 在一次运行中最多执行一次：命中 `is_context_overflow` 后 MUST 移除失败 assistant、压缩一次并重试该轮；若响应成功但超过窗口则压缩并保留该响应；随后发送 `compaction_start{reason="overflow"}` 与对应结束事件。

#### Scenario: Overflow triggers compaction and retry

- **WHEN** 首次请求返回 `prompt is too long`
- **THEN** 发出溢出压缩事件，压缩后重试并成功写入正常 assistant

#### Scenario: Only one recovery per run

- **WHEN** 同一次运行再次发生溢出
- **THEN** 不再自动恢复，按错误结束
