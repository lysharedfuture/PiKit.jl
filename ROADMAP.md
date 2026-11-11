# PiKit.jl 路线图 / Roadmap

> 起始上游基线：`earendil-works/pi` @ `06aa6563e4d51d6df5de6c9664c3a868f3f5bb2a`（2026-11-04），`pi-ai` / `pi-agent-core` / `pi-coding-agent` 当时报告 1.5.0；当前验证基线、能力矩阵与同步记录见 `docs/src/upstream-compat.md`。
> 项目级功能路线图。细粒度状态由 spec-superflow 的 `changes/<name>/` 维护；规范性需求在 `specs/<capability>/spec.md`，增量需求在 `changes/<name>/specs/`；日志纪律见 `.omp/RULES.md`；开发过程（含 Julia 改进记录）见 `specs/development-process/spec.md`。
> 本文件只维护功能级条目、change 关联、跨期契约、风险与决策；不复制 `tasks.md` 的子任务状态。

## 目标架构 / Target

目标：移植 `pi-agent-core`、`pi-coding-agent`、`pi-durable` 及其依赖/周边，保持事件协议、工具协议、会话格式、RPC 帧兼容。最终态是**与上游包边界一一对应的 Julia 包族**，不是一个巨型包。

| 上游包 | 作用 | Julia 目标 | 期次 |
|---|---|---|---|
| `pi-ai` | 统一 LLM API、模型发现、多 Provider | `PiAI.jl` | 一期子集；二期补齐 |
| `pi-agent-core` | agent 循环、状态、附件、传输抽象 | `PiAgentCore.jl` | 一期核心；二期补全 |
| `pi-coding-agent` | 编码 agent：工具、提示词、会话、四种模式 | `PiCodingAgent.jl` | 一期核心；二/三期补全 |
| `pi-durable` | 持久化会话/任务/文档运行时、可恢复执行 | `PiDurable.jl` | 二期 |
| `pi-schema` | JSON Schema 2020-12 / draft-7 校验 | `PiSchema.jl` | 一期内部子集；二期独立 |
| `pi-env` | 远程执行环境（SSH daemon + client） | `PiEnv.jl` | 二期随 durable |
| `pi-telemetry` | 厂商中立遥测契约 | `PiTelemetry.jl` | 二期 2D 核心包 + AI 接入；三期 exporter |
| `pi-mcp` | 独立 MCP 客户端 | `PiMCP.jl` | 二期 weakdep |
| `pi-tui` | 差分渲染 TUI 库 | `PiTUI.jl` | 三期（一期为行式 REPL） |
| `pi-codemode` | 沙箱 JS，唯一能力是调用注入工具 | 待评估（D1） | 三期 |
| `chord` / `evals` | 通用对象运行时 / 评测框架 | 默认不移植（D5） | 评估 |

## 已完成 / Delivered

- 一期 v0.1 代码、测试与文档已交付：`PiKit.AI` / `PiKit.AgentCore` / `PiKit.CodingAgent` 三模块、三个 Provider、AgentCore 循环、8 个编码工具、会话 v3 子集、压缩/溢出/重试、print/JSON/RPC/REPL、日志与 CLI。
- 零网络全量测试通过：`PIKIT_AGENT_DIR=$(mktemp -d) julia --project=. -e 'using Pkg; Pkg.test()'`。
- faux 端到端、JSON/RPC 冒烟通过；`grep` 使用 `ripgrep_jll`，`find` 在 `fd_jll` 注册前使用临时下载路径；`.gitignore` 集成冒烟通过。
- GitHub 仓库已创建：`https://github.com/lysharedfuture/PiKit.jl`；`v0.1.0` 已注册并由 TagBot 创建 tag；freeze commit 作为 `0.1.1` patch 注册中。
- 文档已交付：`docs/src/cli.md`、`docs/src/json.md`、`docs/src/sessions.md`、`docs/src/upstream-compat.md`、`docs/src/julia-improvements.md` 与改进记录检查器。

## 进行中 / In Progress

