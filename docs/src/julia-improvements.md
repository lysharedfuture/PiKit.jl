# Julia 改进建议记录

> 规范：`specs/development-process/spec.md`。本文记录一期 W1–W5、二期 2A–2D、三期 3A–3E 的实际观察、上游约束与 Julia 替代方案。
> 每波至少 3 条；必选 ID 与主题以规范中的 Required topics 表为准。
> 发现上游差异时先写 `上游`/`观察`，在该 wave 结束前补齐 `Julia 方案`/`结论`；不要留到该期发布前补写。

## 记录格式

```markdown
### <wave-id>-<nn> <主题>
- 上游：<path>:<line>
- 观察：TypeScript 做法与约束。
- Julia 方案：Julia 替代与原因。
- 结论：采纳 | 建议上游 | Julia 生态缺口
```

字段规则：

- `上游`：`.upstream` 下的 `<path>:<line>`。
- `观察`：TypeScript 做法与约束，写事实，不写评价。
- `Julia 方案`：本实现采用的替代与原因。
- `结论`：`采纳` / `建议上游` / `Julia 生态缺口`。

## W1 AI 层

### W1-01 异步流：AsyncIterator vs Channel/Task

- 上游：packages/ai/src/types.ts:1
- 观察：Provider 以 `AsyncIterable<AssistantMessageEvent>` 暴露流，消费方 `for await` 逐事件处理；事件对象携带共享的 `partial` 消息引用。
- Julia 方案：`AssistantMessageEventStream` 包装 `Channel(32)` 与生产者 `Task`，用背压保持内存线性；`Base.iterate` 委托 channel，`result` 等待 task；`partial` 明确为共享实时对象，需要快照的消费方自行复制。
- 结论：采纳

### W1-02 SSE 客户端解析

- 上游：packages/ai/src/api/openai-completions.ts:1
- 观察：OpenAI/Anthropic 适配器都手写逐行 SSE 解析：去 CR、`data:` 多行拼接、注释忽略、空行 dispatch、EOF flush。
- Julia 方案：`foreach_sse(f, io; signal)` 用 `readline` 逐行解析并在每行前轮询 `AbortToken`；中途中止时关闭 body 解除阻塞，返回而不抛异常。
- 结论：采纳

### W1-03 JSON Schema 校验错误路径

- 上游：packages/ai/src/utils/validation.ts:1
- 观察：工具参数校验失败时错误消息包含工具名、JSON 路径与原因；`argumentsError` 短路 schema 校验并直接作为失败信息。
- Julia 方案：`validate_arguments(name, schema, args)` 递归实现关键字子集并在路径中使用 `$`、`.prop`、`[i]`；`ToolCall.arguments_error` 非空时由 AgentCore 直接生成失败结果。
- 结论：采纳

## W2 AgentCore

### W2-01 AbortSignal vs `AbortToken` + IO close

- 上游：packages/agent/src/agent-loop.ts:1
- 观察：AgentCore 通过 DOM `AbortSignal` 传播取消，HTTP body、工具进程与重试 sleep 分别监听 abort 事件。
- Julia 方案：`AbortToken` 提供 `abort!`/`on_abort`/`is_aborted`，阻塞点轮询；HTTP body 与子进程在 abort 回调中关闭/杀进程树；`on_abort` 在锁外执行回调避免重入。
- 结论：Julia 生态缺口

### W2-02 `Promise.all` 并发与事件顺序

- 上游：packages/agent/src/agent-loop.ts:1
- 观察：工具批次默认并行，`tool_execution_end` 按完成顺序发出，而 `toolResult` 消息按 assistant 源顺序写入 transcript。
- Julia 方案：`@async` 执行并在完成时发结束事件，收集结果后按源顺序生成 `ToolResultMessage`；所有 emit 经 `ReentrantLock` 串行化。
- 结论：采纳

### W2-03 结构化消息 union vs 抽象类型

- 上游：packages/ai/src/types.ts:1
- 观察：TypeScript 用 discriminated union 表示 `System|User|Assistant|ToolResult|Custom` 消息，CodingAgent 自定义消息也参与同一 union。
- Julia 方案：以 `AbstractMessage` 为根，四个 LLM 消息与 `BashExecutionMessage`/`CompactionSummaryMessage` 子类型继承；`coding_convert_to_llm` 显式转换/丢弃未知类型。
- 结论：采纳

## W3 CodingAgent 工具

### W3-01 进程组超时/杀树

