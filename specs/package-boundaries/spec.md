# Capability Spec: package-boundaries

## Purpose

定义二期拆包后的 Julia 包边界：目录与 manifest、单向依赖、公开 API 连续性、CLI 层级、日志安装点、独立测试与注册，以及拆包前后必须保持一致的外部行为。目标是让 `PiAI`、`PiAgentCore`、`PiCodingAgent` 可单独依赖，同时 `PiKit 0.2` 对一期用户保持源码兼容。

## ADDED Requirements

### Requirement: Package graph and dependency direction

仓库 MUST 提供 `PiAI`、`PiAgentCore`、`PiCodingAgent`、`PiKit` 四个包，依赖方向 MUST 为 `PiAI ← PiAgentCore ← PiCodingAgent ← PiKit`。2A 时点：`PiAI` MUST 只依赖 `HTTP`、`JSON` 与标准库；`PiAgentCore` MUST 只依赖 `PiAI` 与 `Logging`；`PiCodingAgent` MUST 只依赖 `PiAI`、`PiAgentCore`、`HTTP`、`ripgrep_jll` 与标准库（`fd_jll` 注册后加入）；`PiKit` MUST 依赖三者与 `Logging`/`Dates`/`Base64`。后续阶段允许的向下依赖（2D 的 `PiSchema`/`PiTelemetry`、`PiCodingAgent` 对 `PiMCP` 的弱依赖、2B 的 `PiDurable`）MUST 在对应变更中显式声明；本要求禁止的是反向依赖、跨层依赖与对 `PiKit` 的依赖，而不是冻结依赖集合。任何违规 MUST 使边界检查失败。

#### Scenario: Reverse dependency is rejected

- **WHEN** `PiAI/src` 中出现 `using PiAgentCore`、`import PiKit` 或对兄弟包源码目录的 `include`
- **THEN** `scripts/check-package-boundaries.jl` 返回非零状态并指出文件与符号

#### Scenario: Each package instantiates alone

- **WHEN** 在仅含该包与其依赖的临时环境中执行 `Pkg.instantiate()`
- **THEN** 解析成功，且不会拉入 `PiKit` 或更高层包

### Requirement: Public API continuity

`PiKit` MUST 以 `const AI = PiAI`、`const AgentCore = PiAgentCore`、`const CodingAgent = PiCodingAgent` 暴露与一期相同的模块路径，并 MUST 继续导出 `main`。

`PiKit.AI` 与 `PiKit.AgentCore` 导出的每个符号 MUST 继续由对应包导出；`PiKit.CodingAgent` 的**库符号**（工具、会话、压缩、system prompt、runtime、config）MUST 继续由 `PiCodingAgent` 导出，且新包导出集合 MUST 是该集合的超集。

CLI 层符号（`parse_cli`、`CLIOptions`、`CLIError`、`HELP_TEXT`、`list_models_text`、`resolve_tool_names`、`initial_prompt`、`run_print_mode`、`run_json_mode`、`run_rpc_mode`、`run_repl_mode`、`json_mode_event`、`session_json_event`、`build_runtime`、`main`）MUST 随 CLI 迁入 `PiKit` 并由 `PiKit` 导出；`PiCodingAgent` MUST NOT 导出或实现它们。迁移说明 MUST 记录 `PiKit.CodingAgent.main` → `PiKit.main` 以及 CLI 符号的归属变化。

#### Scenario: Existing module paths still resolve

- **WHEN** 执行 `using PiKit; PiKit.AI.TextContent("x"); PiKit.AgentCore.Tool; PiKit.main`
- **THEN** 三个表达式均解析到拆包后的对应包，类型与一期相同

#### Scenario: Library symbol sets are supersets of v0.1

- **WHEN** 对一期三个模块与对应新包分别取导出符号集合，并排除 CLI 层符号
- **THEN** 新包集合包含一期的库符号集合，差集只允许新增符号

#### Scenario: CLI symbols leave the library package

- **WHEN** 检查 `PiCodingAgent` 的导出集合
- **THEN** 不存在 `main` 或任何 CLI 层符号；它们由 `PiKit` 导出

### Requirement: CLI layer ownership

