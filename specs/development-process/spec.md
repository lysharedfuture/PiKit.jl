# development-process

## Purpose

定义 PiKit 的开发过程约束，适用于一期（W1–W5）、二期（2A–2D）与三期（3A–3E）：确保各期发现的 TypeScript 与 Julia 差异被持续记录到 `docs/julia-improvements.md`，而不是在发布前补写。规范负责“必须记录什么”，文档负责“实际记录了什么”。

## Requirements

### Requirement: Per-wave improvement records

一期 W1–W5、二期 2A–2D、三期 3A–3E 的每个 wave SHALL 在 `docs/julia-improvements.md` 至少记录 3 条改进建议；每条 MUST 使用该 wave 的稳定 ID（一期 `W<n>-<nn>`，二期/三期 `<phase><letter>-<nn>`），并包含 `上游`、`观察`、`Julia 方案`、`结论` 四个字段；`结论` MUST 为 `采纳`、`建议上游` 或 `Julia 生态缺口`。

#### Scenario: Wave completion requires three records

- **WHEN** 任一期的某个 wave 实现任务完成
- **THEN** 该 wave 的文档任务只有在该 wave 至少 3 条记录且四字段完整时才可标记完成

#### Scenario: Missing field fails the check

- **WHEN** 某条目缺少 `Julia 方案`
- **THEN** 检查器以非零退出码报告该 ID 缺失字段

#### Scenario: All phases use the same record contract

- **WHEN** 二期 2A 或三期 3A 的记录被检查
- **THEN** 它们与一期 W1 使用相同的四字段、结论枚举与每波至少 3 条要求

### Requirement: Required improvement topics

规范 SHALL 为每个 phase 的每个 wave 维护必选主题与稳定 ID；记录条目标题 MUST 使用这些 ID；主题 MUST 全部覆盖。Phase 1 的 W1–W5 与 Phase 2 的 2A–2D 主题见下表；Phase 3（3A–3E）的必选主题 MUST 在各 wave 启动前补入本规范，未登记不得启动。

#### Scenario: W1 topics are covered

- **WHEN** 运行检查器 `--wave W1`
- **THEN** 必须存在 W1-01、W1-02、W1-03 三条记录

#### Scenario: Unknown ID is rejected

- **WHEN** 记录使用未在本规范表中出现的 ID
- **THEN** 检查器报告未知 ID，而不是把它当作新主题

#### Scenario: Future phase topics are registered before start

- **WHEN** 二期 2A 或三期 3A 准备启动
- **THEN** 该 wave 的必选主题与 ID 已登记在规范中；否则检查器拒绝启动门禁

| Phase | Wave | ID | Required topic |
|---|---|---|---|
| 1 | W1 | W1-01 | 异步流：AsyncIterator vs Channel/Task |
| 1 | W1 | W1-02 | SSE 客户端解析 |
| 1 | W1 | W1-03 | JSON Schema 校验错误路径 |
| 1 | W2 | W2-01 | AbortSignal vs `AbortToken` + IO close |
| 1 | W2 | W2-02 | `Promise.all` 并发与事件顺序 |
| 1 | W2 | W2-03 | 结构化消息 union vs 抽象类型 |
| 1 | W3 | W3-01 | 进程组超时/杀树 |
| 1 | W3 | W3-02 | rg/fd 外部工具管理与 `.gitignore` 语义 |
| 1 | W3 | W3-03 | 文本 diff 实现 |
| 1 | W3 | W3-04 | 子进程环境继承与 `PI_*` 覆盖 |
| 1 | W3 | W3-05 | login shell 取舍 |
| 1 | W4 | W4-01 | CLI 解析与 `@file`/`--` |
| 1 | W4 | W4-02 | REPL 的 Ctrl+C 中止 |
| 1 | W4 | W4-03 | 无差分渲染 TUI 的取舍 |
| 1 | W5 | W5-01 | 会话树/压缩 token 估算 |
| 1 | W5 | W5-02 | v3 兼容读取的未知 entry 策略 |
| 1 | W5 | W5-03 | 补充主题（实现期确定，≥1 条） |
| 2 | 2A | 2A-01 | 包边界与依赖方向 |
| 2 | 2A | 2A-02 | 类型身份与模块别名 |
| 2 | 2A | 2A-03 | 日志安装点与库设计 |
| 2 | 2B | 2B-01 | 持久存储格式与单写者 |
| 2 | 2B | 2B-02 | effect 三明治与 replay 策略 |
| 2 | 2B | 2B-03 | deferred 轮询与崩溃恢复 |
| 2 | 2B | 2B-04 | 文档事务子集与 chord 替代 |
| 2 | 2C | 2C-01 | HTTP/SSE 手写 vs 厂商 SDK |
| 2 | 2C | 2C-02 | OAuth 与凭据存储 |
| 2 | 2C | 2C-03 | 长缓存与 provider 能力矩阵 |
| 2 | 2C | 2C-04 | AWS SigV4 与二进制 event-stream |
| 2 | 2D | 2D-01 | JSON Schema 编译与 unevaluated 语义 |
| 2 | 2D | 2D-02 | ECMA 正则兼容 |
| 2 | 2D | 2D-03 | MCP 传输与工具桥接 |
| 2 | 2D | 2D-04 | 遥测显式上下文与脱敏 |

