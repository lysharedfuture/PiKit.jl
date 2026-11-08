# provider-faux

## Purpose

定义测试用脚本化 Provider 的行为，使 agent 循环、CLI 与 JSON/RPC 模式可以在零网络条件下得到确定性的流事件与会话。faux 必须能表达文本、thinking 与工具调用，并能通过环境变量从 fixture 文件装载响应序列。

## Requirements

### Requirement: Scripted response streaming

`faux` Provider SHALL 按队列顺序消费响应步骤，把文本/thinking 按 3–5 个 **token** 切块（默认每 token 4 字符，即 12–20 字符，`tokenSize` 可配置）并发出对应的 `*_start`/`*_delta`/`*_end` 事件；工具调用 MUST 先发 `toolcall_start`、再分块发送参数 JSON、最后发 `toolcall_end`；每次请求 MUST 记录调用次数与最近一次上下文。

#### Scenario: Text step yields a full event sequence

- **WHEN** 队列中有一个文本步骤并被消费
- **THEN** 事件序列为 `StartEvent`、`TextStartEvent`、若干 `TextDeltaEvent`、`TextEndEvent`、`DoneEvent`

#### Scenario: Chunks use token size, not character count

- **WHEN** 文本步骤使用默认 3–5 token 配置
- **THEN** 除最后一块外，每个 delta 的字符数在 12–20 之间（3–5 token × 4 字符）

#### Scenario: Tool call step yields tool events

- **WHEN** 队列中有一个工具调用步骤
- **THEN** 参数 JSON 以 `toolcall_delta` 分块送达，`toolcall_end` 携带完整 `ToolCall`

#### Scenario: Model metadata is reported

- **WHEN** 流正常结束
- **THEN** 最终消息的 `api` 与 `provider` 均为 `faux`，`model` 为请求的模型 id

### Requirement: Exhausted queue and scripted failures

当响应队列为空时，`faux` SHALL 返回一个 `ErrorEvent`，其错误消息 `error_message == "No faux response queued"` 且 `stop_reason == "error"`；脚本步骤 MAY 指定任意 stop reason 与 `error_message` 以模拟失败响应。

#### Scenario: Empty queue fails deterministically

- **WHEN** `stream` 被调用但没有排队步骤
- **THEN** 产出一个错误事件而不是抛出异常

#### Scenario: Scripted error step

- **WHEN** 步骤指定 `stop_reason="error"` 与错误文本
- **THEN** 最终消息保留该 stop reason 与错误文本

### Requirement: CLI fixture loading

当 `PIKIT_FAUX_RESPONSES` 指向文件时，CLI SHALL 读取 JSON 数组并按顺序消费；元素 MUST 支持文本、thinking、工具调用和完整消息形态，耗尽后按空队列语义失败；未显式指定模型时 MUST 默认使用 `faux/faux-1`。

#### Scenario: Fixture drives print mode

- **WHEN** fixture 首项为文本且 CLI 以 `-p` 运行
- **THEN** stdout 输出该文本且退出码为 0

#### Scenario: Fixture tool call drives a tool turn

- **WHEN** fixture 首项为工具调用、次项为文本
- **THEN** CLI 先执行工具，再用第二项作为最终回复

#### Scenario: Exhausted fixture reports an error

- **WHEN** 请求次数超过 fixture 项数
- **THEN** 该次运行以错误事件结束，进程返回非零退出码