CLI 入口与模式实现 MUST 只位于 `PiKit`：参数解析、`print`/`json`/`rpc`/`repl` 模式、入口与 runtime 装配 MUST 在 `PiKit` 的 `src/cli/`（或等价目录）。`PiKit` MUST 同时暴露 `(@main)(args)` 与 `main()`：`julia -m PiKit ...` 使用前者，`bin/pikit` MUST 调用后者。`PiKit` 是 CLI/聚合层（D6 已定），MUST NOT 新增核心 AI/agent/工具/会话 API，也不是第四个核心包；v1.0 API 对等以 `PiAI`/`PiAgentCore`/`PiCodingAgent`/`PiDurable` 为准。`PiCodingAgent` MUST 只包含可复用库能力（工具、会话、压缩、system prompt、agent session），MUST NOT 依赖 CLI 参数形状或进程退出码。

#### Scenario: Library package does not import CLI

- **WHEN** 检查 `PiCodingAgent` 的 `using`/`import`
- **THEN** 不出现 `PiKit`、`ARGS`、`exit` 或 CLI 模式模块

#### Scenario: CLI behavior is unchanged

- **WHEN** 以 `pikit -p "hello" --mode json` 运行 faux 场景
- **THEN** stdout 的 JSON 事件序列与 v0.1 快照逐行一致

#### Scenario: Installed and repository entry points agree

- **WHEN** 分别执行 `julia -m PiKit --version` 与 `bin/pikit --version`
- **THEN** 两者输出相同版本并以 0 退出

### Requirement: Logging installation boundary

子包 MUST 使用标准库 `Logging` 的 `@info`/`@warn`/`@error`/`@debug` 并携带 `_group=LOG_TAG`，MUST NOT 自行安装全局 logger、写 stdout 或假定 `~/.pikit` 存在。`PiKit` MUST 在 `__init__` 中只安装一次文件 sink；单独 `using PiAI` 时 MUST 保留调用方现有 logger 行为。

`LOG_TAG` MUST 为 `<包短名>_<src 内相对路径>`（路径分隔符转 `_`）：`PiAI` → `ai_`、`PiAgentCore` → `agent_core_`、`PiCodingAgent` → `coding_`、`PiKit` → `pikit_`。一期已使用的 `ai_*`/`agent_core_*`/`coding_*` 值 MUST 保持不变。

#### Scenario: Standalone package leaves logger untouched

- **WHEN** 在未 `using PiKit` 的进程中 `using PiAI` 并触发一条 `@info`
- **THEN** 不创建 `~/.pikit/agent/logs/app.log`，且使用 Julia 当前全局 logger

#### Scenario: PiKit installs one file sink

- **WHEN** `using PiKit` 后触发子包日志
- **THEN** 只安装一个文件 sink，日志写入配置路径且不镜像 stderr（除非 `PIKIT_LOG_STDERR=1`）

#### Scenario: Tag names map to source paths

- **WHEN** 检查任一带日志的源文件
- **THEN** 其 `LOG_TAG` 等于包短名加该文件相对包 `src/` 的路径

### Requirement: Independent tests and behavioral snapshot

每个包 MUST 拥有可在自身项目环境运行的测试入口，且默认零网络。仓库 MUST 保存一期行为快照，覆盖 `print`、`json`、`rpc` 模式、会话文件、工具输出与日志过滤关键路径；拆包后的 `PiKit` MUST 产生相同快照。快照差异 MUST 阻止合并，更新基线 MUST 附带显式说明。

#### Scenario: Per-package test runs

- **WHEN** 分别执行三包的 `Pkg.test()`
- **THEN** 全部通过，且不读取仓库根 `Project.toml` 之外的路径

#### Scenario: Snapshot equality after split

- **WHEN** 运行 `scripts/snapshot-regression.jl --check`
- **THEN** JSON 事件、会话 JSONL 与 RPC 帧与 `test/fixtures/snapshots-v0.1/` 一致

### Requirement: Versioning and registration

三包 MUST 使用固定 UUID 与 `0.2.0` 版本，`PiKit` MUST 在 `[compat]` 中约束三者为 `0.2`。三包 MUST 先于 `PiKit 0.2.0` 提交 General 并按 `PiAI → PiAgentCore → PiCodingAgent` 顺序合并；包名与 UUID MUST 在注册前通过 General 可用性检查。

#### Scenario: Install order works from General

- **WHEN** 三包注册合并后在干净环境执行 `Pkg.add(["PiAI","PiAgentCore","PiCodingAgent","PiKit"])`
- **THEN** 解析到同一 `0.2` 系列且 `using PiKit` 成功

#### Scenario: Compat blocks mixed majors

- **WHEN** 环境中存在 `PiAI 0.3` 而 `PiKit` 兼容区间为 `0.2`
- **THEN** 解析失败而不是静默混用
