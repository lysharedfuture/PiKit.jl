# agent-loop

## Purpose

定义 AgentCore 层的循环：状态机、事件序列、工具执行顺序、可插拔 hooks、steering/follow-up 队列、中止与订阅语义。该能力只依赖 `AI` 层的消息与流事件，不感知具体 Provider，也不包含编码工具实现。

## Requirements

### Requirement: Agent event lifecycle

循环 SHALL 按 `agent_start`、若干 `turn_start`/`message_start`/`message_update`/`message_end`/`turn_end`、`agent_end` 的顺序发出事件；`agent_end.messages` MUST 只包含本次运行新增的消息；核心循环 MUST NOT 发出 `will_retry` 或 `agent_settled`。

#### Scenario: Text-only turn sequence

- **WHEN** 一次请求只返回文本
- **THEN** 事件顺序为 `agent_start`、`turn_start`、user `message_start/end`、assistant `message_start/update*/end`、`turn_end`、`agent_end`

#### Scenario: Missing start event is synthesized

- **WHEN** Provider 未发送 `start` 却发送了内容事件
- **THEN** 循环补发 `message_start` 后继续处理增量

#### Scenario: Tool turn continues the loop

- **WHEN** assistant 以 `stop_reason="toolUse"` 结束
- **THEN** 执行工具并进入下一轮，而不是发出 `agent_end`

### Requirement: Tool declaration reconciliation

循环 SHALL 从 transcript 的 system `tools_added`/`tools_removed` 重放当前工具集，并与 `context.tools` 求差；存在差异时 MUST 在首条非 system 消息前插入或更新 system 消息，空字段 MUST 省略。

#### Scenario: Tool set change is recorded

- **WHEN** 本次请求的工具集与 transcript 重放结果不同
- **THEN** 新的 system 消息携带最小差异的 `toolsAdded`/`toolsRemoved`

#### Scenario: No change adds no system message

- **WHEN** 工具集与重放结果一致
- **THEN** 不新增 system 消息

### Requirement: Parallel and sequential tool execution

工具批次 SHALL 在任一工具 `execution_mode == :sequential` 或配置为顺序时整批顺序执行；否则 MUST 先顺序预检，再用 `@async` 并发执行；`tool_execution_end` MUST 按完成顺序发出，`toolResult` 消息 MUST 按 assistant 源顺序生成；所有 emit 必须经 `ReentrantLock` 串行化。

#### Scenario: Completion order differs from source order

- **WHEN** 两个并行工具中第二个先完成
- **THEN** `tool_execution_end` 先发给第二个，而 `turn_end.toolResults` 仍按 assistant 源顺序排列

#### Scenario: Sequential tool forces the whole batch sequential

- **WHEN** 批次中任一工具声明 `:sequential`
- **THEN** 该批次所有工具按源顺序执行

#### Scenario: Events are not interleaved

- **WHEN** 多个工具任务同时尝试 emit
- **THEN** 事件按锁保护顺序完整写出，不发生帧交错

### Requirement: Tool failure, termination and length-stop

工具 `execute` 抛出的异常 MUST 被捕获为 `is_error=true` 的结果且循环继续；`terminate` 仅当批次内所有结果都为 true 时才提前结束；当 assistant `stop_reason == "length"` 时 MUST 不执行任何工具，并为每个调用发出失败的工具结果。

#### Scenario: Throwing tool becomes error result

- **WHEN** 工具执行抛出异常
- **THEN** 产生 `is_error=true` 的结果，异常文本作为内容，循环继续

#### Scenario: Termination requires unanimous results

- **WHEN** 批次中只有一个结果 `terminate=true`
- **THEN** 循环继续执行后续轮次

#### Scenario: Length stop does not execute tools

- **WHEN** assistant 带工具调用但 `stop_reason == "length"`
- **THEN** 每个工具都收到失败结果，且 `execute` 未被调用

### Requirement: Loop hooks

循环 SHALL 支持 `before_tool_call`、`after_tool_call`、`finish_turn`、`prepare_request` 与 `prepare_next_turn`；hooks 返回 `nothing` MUST 表示不替换；`finish_turn` MUST 返回 `:end`、`:continue` 或 `nothing`；`after_tool_call` MUST 逐字段覆盖结果且替换 `content` 时丢弃未重新提供的 `structured_content`。

#### Scenario: Blocked tool call skips execution