- **General 注册**：`v0.1.0` 已通过 PR #175351 合并且 TagBot 创建 tag；该版本树早于 freeze commit。freeze commit 以 `0.1.1` patch 重新提交注册，包含 `bin/pikit` 修复与文档更新；`find` 仍等待 `fd_jll`。0.1.1 合并后 2A 从该 tag 开始。

## 已完成变更 / Completed Changes

| 功能 | Change | 状态 |
|---|---|---|
| 一期 v0.1 核心闭环 | `pikit-julia-port` | 代码/测试/文档完成；`v0.1.0` 已注册并 tag；`0.1.1` freeze patch 注册中 |

## 待办 / Planned

### 一期（v0.1）：可交付闭环

一期范围：单包 `PiKit`（`PiKit.AI` / `PiKit.AgentCore` / `PiKit.CodingAgent` 三模块）、`openai-completions` / `anthropic-messages` / `faux` 三个 Provider、8 个工具（read/bash/powershell/edit/write/grep/find/ls）、会话 v3 子集、print/JSON/RPC/行式 REPL、压缩/溢出/重试、CLI 子集。

**状态：代码、测试、文档已完成；`v0.1.0` 已注册并 tag；freeze commit 以 `0.1.1` patch 注册中。**

| 功能 | 说明 | Change |
|---|---|---|
| AI 核心 | 消息/内容类型、显式 JSON codec、SSE、事件流、Schema 子集、模型目录、凭据、retry/overflow | `pikit-julia-port` |
| Provider | `openai-completions`、`anthropic-messages`、`faux`、注册表、缓存与工具规则 | `pikit-julia-port` |
| AgentCore 循环 | 事件序列、hooks、并行/顺序工具、steering/follow-up、中止、listener | `pikit-julia-port` |
| 编码工具 | truncate/path、read、bash、powershell、edit、write、rg/fd 管理、details/operations、grep/find/ls、写队列、工具注册表、system prompt | `pikit-julia-port` |
| 会话与压缩 | v3 读写、上下文重建、fork、token 估算、压缩、溢出恢复 | `pikit-julia-port` |
| CLI 四模式 | 配置、手写解析、runtime、print/JSON/RPC/REPL | `pikit-julia-port` |
| 日志 | 方案 C：默认只写文件，`PIKIT_LOG_STDERR=1` 才镜像 stderr；默认 `info`，`debug` 关闭 | `pikit-julia-port` |
| 开发过程 | 三期通用：每波记录、稳定 ID、检查器与每期发布门禁 | `pikit-julia-port` |
| 发布 | 文档、General 注册、TagBot `v0.1.0`/`v0.1.1` tag | `pikit-julia-port` |

**发布策略：一期即提交 General**（`PiKit` 名称已核对未被占用）。以 `0.x` 版本发布并明确 API 未冻结；注册合并后安装方式 `Pkg.add("PiKit")`，此前源码安装使用 `Pkg.develop(path=...)` 或 `Pkg.develop(url="https://github.com/lysharedfuture/PiKit.jl")`。注册 PR #175351 正在等待人工审核/合并。

一期必须留下的“二期钩子”：

- 模块边界 = 上游包边界（`src/ai` / `src/agent_core` / `src/coding`），拆包只移动目录 + 独立 `Project.toml`。
- `Provider` 注册表、`Tool.replay`/`output_schema` 字段位、`deferred` 透传、`context_edit` 只读——二期直接填充，不改协议。
- 会话 reader 容错：未知 entry 保留、未知字段进 `extra`；durable 新 entry 对一期 reader 只是 `UnknownEntry`。

### 二期（v0.2–v0.4）：可依赖、可恢复

