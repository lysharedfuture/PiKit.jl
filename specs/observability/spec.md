# observability

## Purpose

定义 PiKit 的本地日志纪律：每文件唯一 TAG、级别语义、默认文件 sink 与按 tag 过滤、stderr 显式 opt-in，以及失败不静默、脱敏与协议流纯净。该能力只描述诊断日志，不包含 telemetry 导出；日志格式不是稳定的 telemetry schema。

## Requirements

### Requirement: Per-file log tag

每个含日志的源文件 SHALL 声明 `const LOG_TAG = "<文件名去扩展名>"`，并在所有日志调用中使用 `_group=LOG_TAG`；tag MUST 为小写加下划线，嵌套目录使用 `<目录>_<文件>`，且 MUST 与文件路径唯一对应。

#### Scenario: Tag matches the file path

- **WHEN** 文件 `src/coding/tools/read.jl` 记录日志
- **THEN** 其 `LOG_TAG == "coding_tools_read"`，记录携带 `_group="coding_tools_read"`

#### Scenario: Tag filtering uses the group

- **WHEN** 配置 `PIKIT_LOG=coding_tools_read=debug`
- **THEN** 只有该 group 的 debug 记录被写出，其他 group 仍按默认 `info` 过滤

#### Scenario: Invalid tag is rejected by review

- **WHEN** 文件使用中文 tag、模块名或缺失 `LOG_TAG`
- **THEN** 日志审计失败并要求改为文件名派生的 tag

### Requirement: Log level semantics

日志 SHALL 使用英文文本；`info` MUST 表示状态切换与关键动作，`warn` 表示可恢复异常，`error` 表示失败，`debug` 表示高频或调试路径；默认级别 MUST 为 `info`，`debug` MUST 默认关闭。

#### Scenario: Debug is off by default

- **WHEN** 未设置 `PIKIT_LOG`
- **THEN** `debug` 记录不写出，`info`/`warn`/`error` 按配置写出

#### Scenario: Recoverable failure warns before retry

- **WHEN** Provider 请求失败且即将重试
- **THEN** 记录 `warn`，包含尝试次数与错误分类，不记录密钥

#### Scenario: Final failure is an error

- **WHEN** 工具执行或会话写入最终失败
- **THEN** 记录 `error`，必要时附带异常与回溯

### Requirement: File sink and stderr opt-in

日志 SHALL 默认只写 `~/.pikit/agent/logs/app.log`；路径优先级 MUST 为 `PIKIT_LOG_FILE` > `PIKIT_AGENT_DIR` > `~/.pikit/agent`；stderr MUST 默认关闭，仅当 `PIKIT_LOG_STDERR=1` 时镜像；`PIKIT_LOG` MUST 支持全局级别与 `tag=level` 列表。

#### Scenario: Default output is file-only

- **WHEN** 运行 CLI 且未设置 `PIKIT_LOG_STDERR`
- **THEN** stderr 不出现日志行，日志写入默认文件

#### Scenario: Stderr mirror is explicit

- **WHEN** 设置 `PIKIT_LOG_STDERR=1`
- **THEN** 每条满足级别与 tag 过滤的日志同时出现在 stderr

#### Scenario: File sink failure degrades safely

- **WHEN** 日志文件无法打开或写入
- **THEN** 向 stderr 警告一次，后续降级为 stderr-only，请求本身不失败

#### Scenario: Tests do not touch the real home

- **WHEN** 测试创建 logger
- **THEN** 使用 `mktempdir()` 或 `PIKIT_AGENT_DIR`，不写入真实 `~/.pikit`

### Requirement: No silent error swallowing

代码 MUST NOT 使用裸 `catch`、`catch; nothing` 或 `try ... catch; end` 吞掉错误；预期缺失 MUST 用显式分支处理并可记录 `debug`；重试前 MUST 记录 `warn`，最终失败 MUST 记录 `error`。

#### Scenario: Unexpected exception is logged

- **WHEN** 工具执行抛出未预期异常
- **THEN** 循环记录 `error` 并保留异常与回溯，然后按工具失败语义返回结果

#### Scenario: Expected absence is not an error

- **WHEN** 可选文件或可选配置不存在
- **THEN** 使用显式存在性分支处理，必要时记录 `debug`，不产生 `error` 噪音

### Requirement: Protocol stream purity and redaction

JSON 与 RPC 模式的 stdout MUST 只包含协议帧，日志 MUST NOT 写入 stdout；`info`/`warn`/`error` MUST NOT 记录 `Authorization`、`x-api-key`、API key 或完整请求体，`debug` 记录 payload 前 MUST 脱敏。

#### Scenario: JSON mode remains parseable

- **WHEN** 以 `--mode json` 运行并产生日志
- **THEN** stdout 每一行仍是合法 JSON 事件，日志不出现在 stdout

#### Scenario: Secrets are redacted

- **WHEN** 日志键为 `authorization`、`api_key` 或 `x-api-key`
- **THEN** 输出值为脱敏占位符，而非原始凭据

#### Scenario: Error text keeps diagnostics without credentials

- **WHEN** Provider 返回非 2xx
- **THEN** 错误日志包含状态码与端点，不包含请求头或密钥