- **WHEN** `before_tool_call` 返回 `block=true`
- **THEN** 产生失败结果且工具 `execute` 未被调用

#### Scenario: Hook result override

- **WHEN** `after_tool_call` 返回新的 `content`
- **THEN** 最终工具结果使用该内容，并丢弃旧的 `structured_content`

#### Scenario: Explicit continuation without extra request

- **WHEN** `finish_turn` 返回 `:continue` 且已有工具结果或排队消息
- **THEN** 不额外发送仅上下文请求，直接进入下一轮

### Requirement: Steering and follow-up queues

`Agent` SHALL 支持 `steer!`、`follow_up!`、`clear_queues!` 与 `peek_queued`；队列模式 MUST 为 `:one_at_a_time` 或 `:all`；steering 消息 MUST 在下一次 LLM 请求前注入，follow-up MUST 在本应停止后触发下一轮。

#### Scenario: Steering is injected before the next request

- **WHEN** 运行中调用 `steer!`
- **THEN** 该消息出现在下一次请求的上下文中

#### Scenario: Follow-up starts a new turn

- **WHEN** 模型正常结束且 follow-up 队列非空
- **THEN** 循环继续处理 follow-up 而不是 `agent_end`

#### Scenario: Continue from assistant requires a queue

- **WHEN** transcript 末尾是 assistant 且两个队列都为空
- **THEN** `continue!` 抛出 `Cannot continue from message role: assistant`

### Requirement: Abort and failure fallback

`abort!` MUST 触发协作式取消，且运行在 200ms 内以 `agent_end` 结束；运行失败时 MUST 构造 `stop_reason="aborted"` 或 `"error"` 的 `AssistantMessage` 并依次发出 `message_start`、`message_end`、`turn_end`、`agent_end`；`wait_idle` MUST 等待活动任务结束。

#### Scenario: Abort settles quickly

- **WHEN** 在一次流式运行中调用 `abort!`
- **THEN** 200ms 内收到 `agent_end`，最终 assistant 的 `stop_reason == "aborted"`

#### Scenario: Unexpected failure still emits terminal events

- **WHEN** 循环内部抛出未被工具捕获的异常
- **THEN** 生成错误消息并发出完整的终止事件序列

### Requirement: Listener and state updates

`subscribe(agent, f)` SHALL 返回取消闭包；listener MUST 按注册顺序串行调用，返回 `Task` 时等待完成；`prompt!` MUST 在 `agent_end` listener 结算后才返回；listener 只能在运行期间调用，单个 listener 抛错 MUST 按运行失败处理。

#### Scenario: Listeners run in order and settle

- **WHEN** 两个 listener 订阅同一运行
- **THEN** 记录顺序与注册顺序一致，`prompt!` 返回时两者都已完成

#### Scenario: Listener outside a run is rejected

- **WHEN** 在没有活动运行时调用 listener
- **THEN** 抛出 `Agent listener invoked outside active run`

#### Scenario: State tracks streaming message

- **WHEN** 收到 `message_start`、`message_update`、`message_end`
- **THEN** `state.streaming_message` 依次设置、更新、清空

### Requirement: Turn definition

一次 turn SHALL 表示 agent 循环的一次迭代，从 `turn_start` 到 `turn_end`；它 MUST 包含该迭代消费的输入、一次 assistant 响应，以及该响应触发的工具执行与 `toolResult`（如果有）；tool 调用 MUST NOT 作为 turn 的判定条件，纯文本响应 MUST 构成完整 turn；工具执行后的下一次 assistant 响应 MUST 属于新的 turn。

#### Scenario: Text-only response is one turn

- **WHEN** assistant 返回纯文本且没有 tool 调用
- **THEN** 该次响应构成一个 turn，`turn_end.toolResults` 为空；若没有后续 continuation，运行随后进入 `agent_end`

#### Scenario: Tool call remains one turn

- **WHEN** assistant 返回一个 tool 调用
- **THEN** 该 assistant 响应、工具执行与 `toolResult` 属于同一个 turn

#### Scenario: Multiple tool calls stay in the same turn

- **WHEN** 同一 assistant 响应包含多个 tool 调用
- **THEN** 所有工具执行与结果仍属于同一个 turn

#### Scenario: Next assistant response starts a new turn

- **WHEN** 工具执行完成后循环继续请求模型
- **THEN** 下一次 assistant 响应属于新的 turn，而不是原 turn 的延续