| 子阶段 | 内容 | 退出标准 | Change |
|---|---|---|---|
| **2A 拆包** | `PiAI.jl` / `PiAgentCore.jl` / `PiCodingAgent.jl`；`PiKit.jl` 变为聚合与 CLI 层；模块间只用公开 API | 三包独立测试绿；PiKit 快照回归与 v0.1 一致；三个包提交 General | `changes/phase2a-package-split` |
| **2B durable** | `PiDurable.jl`：持久化运行、effect 记录与 `replay(:never\|:safe)`、`deferred` 轮询、崩溃后续跑、`context_edit` 全语义、compaction `details`/`fromHook` | `kill -9` 后可续跑；durable JSONL store 可被上游 `pi-durable` 打开；重放不重复副作用 | `changes/phase2b-durable-runtime` |
| **2C ai 广度** | `openai-responses`、`google-generative-ai`/vertex、bedrock、mistral、azure、images/classifiers、OAuth/login、long cache | 每 Provider 一套 mock 请求体快照 + 一次真实手工冒烟 | `changes/phase2c-ai-providers` |
| **2D schema/mcp/telemetry** | 完整 `PiSchema.jl`（draft-7/2020-12、`$ref`、strict tools、grammar）；`PiMCP.jl` weakdep；`PiTelemetry.jl` 核心包 + NOOP/内存/render + AI 请求 span | schema 通过上游 fixture；MCP 连本地 server；遥测包注册、默认关闭、AI span/event/metrics 可断言 | `changes/phase2d-schema-mcp-telemetry` |

依赖：2A 先行；2B/2C/2D 在拆包后并行；2D 的 schema 是 strict tools 的前置（两者都在 2D 收口）。

### 三期（v0.5–v1.0）：生态与交互对等

| 方向 | 内容 | 说明 | Change |
|---|---|---|---|
| **3A TUI** | `PiTUI.jl` 差分渲染、全屏交互、主题、快捷键 | 行式 REPL 保留为 `--no-tui` | 未建档 |
| **3B 扩展系统** | extensions/Pi packages、skills、prompt templates、themes、自定义工具与 provider | 对应上游 `register*` 与 packages | 未建档 |
| **3C 远程执行** | `PiEnv.jl`：SSH daemon + client，与 durable 组合 | 工具执行可路由到远端 | 未建档 |
| **3D codemode** | 沙箱执行 + 注入工具 | 见 D1；不承诺 1:1 | 未建档 |
| **3E 补齐** | 分支摘要、virtual models、HTML/share 导出、图片缩放 | 按需求拉动，不阻塞 v1.0 | 未建档 |

v1.0 判据：三个核心上游包（core/coding-agent/durable）的公开 API 与协议均有 Julia 对应物；跨版本会话可读；多包可从 General 安装。

## 未排期与条件项 / Unscheduled & Conditional（2026-11-11）

本表只记录**未进入任何已承诺阶段**的项。已交付项见“已完成变更”；已排到二/三期的内容见阶段表，不再在本表重复。`chord`/`evals` 属于非目标（D5），见文末。

| 项 | 性质 | 为什么未排期 | 触发条件 | 触发后 |
|---|---|---|---|---|
| HTML/share 导出 | 3E 候选 | 不承诺交付 | 有分享/导出需求 | 3E |
| 图片缩放 | 3E 候选 | 不承诺交付 | 有图片交互需求 | 3E |
| branch summarization | 3E 候选 | 不承诺交付 | 有长分支会话需求 | 3E |
| virtual models | 3E 候选 | 不承诺交付 | 有多模型聚合需求 | 3E |
| `agent/src/proxy.ts` | 条件项 | 一期不移植；二期未排期 | 有服务器代理入口需求 | 待定 |
| `fetch` / `transport` / websocket | 条件项 | 一期不建模；`onProviderStreamEvent` 已在 2C | 有客户端注入/原始事件/WebSocket 需求 | 待定 |

## 设计参考 / Design References

- `worker_tools.jl`（LLMTools/Agentif）：Julia worker 池、`remote_eval`、输出投影、worker 生命周期。仅作 2B/3C/3D 评估参考，不承诺交付；触发条件：需要 Julia worker 执行模型。

## 已知缺陷 / Known Issues

- **0.1.1 尚未注册**：`v0.1.0` 已注册并 tag，但其树早于 freeze commit（`bin/pikit` 旧调用）；freeze commit 以 `0.1.1` patch 重新注册，合并前 `Pkg.add("PiKit")` 只到 0.1.0。
- **Windows PowerShell 实机未验证**：当前环境为 Linux；非 Windows 返回错误路径已有测试，`powershell` 的实际 Windows 冒烟待补。
- **REPL TTY 手工验证未执行**：自动测试覆盖 stdin/print 路径；真实 TTY 下的斜杠命令、流式渲染与 Ctrl+C 中止需手工冒烟。
- 旧 General PR #175350 仍处于 open 状态，等待维护者关闭；新 PR #175351 为有效注册单。

