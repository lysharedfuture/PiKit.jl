# cli-modes

## Purpose

定义 `pikit` 的命令行解析、配置优先级、runtime 组装，以及 print、JSON、RPC 与行式 REPL 四种入口的可观察行为。协议模式必须保持与上游相同的帧形状与退出码，同时不把日志写入协议输出流。

## Requirements

### Requirement: CLI parsing and option subset

`parse_cli` SHALL 支持一期选项子集：`-p/--print`、`--mode`、`--provider`、`--model`、`--api-key`、`--thinking`、`-t/--tools`、`-xt/--exclude-tools`、`-nbt/--no-builtin-tools`、`-nt/--no-tools`、`-c/--continue`、`-r/--resume`、`--session`、`--session-id`、`--fork`、`--session-dir`、`--no-session`、`-n/--name`、`--system-prompt`、`--append-system-prompt`、`--no-context-files`、`-a/--approve`、`-na/--no-approve`、`--offline`、`--list-models`、`-v/--version`、`-h/--help`；MUST 支持 `--` 终止、`@file` 读取与可重复选项；非法 `--thinking` 或 `--session-id` MUST 以退出码 2 结束。

#### Scenario: Double dash collects prompt text

- **WHEN** 参数为 `-- --not-an-option`
- **THEN** `--not-an-option` 作为 prompt 文本而不是选项

#### Scenario: At-file loads a prompt or image

- **WHEN** 位置参数为 `@path`
- **THEN** 文本文件内容并入初始 prompt，图片以 base64 加入 images

#### Scenario: RPC rejects at-file

- **WHEN** `--mode rpc` 下出现 `@path`
- **THEN** 立即报错并以退出码 2 结束

#### Scenario: Tool selection modes

- **WHEN** `--tools` 的所有项以 `+`/`-` 开头
- **THEN** 在默认集上增删；否则整体替换默认集

### Requirement: Configuration precedence

`config` SHALL 读取 `PIKIT_AGENT_DIR` 或 `~/.pikit/agent` 下的用户设置，以及受信任时的项目 `.pikit/settings.json`；优先级 MUST 为 CLI > 项目（信任时）> 用户 > 默认；支持 `model`、`provider`、`thinking`、`defaultTools`、`sessionDir`、`autoCompaction`、`autoRetry`、`reserveTokens`、`keepRecentTokens`、`retry`、`cacheRetention` 与 `apiKeys`。

#### Scenario: CLI overrides settings

- **WHEN** CLI 提供 `--model` 且设置文件也有模型
- **THEN** 使用 CLI 模型

#### Scenario: Untrusted project settings are ignored

- **WHEN** 未传 `--approve` 且存在项目设置
- **THEN** 项目设置不参与优先级

#### Scenario: Context files ignore trust

- **WHEN** 项目未受信任但存在 AGENTS.md
- **THEN** 上下文文件仍被收集

### Requirement: Print mode

`-p` 文本模式 SHALL 记录本次运行最后一次 assistant `message_end`，成功时逐块打印文本并换行；`stop_reason` 为 `error`/`aborted` 时 MUST 写 stderr 并返回 1；`length` MUST 写 `Response was truncated: the model reached its output token limit.` 并返回 1。

#### Scenario: Successful print

- **WHEN** faux 返回一行文本且以 `-p` 运行
- **THEN** stdout 恰为该文本加换行，退出码 0

#### Scenario: Truncated response returns failure

- **WHEN** 最终 assistant 的 `stop_reason == "length"`
- **THEN** stderr 输出截断提示且退出码为 1

### Requirement: JSON mode events

`--mode json` SHALL 先写 session header，再逐行写事件 JSON；`message_update` MUST 去掉 `partial`、在顶层加 `usage`，`toolcall_start` MUST 补 `id`/`toolName`；`agent_end` MUST 追加 `willRetry`；事件全集 MUST 覆盖 `queue_update`、`thinking_level_changed`、`session_info_changed`、`entry_appended`、`compaction_start/end`、`auto_retry_*`、`summarization_retry_*` 与 `agent_settled`；stdout MUST 只含协议。

#### Scenario: Update frame shape

- **WHEN** 运行产生 `message_update`
- **THEN** 输出对象不含 `partial`，但含 `usage`

#### Scenario: Terminal events present

- **WHEN** 一次正常运行结束
- **THEN** 输出包含 `agent_start`、`turn_start`、`message_start/end`、`turn_end`、`agent_end` 与 `agent_settled`

#### Scenario: Logs stay off stdout

- **WHEN** 运行期间产生警告
- **THEN** 警告写入 stderr，stdout 仍可逐行解析为 JSON

### Requirement: RPC mode