Phase 3 登记表（启动前必须补入主题与 ID）：

| Phase | Wave | Status |
|---|---|---|
| 3 | 3A | 启动前登记 |
| 3 | 3B | 启动前登记 |
| 3 | 3C | 启动前登记 |
| 3 | 3D | 启动前登记 |
| 3 | 3E | 启动前登记 |

### Requirement: Upstream anchors

每条记录的 `上游` MUST 为 `.upstream` 下的 `<path>:<line>`；提供快照时检查器 MUST 校验路径存在且行号在文件范围内；未提供快照时 MUST 只做格式检查并明确报告“未校验”。

#### Scenario: Valid upstream anchor

- **WHEN** `上游` 为 `packages/ai/src/types.ts:123` 且 `.upstream` 快照存在
- **THEN** 检查器确认该文件存在且行号不超过文件行数

#### Scenario: Invalid anchor fails

- **WHEN** `上游` 指向不存在的文件或越界行号
- **THEN** 检查器以非零退出码报告该 ID

#### Scenario: Missing snapshot does not fake validation

- **WHEN** 未提供 `.upstream` 快照
- **THEN** 检查器只校验 `path:line` 格式，并明确输出“锚点未校验”

### Requirement: Capture during implementation

发现上游差异时，实现者 SHALL 在对应 wave 结束前写入记录；不得只在阶段发布前补写（一期 M8、二期各子阶段收口、三期 v1.0）；`design.md` 的架构决策 SHOULD 引用相关记录 ID，便于实现时回填。

#### Scenario: Divergence is recorded before wave close

- **WHEN** 任一期的某个 wave 实现中发现上游语义差异
- **THEN** 该 wave 关闭前记录已存在且四字段完整

#### Scenario: Retrospective gap is visible

- **WHEN** 某 wave 已关闭但缺少必选 ID
- **THEN** 检查器报告缺口，该期发布门禁不得通过

### Requirement: Verification and release gate

每个 wave SHALL 运行 `julia scripts/check-julia-improvements.jl --wave <id>`；每期发布 MUST 运行 `--phase <phase> --strict`（一期 M8、二期各子阶段收口、三期 v1.0）；三期最终发布 MUST 额外运行 `--all --strict`；失败 MUST 阻止该期 tag 与发布；review MUST 抽查记录内容与代码实现一致。

#### Scenario: Missing records block release

- **WHEN** 某期运行 `--phase <phase> --strict` 发现缺失条目或占位符
- **THEN** 该期发布任务不得标记完成

#### Scenario: Phase 2 gate is independent

- **WHEN** 一期记录完整但二期 2A–2D 记录缺失
- **THEN** 二期发布门禁失败，一期结果不能替代二期检查

#### Scenario: Review rejects superficial entries

- **WHEN** 条目字段齐全但 `Julia 方案` 与代码实际实现不一致
- **THEN** review 以失败处理并要求重写该条目