## 里程碑 / Milestones

- **一期 v0.1**：**已完成 M0–M7 与 M8 的代码/测试/文档；`v0.1.0` 已注册并 tag；freeze commit 以 `0.1.1` patch 注册中**（`change: pikit-julia-port`）。
- **二期 v0.2–v0.4**：2A 拆包已实现（四包 + 边界检查 + 行为快照，`change: phase2a-package-split`；注册待提交）；2B `phase2b-durable-runtime`、2C `phase2c-ai-providers`、2D `phase2d-schema-mcp-telemetry` 规划已建档。
- **三期 v0.5–v1.0**：未开始（3A–3E）。
- **改进记录门禁**：一期 M8 `--phase 1 --strict`；二期各子阶段收口 `--phase 2 --strict`；三期 v1.0 `--all --strict`。

### 一期里程碑 M0–M8

**M0–M7 已完成；M8 的文档、GitHub 仓库与 `v0.1.0` 注册/tag 已完成；freeze commit 的 `0.1.1` patch 注册中。**

| 里程碑 | 范围 | 退出标准（可执行） | 依赖 |
|---|---|---|---|
| **M0 骨架** | git init、`Project.toml`、三模块空壳、`bin/pikit`、CI、LICENSE/NOTICE、`scripts/fetch-upstream.sh` | `using PiKit` 输出 `ok`；CI 绿；`.upstream/` 按 `UPSTREAM_REF` 落地 | — |
| **M1 AI 基础** | types、json、sse、event_stream、schema 子集、models、credentials、retry/overflow 纯函数 | codec roundtrip、SSE 边界、schema 错误路径、retry 分类、overflow 三类检测 | M0 |
| **M2 Provider** | openai-completions、anthropic-messages、faux、registry；缓存与工具规则、流映射、错误编码 | mock 请求体快照；faux 事件序列；非 2xx/中止生成 `ErrorEvent` | M1 |
| **M3 循环** | agent_core/types、loop、agent：hook、并行工具、队列、listener、失败兜底 | faux 序列/并行顺序/steering/finish_turn；`abort!` 200ms 内 `agent_end` | M1、M2(faux) |
| **M4 工具** | truncate、path_utils、shell_env、tools_manager（rg/fd）、read、bash、powershell、edit、write、mutation queue、grep/find/ls、details/operations、registry | W3 工具验收全过（截断文案、timeout、BOM/CRLF、rg/fd 解析与离线、shell/PowerShell 解析、details/operations、同文件串行） | M1 |
| **M5 会话+E2E** | session（header 校验/尾部修复/`context_edit`/build_context）、system_prompt、runtime、config、print | v3 fixture 往返；compaction+`context_edit` 重建；`-p` faux 端到端 | M3、M4 |
| **M6 协议模式** | JSON 事件全集、RPC 命令与 `disposition`、REPL、CLI 全量 flag | JSON 快照匹配 `docs/src/json.md`；RPC 冒烟；REPL 手工 | M5 |
| **M7 压缩与恢复** | compaction（usage 锚点/切点/entry 字段）、溢出恢复、retry 集成 | 阈值压缩、413 溢出重试、配额 429 不重试三条端到端 | M6 |
| **M8 发布** | docs、README、julia-improvements 检查器、**General 注册**、TagBot tag | `julia scripts/check-julia-improvements.jl --phase 1 --strict --upstream .upstream` 通过（已完成）；GitHub 仓库 `lysharedfuture/PiKit.jl` 已创建；`v0.1.0` 已注册并 tag；`0.1.1` freeze patch 注册中；真实 Provider 手工冒烟 | M7 |

## 依赖关系 / Dependencies

