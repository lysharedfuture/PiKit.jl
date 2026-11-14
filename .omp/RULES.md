# RULES — PiKit 开发纪律

> 本文件约束 PiKit 的开发纪律。各一级章节相互独立；目前包括 GitHub 提交与发布、发布 tag（根包与子包）、注册前置检查、本地注册表、文档、日志，后续新增纪律追加同级章节。

## GitHub 提交与发布

- 向 GitHub 推送代码、创建/更新 PR、创建 tag、创建 Release、触发 General 注册或文档部署前，MUST 先获得用户明确确认。
- 本地 `git commit`、构建、测试和文档本地构建不需要确认。
- 确认必须明确目标：仓库、分支、commit、版本号；不得以历史对话中的“继续”视为永久授权。
- 未经确认，禁止执行 `git push`、`gh pr create`、`gh pr edit`、`gh release create`、`gh release edit`、tag 推送或 Registrator 触发评论。
- 推送失败或部分成功时，MUST 报告实际远端状态，不得静默重试或改变目标。
- tag 与 Release 仍须遵守下一节的 TagBot 规则。

## 发布 tag（根包与子包）

### 通用

- 所有发布 tag（根包 `vX.Y.Z` 与子包 `<Package>-vX.Y.Z`）MUST 由 TagBot 创建。
- 禁止手工 `git tag`、`gh release create` 或推送 release tag。
- 注册合并后等待 `JuliaTagBot` 创建 tag 与 Release；TagBot workflow 见 `.github/workflows/TagBot.yml`。
- 重新发布已注册版本前，先删除旧 tag/Release，再在最终 commit 上重新触发 `@JuliaRegistrator register`，让 TagBot 按 registry tree 重建 tag。
- TagBot workflow MUST 为每个包提供一个独立 step；缺少 step 视为发布配置未完成。

### 根包

- 根包 `PiKit` 的 tag 形如 `vX.Y.Z`，由不带 `subdir` 的 TagBot step 创建。

### 子包

- 每个子包 MUST 有独立的 TagBot step 并设置 `subdir`（`PiAISDK`、`PiAgentCore`、`PiCodingAgent`）。
- 子包 tag 形如 `<Package>-vX.Y.Z`；根包 tag 与子包 tag 互不替代。
- 新增子包时 MUST 同时新增其 TagBot step 与 `docs/make.jl` 条目。

### Release notes

- 每次调用 Registrator 时，`@JuliaRegistrator register` 评论 MUST 在同一评论内包含 `Release notes:` 段落。
- 格式：

  ```text
  @JuliaRegistrator register

  Release notes:

  ## Changes
  - ...
  ```

- 新版本 MUST 写用户可见变化；破坏性变更 MUST 单独列出并说明影响。
- 首次发布写 `Initial release ...`；后续版本按 `Added / Changed / Fixed / Breaking` 组织。
- Release notes MUST 与触发评论在同一条消息内，不得另发评论后补；否则 Registrator 不会关联。
- 子包触发行 MUST 带 `subdir=<dir>`，notes 格式与根包一致。
- 修改 notes 后重新触发同一版本，注册 PR 会更新。
- TagBot 会把同一段 notes 写入 GitHub Release。

## 注册前置检查

- 包名 MUST 至少 5 个 ASCII 字符，MUST NOT 以 `jl` 结尾、以 `Ju` 开头或包含 `julia`。
- 包代码顶层目录（子包即子包目录）MUST 有 OSI 认可的 `LICENSE`。
- `Project.toml` MUST 包含 `name`/`uuid`/`version`；`[compat]` MUST 为所有依赖与 `julia` 提供上界，且 `julia` 上界只覆盖有限个 breaking release。
- 名称相似度 MUST 在提交注册前用 AutoMerge 官方 `meets_distance_check` 对当时 General 全量包名验证通过；判定相似时 MUST 改名，不得依赖 `Override AutoMerge: name similarity is okay` 掩盖长度或许可问题。
- 注册顺序 MUST 为 `PiAISDK → PiAgentCore → PiCodingAgent → PiKit`；每条 Registrator 评论 MUST 内嵌 release notes（见“发布 tag / Release notes”）。
- 版本策略：破坏性变更升 minor（`0.x` 内即为 minor），否则 patch；`PiKit` 的 `[compat]` 与三个子包版本 MUST 同步。已注册版本 MUST NOT 重复使用。
- 提交注册前 MUST 运行 `scripts/check-project-rules.jl`，失败不得触发 Registrator。

## 本地注册表（LocalRegistry）

术语区分：`LocalRegistry.jl` 是生成/维护 registry 的**工具**；`PiKitRegistry` 是它生成的 **registry 仓库**。二者都不是包依赖——下游“使用”指 Pkg 通过 registry 解析包，而不是在代码里依赖某个包。

- `LocalRegistry.jl` MUST 只安装在全局或共享开发环境，MUST NOT 出现在任何 `Project.toml` 的 `[deps]`/`[extras]`/`[targets]` 中。
- `PiKitRegistry` MUST 由 Pkg 的 registry 机制发现（`Pkg.Registry.add`），MUST NOT 写入任何 `Project.toml`；包间版本约束写在 `[compat]`，`[sources]` 只是本地开发覆盖，二者都不构成对 registry 的依赖。
- General 合并前，MAY 用 `PiKitRegistry` 让下游以 `Pkg.add("PiAISDK")` 等方式解析未注册子包；消费者不需要安装 `LocalRegistry.jl`。
- 登记前包必须是干净的 git 工作区，登记版本 MUST 与将提交 General 的版本一致。
- 本地 registry 的 `repo`/`subdir`/`git-tree-sha1` MUST 与仓库 commit 一致；registry 建立后，提交 General 前 MUST 运行 `scripts/check-registry-parity.jl`。
- 同一包版本 MUST NOT 在多个 registry 中以不同 tree 出现；General 合并后 SHOULD 删除本地对应条目。
- `LocalRegistry.jl` 的 `register` 默认 `push=false`；推送 registry 仓库前 MUST 按“GitHub 提交与发布”取得确认。
- 使用本地 registry MUST NOT 放宽 General 的任何门禁（名称、许可、文档、compat）。

