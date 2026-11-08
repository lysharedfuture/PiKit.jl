# ai-core

## Purpose

定义 PiKit 所有 Provider 共用的消息模型、JSON wire 形状、流式事件、用量与成本、参数校验、模型目录、凭据解析以及错误分类。该能力是 AgentCore 与 CodingAgent 的共同底座，必须在不依赖具体 Provider 的前提下保持与上游 `pi-ai` 的事件与字段兼容。

## Requirements

### Requirement: Message and content wire compatibility

`AI` 层 SHALL 以 `TextContent`、`ImageContent`、`ThinkingContent`、`ToolCall` 与 `SystemMessage`、`UserMessage`、`AssistantMessage`、`ToolResultMessage` 表示消息，并按 camelCase JSON 键名显式编解码；可选字段为 `nothing` 时 MUST 省略对应键，未识别的键 MUST 保存在 `extra` 并在重写时原样保留。

#### Scenario: Unknown fields survive a rewrite

- **WHEN** 读取含 `rawStopReason` 等未建模字段的 pi 消息并重新序列化
- **THEN** 该字段仍以原值出现在输出 JSON 中

#### Scenario: Absent optional fields are omitted

- **WHEN** 序列化 `text_signature = nothing` 的文本块
- **THEN** 输出的 JSON 对象不含 `textSignature` 键

#### Scenario: Section order is preserved

- **WHEN** 解析含多个 `sections` 的 system 消息
- **THEN** 结果保持文档中的键顺序，而不是哈希顺序

### Requirement: Streaming assistant events

流式 API SHALL 按 `start → (block start → delta* → end)* → done|error` 的顺序产出事件；块级事件 MUST 携带 `content_index`，最终事件 MUST 携带完整消息；Provider 失败 MUST 编码为 `ErrorEvent`（其 `error` 是完整 `AssistantMessage`），不得向调用方抛异常。

#### Scenario: Text stream completes normally

- **WHEN** Provider 依次发出文本增量并正常结束
- **THEN** 事件序列以 `DoneEvent(reason="stop")` 结束，且该块 `text_end.content` 等于此前全部 `text_delta` 的拼接

#### Scenario: HTTP failure becomes an error event

- **WHEN** Provider 收到非 2xx 响应
- **THEN** 流中发出 `ErrorEvent(reason="error")`，其 `error.stop_reason == "error"`，且迭代正常结束

#### Scenario: Abort terminates the stream

- **WHEN** 调用方在流式过程中触发中止
- **THEN** 最终消息的 `stop_reason == "aborted"`，流关闭且不抛出异常

### Requirement: Usage and cost accounting

`Usage` SHALL 记录 token 计数，`Cost` SHALL 记录美元金额；`apply_cost!` MUST 按每百万 token 费率计算四项成本、求和写入 `total`、应用最高匹配的定价阶梯，并在 Provider 直接给出账单金额时设置 `total_from_provider` 且不覆盖该金额。

#### Scenario: Cost is derived from token counts

- **WHEN** 某模型 input 费率为 3 USD/1M tokens 且 usage.input 为 1,000,000
- **THEN** `cost.input == 3.0` 且 `cost.total` 等于四项金额之和

#### Scenario: Highest matching tier applies to the whole request

- **WHEN** `cost.tiers` 含 `inputTokensAbove=200000` 的档位且 usage.input 为 300000
- **THEN** 整个请求按该档费率计算，而非分段计算

#### Scenario: Provider-reported total is preserved

- **WHEN** Provider 在 usage 中直接报告 `cost.total`
- **THEN** `total_from_provider == true` 且本地估算不覆盖该值

### Requirement: JSON Schema subset validation

`validate_arguments(tool_name, schema, args)` SHALL 支持 `type`、`properties`、`required`、`additionalProperties`、`enum`、`const`、`items`、`minItems`/`maxItems`、`minimum`/`maximum`、`minLength`/`maxLength`、`pattern` 与 `anyOf`/`oneOf`/`allOf`；校验失败 MUST 抛出含工具名、JSON 路径与原因的 `ArgumentError`；当 `tool_call.arguments_error` 非空时 MUST 直接用该文本失败，不再解析参数。

#### Scenario: Missing required field

- **WHEN** 必填字段缺失
- **THEN** 错误消息包含工具名、缺失字段路径与原因

#### Scenario: Extra field rejected when schema forbids it

- **WHEN** `additionalProperties=false` 且参数含未声明字段
- **THEN** 校验失败并指出该额外字段

#### Scenario: Malformed raw arguments short-circuit validation

- **WHEN** 模型返回的参数文本不是合法 JSON 对象
- **THEN** 工具结果直接报告该说明与模型原始参数，而不是抛出解析异常

### Requirement: Model catalog and credential resolution

`load_models` SHALL 合并内置 `models.json` 与 `~/.pikit/models.json` 的用户覆盖；`find_model` MUST 支持 `provider/id`、精确 id、大小写不敏感子串，并为未知 `provider/id` 合成默认模型；`resolve_api_key` MUST 按 CLI 覆盖、`auth.json`、Provider `$VAR`、环境变量的顺序解析。

#### Scenario: User model overrides built-in entry