```text
HTTP 1.10 + JSON 1.13 + ripgrep_jll 15.2
ripgrep_jll（grep）；fd_jll（find；待 Yggdrasil）
  └── 一期 PiKit（AI/AgentCore/CodingAgent 三模块）
        └── 2A 拆包 ──> PiAI / PiAgentCore / PiCodingAgent
                          ├── 2B PiDurable
                          ├── 2C ai 广度 ──> 2D PiSchema（strict tools 前置）
                          └── 2D PiMCP（weakdep）/ PiTelemetry
三期：3A PiTUI / 3B 扩展 / 3C PiEnv / 3D codemode / 3E 补齐
```

## 跨期契约 / Compatibility Contract

- 事件/消息 wire 形状、会话 v3 基线字段、RPC 帧、工具结果结构稳定；新增能力只加字段/加事件，不改既有含义。
- 会话读取永远向后兼容：未知 entry 保留、未知字段进 `extra`。
- Provider 通过注册表扩展，核心不新增 switch 分支。
- 每次同步上游后更新 `docs/src/upstream-compat.md`（当前验证基线与差异表）；README/NOTICE/脚本不承担永久 pin 语义；偏差只减不增。
- 0.x 期间允许破坏性变更，但必须附迁移说明；v1.0 起冻结。

## 待决决策 / Decisions Pending

| 编号 | 问题 | 影响期 | 记录时的倾向（非决定） | 重新评估的触发条件 |
|---|---|---|---|---|
| D1 | `codemode` 依赖 JS 沙箱：嵌入 node/deno 子进程，还是只提供 Julia 子集/子进程工具？ | 三期 | 先不承诺 1:1；若必须兼容 pi 脚本，走外部 JS 运行时 | 有真实 codemode 工作流需求 |
| D2 | TUI 自研差分渲染，还是包 `TerminalMenus`/`TextUserInterfaces`？ | 三期 | 自研渲染层、复用已有终端后端 | 3A 启动时按维护成本再定 |
| D3 | durable 的 effect 持久化粒度与 fsync 策略（每次工具调用 vs 每 turn） | 二期 2B | 每次工具调用记 effect，崩溃恢复以 turn 为边界 | 2B 故障注入测试结果 |
| D5 | `chord`/`evals` 是否移植 | 三期后 | 默认不移植；evals 用 Julia 测试框架替代 | 有跨进程对象运行时或评测框架需求 |

已定：**一期提交 General**；二期 2A 完成后再注册三个子包；v1.0 前冻结 API。

- **D4 已定（2D）**：`PiSchema` 独立成包，与上游 `pi-schema` 包边界一致；`PiAI` 直接依赖它，`PiAgentCore`/`PiDurable` 通过 `PiAI` 或显式依赖使用。并入 `PiAI` 的方案否决：会让只依赖 schema 的外部项目被迫拉入 HTTP/JSON/AI 依赖，并破坏上游包边界。
- **D6 已定（2A）**：保留 `PiKit` 为 CLI/聚合层。它只承载 `(@main)(args)`/`main()`、CLI 解析与 print/JSON/RPC/REPL 模式、配置与信任、日志 sink、应用装配（auth/durable/MCP/TUI 等）、发布元数据与兼容别名；不新增核心 AI/agent/工具/会话 API。`PiCodingAgent` 保持纯库，不导出 `main`、不依赖 `PiKit`。`PiKit` 不是第四个核心包；v1.0 API 对等以 `PiAI`/`PiAgentCore`/`PiCodingAgent`/`PiDurable` 为准。

## 风险 / Risks

1. **durable 恢复语义**（最高）：effect 重放、幂等边界、崩溃点一致性；需故障注入测试。
2. **多 Provider 方言**：靠 `compat` + 请求体快照治理，避免静默降级。
3. **TUI 交互**：差分渲染与中止/队列/压缩状态耦合；先做事件回放驱动。
4. **codemode 运行时**：非 Julia 沙箱的许可、性能、工具注入契约。
5. **拆包 API 漂移**：2A 前冻结核心类型，拆包后禁止跨包内部依赖。

## 非目标 / Non-Goals

- `chord`、`evals`（D5）。
- 全屏 TUI 在 v0.1–v0.4 不做（三期 3A）。
- 以下为 3E 候选、不承诺交付：HTML/share 导出、图片缩放。
- `pi-codemode` 的 1:1 JS 兼容不承诺（D1）。