- 上游：packages/coding-agent/src/utils/shell.ts:1
- 观察：bash 以 detached 进程组启动，超时或中止时 `SIGKILL` 整个进程组；macOS 先 `SIGSTOP`，Windows 使用 `taskkill /F /T`。
- Julia 方案：`detach(cmd)` 创建独立会话，`ccall(:kill, -pid)` 杀组并回退到单进程；Windows 调 `System32\taskkill.exe`；超时/中止后等待进程回收。
- 结论：采纳

### W3-02 rg/fd 外部工具管理与 `.gitignore` 语义

- 上游：packages/coding-agent/src/utils/tools-manager.ts:1
- 观察：grep/find 复用 ripgrep/fd 的 `.gitignore`、隐藏文件与二进制跳过语义；上游通过外部工具路径解析，且新包不应在运行时下载第三方二进制。
- Julia 方案：`grep` 使用 `ripgrep_jll.rg()`，由 Pkg/Artifacts 提供全平台二进制；`find` 等待 fd_jll（Yggdrasil `F/fd`）后替换现有 fd 下载；在 JLL 可用前保留临时 `ensure_tool` 路径。
- 结论：采纳

### W3-03 文本 diff 实现

- 上游：packages/coding-agent/src/core/tools/edit-diff.ts:1
- 观察：edit 返回结构化 `diff` 与 unified `patch`，按行显示增删。
- Julia 方案：`_line_diff` 使用 LCS 动态规划生成行级 diff，`_unified_patch` 加 `---/+++` 头；仅用于展示，不参与写回。
- 结论：采纳

### W3-04 子进程环境继承与 `PI_*` 覆盖

- 上游：packages/coding-agent/src/utils/shell.ts:1
- 观察：`getShellEnv` 复制父进程环境，仅覆盖 `PATH` 前缀与 `PI_*` 会话变量，不剥离 `*_API_KEY`/`*_TOKEN`。
- Julia 方案：`get_shell_env` 复制 `ENV`，删除并重设五个 `PI_*` 键，`PATH` 前置 `PIKIT_AGENT_DIR/bin`；安全边界明确为 OS 用户权限。
- 结论：采纳

### W3-05 login shell 取舍

- 上游：packages/coding-agent/src/utils/shell.ts:1
- 观察：默认使用非 login shell，避免 `.bashrc`/`.profile` 的输出与别名污染工具执行；Windows 优先 Git Bash。
- Julia 方案：`get_shell_config` 对齐上游解析顺序（自定义 shellPath → Git Bash → `/bin/bash` → PATH bash → sh），不提供 login shell 开关。
- 结论：采纳

## W4 CLI 与模式

### W4-01 CLI 解析与 `@file`/`--`

- 上游：packages/coding-agent/src/cli/args.ts:1
- 观察：CLI 支持 `--` 终止选项、`@file` 注入 prompt/图片、可重复选项与工具增删表达式。
- Julia 方案：`parse_cli` 手写解析器，保持短/长选项、`--`、`@file`、`--tools +/-` 与退出码语义；图片扩展名读取为 base64。
- 结论：采纳

### W4-02 REPL 的 Ctrl+C 中止

- 上游：packages/coding-agent/src/cli/args.ts:1
- 观察：REPL 运行中 Ctrl+C 触发 abort，随后仍可继续输入下一条消息。
- Julia 方案：prompt 在独立 `Task` 中运行，主任务捕获 `InterruptException` 后 `abort!` 并等待任务结束；REPL 循环继续。
- 结论：采纳

### W4-03 无差分渲染 TUI 的取舍

- 上游：packages/coding-agent/src/cli/args.ts:1
- 观察：上游交互式 TUI 使用全屏差分渲染、组件树与主题系统。
- Julia 方案：一期只做行式 REPL，流式输出 text/thinking 与工具状态；全屏 TUI 与主题留到二期，避免引入终端渲染依赖。
- 结论：Julia 生态缺口

## W5 会话、压缩与发布

### W5-01 会话树/压缩 token 估算

- 上游：packages/coding-agent/src/core/compaction/compaction.ts:1
- 观察：上游以 chars/4 估算消息 token，优先使用最后一条有效 assistant 的 usage 作为锚点，只估算其后的尾部消息。
- Julia 方案：`estimate_tokens` 按消息类型计 chars/4，image 固定 4800 字符；`estimate_context_tokens` 锚定最后 usage 并只估算尾部；压缩切点回退到 user 轮次起点。
- 结论：采纳

