# provider-openai-completions

## Purpose

定义 `openai-completions` Provider 的请求翻译、流式增量聚合、工具参数容错与 HTTP 错误语义。该能力覆盖 OpenAI 及兼容端点（DeepSeek、Ollama、网关），通过模型级 `compat` 开关吸收方言差异，并保持与上游 `pi-ai` 相同的事件序列。

## Requirements

### Requirement: OpenAI-compatible request translation

Provider SHALL 向 `rstrip(base_url, '/') * "/chat/completions"` 发送带 `Authorization: Bearer`、`content-type` 与 `user-agent: pikit/<version>` 的流式请求；请求体 MUST 包含 `model`、`messages`、`stream=true`，并在工具或兼容开关允许时写入 `tools`、`tool_choice`、`max_tokens`/`max_completion_tokens`、`reasoning_effort`、`stream_options`、缓存键与保留档位。

#### Scenario: Tool history keeps an empty tools array

- **WHEN** 本次请求没有工具，但历史消息含 `tool_calls` 或工具结果
- **THEN** 请求体仍发送 `"tools": []`

#### Scenario: Image content becomes a data URL

- **WHEN** 用户消息包含图片块
- **THEN** 图片被转换为 `image_url` 且 URL 为 `data:<mime>;base64,<data>`

#### Scenario: Unsupported dialect fields are omitted

- **WHEN** 模型 `compat` 未启用 `supportsUsageInStreaming` 或 `supportsReasoningEffort`
- **THEN** 请求体不包含 `stream_options.include_usage` 或 `reasoning_effort`

#### Scenario: Assistant tool calls are re-encoded

- **WHEN** assistant 消息包含 `ToolCall`
- **THEN** 输出 `tool_calls` 数组，`function.arguments` 是 JSON 字符串

### Requirement: Streaming delta aggregation

Provider SHALL 将 `choices[0].delta.content` 映射为文本增量、`reasoning_content`/`reasoning` 映射为 thinking 增量、`delta.tool_calls` 按 `index` 聚合 `id`/`name`/`arguments`；`finish_reason` MUST 映射为 `stop`、`length`、`toolUse` 或 `error`，usage MUST 从 token 字段与缓存明细读取。

#### Scenario: Text deltas form block events

- **WHEN** 收到多个 `delta.content` 片段
- **THEN** 发出对应 `text_start`/`text_delta`/`text_end` 事件

#### Scenario: Parallel tool calls aggregate by index

- **WHEN** 同一响应含两个不同 `index` 的 tool call 增量
- **THEN** 分别聚合为两个 `ToolCall`，不互相覆盖

#### Scenario: Finish reason maps to stop reason

- **WHEN** `finish_reason` 为 `tool_calls`
- **THEN** 最终消息 `stop_reason == "toolUse"`

#### Scenario: Usage includes cached tokens

- **WHEN** 响应含 `prompt_tokens_details.cached_tokens`
- **THEN** `usage.cache_read` 等于该值

### Requirement: Tool-call argument salvage

Provider SHALL 在工具调用结束时解析累积的参数文本；若解析失败 MUST 截断到最后一个完整值并尝试补齐 `}`/`]`/`"`；仍失败时 MUST 使用空 `arguments` 并写入含说明与模型原始参数文本的 `arguments_error`。

#### Scenario: Truncated JSON is repaired

- **WHEN** 累积参数为缺少结尾括号的合法 JSON 前缀
- **THEN** 补齐后得到非空参数对象且 `arguments_error` 为空

#### Scenario: Unrecoverable arguments are reported

- **WHEN** 参数文本无法通过截断与补齐修复
- **THEN** `arguments == {}` 且 `arguments_error` 含原始参数文本

### Requirement: HTTP failure and pre-stream retry

Provider SHALL 在非 2xx 时读取不超过 64KB 的响应体并发出 `ErrorEvent`，其错误消息含 `HTTP <status>: <body>`；连接失败、429 与 5xx MUST 仅在首个流事件发出前按指数退避重试，遵守 `Retry-After` 且不超过 `max_retry_delay_ms`；一旦发出事件 MUST NOT 重试。

#### Scenario: Non-2xx is encoded as an error message

- **WHEN** 服务端返回 401 与错误体
- **THEN** `ErrorEvent.error.stop_reason == "error"` 且 `error_message` 含状态码与响应体

#### Scenario: Retry before the first event

- **WHEN** 首个事件前收到 503 且仍有重试预算
- **THEN** 按退避延迟重新发送请求，事件流对上层保持透明

#### Scenario: No retry after streaming starts

- **WHEN** 已经发出文本增量后连接中断
- **THEN** 不再重发请求，流以错误事件结束
