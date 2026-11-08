# RULES — PiKit 日志硬纪律

> 本文件只约束日志。shell/git/提交/编辑纪律不在本文件范围。

## 文件标识（TAG）

- 每个含日志的 Julia 源文件顶部（模块与 `using` 之后）声明：
  `const LOG_TAG = "<文件名去扩展名>"`。
- 小写 + 下划线；嵌套目录用 `<目录>_<文件>`，例如 `src/coding/tools/read.jl → coding_tools_read`。
- 禁止中文 tag、无 tag、用模块名/函数名/类名代替。
- tag 必须与文件路径唯一对应；重命名文件时同步修改。

## 调用形式

- 统一使用 stdlib `Logging`：
  - `@info "message" _group=LOG_TAG key=value`
  - `@warn "message" _group=LOG_TAG key=value`
  - `@error "message" _group=LOG_TAG exception=(e, catch_backtrace())`
  - `@debug "message" _group=LOG_TAG key=value`
- 必须用 `_group=LOG_TAG`，不要只写普通 `tag=` 键：Julia 的 `shouldlog` 只能看到 `group`，按文件过滤依赖 `_group`。
- 日志文本用英文；结构化信息优先放键值，不拼字符串。
- 禁止用 `println` / `@printf` 当日志；JSON/RPC 的 stdout 只属于协议。

## 级别

- `info`：状态切换与关键动作（启动、模型选择、会话创建/恢复、压缩开始/结束、工具注册、模式切换）。
- `warn`：可恢复异常（Provider 回退、重试、权限异常、截断）。
- `error`：失败（Provider 错误、工具失败、会话写失败、未捕获异常）。
- `debug`：高频/调试路径（逐 delta、SSE 行、参数归一细节）。
- 默认 `info`；`debug` 默认关闭。

## 输出与过滤（方案 C）

- 默认只写文件：`~/.pikit/agent/logs/app.log`。
- 路径优先级：`PIKIT_LOG_FILE` > `PIKIT_AGENT_DIR` > `~/.pikit/agent`。
- 默认级别 `info`；`PIKIT_LOG=debug` 全局；`PIKIT_LOG=ai_json=debug,coding_tools_bash=debug` 按 tag。
- stderr 默认关闭；`PIKIT_LOG_STDERR=1` 才镜像到 stderr。
- 文件 sink 打开或写入失败：向 stderr 警告一次，后续降级为 stderr-only，不得中断请求。
- JSON/RPC 的 stdout 只写协议；日志不得进入 stdout。
- 文件 sink 追加写，进程内加锁；不重复打开文件。

## 错误不静默

- 禁止裸 `catch`、`catch; nothing`、`try ... catch; end`。
- 预期缺失用显式分支（`ispath`、`=== nothing`）并 `@debug`。
- 重试前 `@warn`；最终失败 `@error`。

## 脱敏

- `info/warn/error` 禁止记录 `Authorization`、`x-api-key`、API key、完整请求体。
- `debug` 记录 payload 前必须脱敏。
- 错误消息保留状态码与端点，不保留凭据。

## 测试

- 测试用 `mktempdir()` / `PIKIT_AGENT_DIR`，不得写真实 `~/.pikit`。
- 用 `Logging.with_logger` 或临时文件捕获；断言 tag、级别与文件内容。
- 断言 JSON/RPC 模式 stdout 无日志。