- **WHEN** 用户 `models.json` 定义了同 provider/model id 的条目
- **THEN** 查询结果使用用户条目的字段值

#### Scenario: Unknown provider model gets defaults

- **WHEN** 查询形如 `provider/unknown-model` 且目录中没有该模型
- **THEN** 返回 `context_window=128000`、`max_tokens=16384`、`reasoning=false` 的合成模型并只警告一次

#### Scenario: Credential precedence

- **WHEN** CLI 覆盖与 `auth.json` 同时提供 key
- **THEN** CLI 覆盖优先；不存在 CLI 覆盖时 `auth.json` 优先于环境变量

#### Scenario: Loose auth file permissions warn

- **WHEN** `auth.json` 权限不是 0600
- **THEN** stderr 输出警告但仍然读取其中 key

### Requirement: Retry and overflow classification

`is_retryable_assistant_error` SHALL 先排除配额/账单类错误，再匹配可重试模式；`is_context_overflow` MUST 识别错误文本中的各 Provider 溢出模式、静默超窗 usage，以及 `length` 且零输出的情况，并排除限流文本。

#### Scenario: Quota 429 is not retryable

- **WHEN** 429 响应体包含 `insufficient_quota`
- **THEN** 分类结果为不可重试

#### Scenario: Transient server error is retryable

- **WHEN** 错误文本包含 `overloaded` 或 `stream disconnected`
- **THEN** 分类结果为可重试

#### Scenario: Silent over-window usage is overflow

- **WHEN** 响应 `stop_reason=="stop"` 且 `usage.input + usage.cache_read` 超过模型 `context_window`
- **THEN** 判定为上下文溢出

#### Scenario: Rate limit is not misclassified as overflow

- **WHEN** 错误文本同时包含数字 413 与 `rate limit`
- **THEN** 不判定为上下文溢出

### Requirement: SSE stream parsing

`foreach_sse(io, f)` SHALL 支持 CRLF、多行 `data:`、`:` 注释、空行 dispatch 与 EOF flush，并在每行前检查中止状态；MUST NOT 把 U+2028/U+2029 当作行分隔符。

#### Scenario: CRLF input parses like LF input

- **WHEN** 同一事件以 CRLF 行尾到达
- **THEN** 解析出的字段与 LF 输入一致

#### Scenario: Multiple data lines are joined

- **WHEN** 一个事件包含两行 `data:`
- **THEN** 两段内容以 `\n` 连接后交给回调

#### Scenario: EOF without trailing blank line

- **WHEN** 流在事件后没有空行即结束
- **THEN** 已缓冲的事件仍被 dispatch 一次

### Requirement: Assistant event stream lifecycle

`AssistantMessageEventStream` SHALL 由有界 `Channel`、`Task` 与最终消息 `Ref` 组成，支持迭代、`eltype` 与 `result`；`partial` MUST 是共享的实时消息而非事件时快照，需要留存历史的消费方自行深拷贝。

#### Scenario: Result matches the final message

- **WHEN** 消费完一个正常结束的流并调用 `result`
- **THEN** 返回值等于最后一条 `done`/`error` 事件携带的消息

#### Scenario: Start event exposes pending message

- **WHEN** 收到 `StartEvent`
- **THEN** 其 `partial.stop_reason == "pending"` 且 `content` 为空

### Requirement: Cooperative cancellation token

`AbortToken` SHALL 提供 `abort!`、`on_abort` 与 `is_aborted`；`abort!` MUST 幂等，回调 MUST 在释放锁后按注册顺序调用；注册晚于中止时 MUST 立即执行回调；状态读取 MUST 使用锁或原子量避免数据竞争。

#### Scenario: Repeated abort is idempotent

- **WHEN** 对同一令牌调用两次 `abort!`
- **THEN** 已注册回调只执行一次

#### Scenario: Late registration runs immediately

- **WHEN** 在中止后注册新回调
- **THEN** 该回调立即执行，而不是等待下一次中止

#### Scenario: Callback re-entry does not deadlock

- **WHEN** 中止回调内部再次调用 `on_abort` 或 `abort!`
- **THEN** 调用返回且不发生在锁内重入的死锁

### Requirement: Provider dispatch and stream options

`stream(model, ctx, opts)` SHALL 通过 `PROVIDERS` 按 `model.api` 分派，未注册 api MUST 返回错误流；`StreamOptions` MUST 支持 `on_payload`（可整包替换请求体，返回 `nothing` 表示不改）、`on_response`（收到响应头后、消费 body 前调用）、`timeout_ms` 与仅限首事件前的 `max_retries`；一期的 `fetch`、`telemetry`、`onProviderStreamEvent`、`transport` MUST 不进入公开接口。

#### Scenario: Unregistered API returns an error stream

- **WHEN** 模型 `api` 没有注册 Provider
- **THEN** 返回的流以错误事件结束，而不是抛出异常

#### Scenario: Payload hook replaces the request body

- **WHEN** `on_payload` 返回新的 payload
- **THEN** HTTP 实际发送该替换后的对象

#### Scenario: Response hook observes status before body

- **WHEN** 收到非 2xx 响应头
- **THEN** `on_response` 在读取错误体之前被调用并收到状态码
