# provider-anthropic-messages

## Purpose

定义 `anthropic-messages` Provider 的 Messages API 请求翻译、thinking budget、提示缓存、SSE 事件映射与 usage/成本语义。目标是与上游 `pi-ai` 的 Anthropic 路径逐字段兼容，包括缓存断点位置与长保留 TTL。

## Requirements

### Requirement: Anthropic Messages request translation

Provider SHALL 向 `base_url` 的 `/v1/messages`（base_url 已含 `/v1` 时为 `/messages`）发送带 `x-api-key`、`anthropic-version: 2023-06-01` 与 `content-type` 的流式请求；请求体 MUST 含 `model`、`max_tokens`、`messages`、`stream=true`，并在适用时写入单块 system 文本、`tools` 的 `input_schema`、`thinking` 与 `temperature`。

#### Scenario: System messages collapse into one text block

- **WHEN** 上下文包含多条 system 消息
- **THEN** 请求体 `system` 是单块 `[{"type":"text","text":...}]`，各段以两个换行连接

#### Scenario: Thinking budget respects max tokens

- **WHEN** 请求的 thinking budget 大于 `max_tokens - 1024`
- **THEN** budget 被 clamp 到 `max_tokens - 1024`，且不低于 1024

#### Scenario: Temperature omitted while thinking is enabled

- **WHEN** thinking 已启用
- **THEN** 请求体不发送 `temperature`

#### Scenario: Adjacent same-role messages merge

- **WHEN** 连续 assistant 消息含 `tool_use`
- **THEN** 它们被合并进同一条消息的 content 数组

### Requirement: Prompt cache control placement

Provider SHALL 在启用缓存时给 system 文本块、最后一个工具定义与最后一个 user 消息的最后一个 content 块添加 `cache_control: {"type":"ephemeral"}`；当 `cache_retention == "long"` 且 `compat` 支持长保留时 MUST 追加 `"ttl":"1h"`。

#### Scenario: Cache breakpoints at required positions

- **WHEN** 请求包含 system、tools 与 user 消息
- **THEN** 三个缓存断点分别出现在 system 块、最后工具定义与最后 user 内容块

#### Scenario: Long retention adds TTL

- **WHEN** `cache_retention == "long"` 且 `compat["supportsLongCacheRetention"]` 为真
- **THEN** 每个 `cache_control` 都包含 `"ttl":"1h"`

#### Scenario: Short retention has no TTL

- **WHEN** `cache_retention != "long"`
- **THEN** `cache_control` 仅含 `{"type":"ephemeral"}`

### Requirement: Anthropic SSE event mapping

Provider SHALL 把 `message_start`、`content_block_start/delta/stop`、`message_delta`、`message_stop`、`error` 分别映射为 `StartEvent`、块级 start/delta/end、final 更新、`DoneEvent` 与 `ErrorEvent`；`ping` MUST 被忽略；stop reason MUST 按 `end_turn`/`stop_sequence → stop`、`max_tokens → length`、`tool_use → toolUse`、其他 → stop 映射。

#### Scenario: Text block lifecycle

- **WHEN** 收到 text 块的 start、多个 delta 与 stop
- **THEN** 发出 `text_start`、对应 `text_delta` 与 `text_end`

#### Scenario: Tool input JSON accumulates

- **WHEN** 收到 `input_json_delta` 片段
- **THEN** 片段按 content block 下标聚合为 `ToolCall.arguments`

#### Scenario: Message stop emits done

- **WHEN** 收到 `message_stop`
- **THEN** 发出 `DoneEvent`，其 reason 来自最近的 stop reason 映射

#### Scenario: Error event terminates the stream

- **WHEN** 收到 Anthropic `error` 事件
- **THEN** 发出 `ErrorEvent` 且流关闭

### Requirement: Anthropic usage and write-1h accounting

Provider SHALL 读取 `input_tokens`、`output_tokens`、`cache_read_input_tokens`、`cache_creation_input_tokens`，并在存在 `cache_creation.ephemeral_1h_input_tokens` 时写入 `usage.cache_write_1h`；生成 usage 后 MUST 调用 `apply_cost!` 计算成本。

#### Scenario: Cache creation and 1h tokens are recorded

- **WHEN** 响应含 `cache_creation_input_tokens` 与 `ephemeral_1h_input_tokens`
- **THEN** `usage.cache_write` 与 `usage.cache_write_1h` 分别对应两者

#### Scenario: Cost uses model rates

- **WHEN** 模型定义了 input/output/cache 费率
- **THEN** usage 生成后 `cost` 的对应字段与总价被填充