## 文档（README 与导出 API）

- 每个包目录（含 monorepo 子包）MUST 有 `README.md`，至少包含：包定位、在 `PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit` 中的位置、上游映射、安装、一个可离线执行的最小示例、文档站链接。
- 每个导出符号 MUST 有 docstring；判定标准为 `Base.Docs.undocumented_names(mod)` 为空。
- `docs/make.jl` MUST 设 `checkdocs = :exports`；每个包 MUST 在 `pages` 中有使用 `@autodocs Modules = [<包>]` 的页面。
- 文档示例 MUST 进入测试（`test/docs_examples.jl` 或等价），使用 `faux` provider 或其它离线路径，MUST NOT 依赖网络。
- 根 `README.md` MUST 顶部有 docs badge 与文档站链接；未发布版本指向 `/dev/`，发布后改为 `/stable/`。
- 修改导出面、示例或文档页时 MUST 同步更新 docstring、`@autodocs` 页面与示例测试；`docs` job 或 `test/docs_audit.jl` 失败即阻断合并。
- 新增包 MUST 同时新增 README、`@autodocs` 页面、`docs/make.jl` 的 `modules`/`pages` 条目与 TagBot step。

## 日志硬纪律

### 文件标识（TAG）

- 每个含日志的 Julia 源文件顶部（模块与 `using` 之后）声明：
  `const LOG_TAG = "<文件名去扩展名>"`。
- 小写 + 下划线；嵌套目录用 `<目录>_<文件>`，例如 `src/coding/tools/read.jl → coding_tools_read`。
- 禁止中文 tag、无 tag、用模块名/函数名/类名代替。
- tag 必须与文件路径唯一对应；重命名文件时同步修改。

### 同步维护

- 代码修改后 MUST 同步修改日志：新增/删除关键路径、状态切换、重试、错误分支时，同步增加、修改或删除对应日志。
- 调整行为、参数、返回语义时，必须同步更新日志级别、消息与结构化字段，不能保留过时日志。
- 重命名/移动源文件时同步更新 `LOG_TAG`。
- 日志变更与代码变更放在同一提交，不得留到后续补写。

### 调用形式

- 统一使用 stdlib `Logging`：
  - `@info "message" _group=LOG_TAG key=value`
  - `@warn "message" _group=LOG_TAG key=value`
  - `@error "message" _group=LOG_TAG exception=(e, catch_backtrace())`
  - `@debug "message" _group=LOG_TAG key=value`
- 必须用 `_group=LOG_TAG`，不要只写普通 `tag=` 键：Julia 的 `shouldlog` 只能看到 `group`，按文件过滤依赖 `_group`。
- 日志文本用英文；结构化信息优先放键值，不拼字符串。
- 禁止用 `println` / `@printf` 当日志；JSON/RPC 的 stdout 只属于协议。

### 级别

- `info`：状态切换与关键动作（启动、模型选择、会话创建/恢复、压缩开始/结束、工具注册、模式切换）。
- `warn`：可恢复异常（Provider 回退、重试、权限异常、截断）。
- `error`：失败（Provider 错误、工具失败、会话写失败、未捕获异常）。
- `debug`：高频/调试路径（逐 delta、SSE 行、参数归一细节）。
- 默认 `info`；`debug` 默认关闭。

### 输出与过滤

- 默认只写文件：`~/.pikit/agent/logs/app.log`。
- 路径优先级：`PIKIT_LOG_FILE` > `PIKIT_AGENT_DIR` > `~/.pikit/agent`。
- 默认级别 `info`；`PIKIT_LOG=debug` 全局；`PIKIT_LOG=ai_json=debug,coding_tools_bash=debug` 按 tag。
- stderr 默认关闭；`PIKIT_LOG_STDERR=1` 才镜像到 stderr。
- 文件 sink 打开或写入失败：向 stderr 警告一次，后续降级为 stderr-only，不得中断请求。
- JSON/RPC 的 stdout 只写协议；日志不得进入 stdout。
- 文件 sink 追加写，进程内加锁；不重复打开文件。

### 错误不静默

- 禁止裸 `catch`、`catch; nothing`、`try ... catch; end`。
- 预期缺失用显式分支（`ispath`、`=== nothing`）并 `@debug`。
- 重试前 `@warn`；最终失败 `@error`。

### 脱敏

- `info/warn/error` 禁止记录 `Authorization`、`x-api-key`、API key、完整请求体。
- `debug` 记录 payload 前必须脱敏。
- 错误消息保留状态码与端点，不保留凭据。

### 测试

- 测试用 `mktempdir()` / `PIKIT_AGENT_DIR`，不得写真实 `~/.pikit`。
- 用 `Logging.with_logger` 或临时文件捕获；断言 tag、级别与文件内容。
- 断言 JSON/RPC 模式 stdout 无日志。