`--mode rpc` SHALL 逐行读取 stdin JSON 并实现 `prompt`、`steer`、`follow_up`、`abort`、`clear_queue`、`get_state`、`get_messages`、`set_model`、`cycle_model`、`get_available_models`、`set_thinking_level`、`cycle_thinking_level`、`get_available_thinking_levels`、`set_steering_mode`、`set_follow_up_mode`、`compact`、`set_auto_compaction`、`set_auto_retry`、`abort_retry`、`bash`、`abort_bash`、`new_session`、`switch_session`、`fork`、`clone`、`get_fork_messages`、`get_session_stats`、`get_last_assistant_text`、`set_session_name`、`get_entries`、`get_tree`；响应 MUST 为 `{"id","type":"response","command","success","data","error"}`；`prompt` 的 `disposition` MUST 为 `started`、`queued` 或 `handled`。

#### Scenario: get_state responds

- **WHEN** 输入 `{"id":"1","type":"get_state"}`
- **THEN** 输出一行 response，`command=="get_state"`、`success==true`，data 含 `sessionId`/`sessionFile`/`model`/`thinkingLevel`/`isStreaming`/`messageCount`

#### Scenario: Unknown command fails without crashing

- **WHEN** 输入未知命令
- **THEN** 返回 `success:false` 与 `unsupported command: X`

#### Scenario: EOF aborts and closes

- **WHEN** stdin 关闭
- **THEN** 当前运行被中止，会话关闭后进程退出

### Requirement: Line REPL

REPL SHALL 提供 `/help`、`/new`、`/resume`、`/model <id>`、`/thinking <level>`、`/compact [instr]`、`/session`、`/tools`、`/quit`；流式输出 MUST 把文本增量写 stdout，TTY 下 thinking 使用暗色控制序列；Ctrl+C MUST 中止当前运行且 REPL 继续接受输入。

#### Scenario: Ctrl+C keeps the REPL alive

- **WHEN** 运行中按 Ctrl+C
- **THEN** 当前请求被中止，提示符重新出现

#### Scenario: Resume lists sessions

- **WHEN** 执行 `/resume`
- **THEN** 输出编号会话列表并允许选择

### Requirement: JSONL framing and stdin handling

所有 JSONL 场景（JSON 模式、RPC 与会话文件）SHALL 只按 `\n` 切分记录并剥掉前导 `\r`，MUST NOT 把 U+2028/U+2029 当作分隔符；非 TTY stdin 且非 RPC 时 SHALL 读取全部输入并前置到初始 prompt；空输入且无 prompt 时 MUST 在 TTY 进入 REPL、在非 TTY 退出 0；`--system-prompt` 与 `--append-system-prompt` 的值若指向存在的文件 MUST 读取其内容，否则按字面文本处理。

#### Scenario: Unicode line separators are data

- **WHEN** JSON 字符串包含 U+2028 或 U+2029
- **THEN** 该记录不被切成多行

#### Scenario: Piped stdin becomes prompt context

- **WHEN** stdin 非 TTY 且包含文本
- **THEN** 该文本作为初始 prompt 的前缀

#### Scenario: Empty input chooses the entry

- **WHEN** 无位置参数、无 stdin 内容且 stdout 非 TTY
- **THEN** 进程以退出码 0 结束且不进入 REPL

#### Scenario: System prompt file is read

- **WHEN** `--system-prompt` 的值是存在的文件路径
- **THEN** 使用文件内容作为系统提示，而不是路径字面量

### Requirement: Runtime persistence and automatic retry

runtime SHALL 在 `message_end` 时持久化 user、toolResult 与 bashExecution，仅在 assistant 的 `stop_reason` 不属于 `error`/`aborted`/`pending` 时持久化 assistant；重试 MUST 仅针对可重试的 assistant 错误，最多 3 次，延迟为 2s/4s/8s，并发出 `auto_retry_start` 与 `auto_retry_end`；溢出走压缩恢复而不是自动重试。

#### Scenario: Failed assistant is not persisted

- **WHEN** assistant 以 `error` 结束
- **THEN** 会话文件不新增该 assistant entry

#### Scenario: Retry events bracket retries

- **WHEN** 可重试错误发生后重试成功
- **THEN** 输出 `auto_retry_start` 与 `auto_retry_end{success:true}`

#### Scenario: Quota error skips retry

- **WHEN** 错误为 `insufficient_quota`
- **THEN** 不发出自动重试事件

### Requirement: Model selection and faux default

CLI SHALL 优先使用 `--model`，其次设置文件的 `provider/model`；当 `PIKIT_FAUX_RESPONSES` 存在时 MUST 注册 faux 并在未显式指定模型时默认 `faux/faux-1`；没有任何模型来源时 MUST 报错 `No model selected. Use --model or configure ~/.pikit/models.json.` 并以退出码 2 结束。

#### Scenario: Faux environment selects default model

- **WHEN** 设置 `PIKIT_FAUX_RESPONSES` 且未传 `--model`
- **THEN** 运行使用 `faux/faux-1`

#### Scenario: Missing model is a usage error

- **WHEN** 没有 CLI、设置或环境提供模型
- **THEN** 输出该错误并退出 2

#### Scenario: List models output

- **WHEN** 传入 `--list-models`
- **THEN** 每行输出 `<provider>/<id>\t<name>` 并退出 0