### W5-02 v3 兼容读取的未知 entry 策略

- 上游：packages/coding-agent/src/core/session-manager.ts:1
- 观察：v3 会话允许扩展自定义 entry；读取方必须保留未知 entry 的 `id`/`parentId`/`timestamp` 才能维持树链。
- Julia 方案：未知类型解析为 `UnknownEntry` 并保留原始 JSON，不写回；已知 entry 的未识别键进入 `extra`，`to_json` 先复制 `extra` 再覆盖已知字段。
- 结论：采纳

### W5-03 补充主题：失败 assistant 不写会话

- 上游：packages/coding-agent/src/core/session-manager.ts:1
- 观察：上游保留失败 assistant 消息，并用 `context_edit{replacement:null}` 从模型上下文排除；读取侧兼容该排除语义。
- Julia 方案：一期 `message_end` 只持久化 user/toolResult/bashExecution 与成功 assistant；读取上游会话时应用 `context_edit` 的 null 排除（含其 toolResult），替换语义留到二期。
- 结论：建议上游

## 二期（v0.2–v0.4）

2A–2D 主题已在 `specs/development-process/spec.md` 登记；各条目在该 wave 收口前补齐四字段，未收口的条目只有标题。

## 2A 包边界与依赖方向

### 2A-01 包边界与依赖方向

- 上游：packages/coding-agent/package.json:44
- 观察：上游按 npm 包分层发版：`pi-coding-agent` 依赖 `pi-agent-core` 与 `pi-ai`，`pi-agent-core` 只依赖 `pi-ai`（`packages/agent/package.json:26`）；依赖方向单向，由包管理器强制。
- Julia 方案：单体仓库拆为四个包（`PiAI ← PiAgentCore ← PiCodingAgent ← PiKit`），依赖写入各自 `Project.toml` 的 `[deps]`/`[compat]`，开发期用相对 `[sources]` 解析；`scripts/check-package-boundaries.jl` 静态校验 `using`/`import`/`include`/限定名，禁止反向依赖与跨包 `include`。
- 结论：采纳

### 2A-02 类型身份与模块别名

- 上游：packages/ai/src/index.ts:1
- 观察：每个上游包只有一个模块实例，类型身份由包入口唯一决定；`pi-ai` 入口保持 side-effect free，provider 工厂与注册放在子路径导出，避免根导入触发全局注册。
- Julia 方案：子包源码只以包名限定引用（`PiAI.*`），不复制模块；`PiKit` 用 `const AI = PiAI` 等别名保持一期路径，`PiKit.AI === PiAI` 保证类型身份唯一；provider 注册只在 `PiAI.__init__`，`PiKit.__init__` 不再重复调用，避免 `PROVIDER_MODELS` 出现重复项。
- 结论：采纳

### 2A-03 日志安装点与库设计

- 上游：packages/coding-agent/src/core/crash-log.ts:1
- 观察：上游把日志落盘放在应用层：`coding-agent` 的 `core/crash-log.ts` 读取 agent dir 并写文件，可复用库不接管全局输出。
- Julia 方案：子包只使用 stdlib `Logging` 的宏与 `_group=LOG_TAG`；文件 sink（`TagFilterLogger`/`install_logging!`）只在 `PiKit.__init__` 安装一次；单独 `using PiAI` 保留调用方 logger，测试用 `with_logger` 或子进程断言未创建日志文件。
- 结论：采纳

## 2B 持久运行时

### 2B-01 持久存储格式与单写者

### 2B-02 effect 三明治与 replay 策略

### 2B-03 deferred 轮询与崩溃恢复

### 2B-04 文档事务子集与 chord 替代

## 2C AI Provider 扩展

### 2C-01 HTTP/SSE 手写 vs 厂商 SDK

### 2C-02 OAuth 与凭据存储

### 2C-03 长缓存与 provider 能力矩阵

### 2C-04 AWS SigV4 与二进制 event-stream

## 2D Schema、MCP 与遥测

### 2D-01 JSON Schema 编译与 unevaluated 语义

### 2D-02 ECMA 正则兼容

### 2D-03 MCP 传输与工具桥接

### 2D-04 遥测显式上下文与脱敏

## 三期（v0.5–v1.0）

未开始。3A–3E 启动前须在 `specs/development-process/spec.md` 登记必选主题与 ID，再按同一格式记录，每波至少 3 条。
