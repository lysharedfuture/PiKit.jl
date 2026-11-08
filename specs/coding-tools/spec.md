# coding-tools

## Purpose

定义 PiKit 编码工具的输入 schema、边界行为与提示词。工具必须在截断、路径归一、进程组、编码、`.gitignore` 与并发写等边界上与上游一致，并向模型返回可解析的文本结果；工具描述与提示词模板属于协议的一部分。

## Requirements

### Requirement: Truncation and UTF-8 safety

`truncate_head`、`truncate_tail` 与 `truncate_line` SHALL 使用默认 2000 行、50KB 与 500 字符上限，返回包含原始行数/字节数的截断结果；截断 MUST 在 UTF-8 字符边界发生，不得切坏多字节字符。

#### Scenario: Head truncation by lines

- **WHEN** 输入 2500 行文本
- **THEN** 结果保留前 2000 行并标记行数截断

#### Scenario: Tail truncation keeps valid UTF-8

- **WHEN** 单行超过上限且包含多字节字符
- **THEN** 截取末尾时字符完整，无非法 UTF-8 序列

### Requirement: Path resolution

`resolve_to_cwd` SHALL 展开 `~`、去掉前导 `@`、归一 Unicode 空格并返回绝对路径；`resolve_read_path` MUST 在原名不存在时依次尝试 macOS 窄空格、NFD、弯引号与组合变体，且只在候选文件存在时采用。

#### Scenario: Home and @ prefixes expand

- **WHEN** 路径为 `@~/notes.txt`
- **THEN** 返回基于用户主目录的绝对路径

#### Scenario: Variant fallback only when present

- **WHEN** 原名不存在但 NFD 变体存在
- **THEN** 读取使用 NFD 变体；若两者都不存在则返回原名路径

### Requirement: read tool

`read` SHALL 支持 1 起始的 `offset` 与 `limit`，按行返回文本并保留上游的首行超限、行数截断、字节截断与 offset 越界文案；图片 MUST 返回文本说明加 base64 `ImageContent`，模型不支持图片时 MUST 只返回省略提示；不得缩放图片。

#### Scenario: Offset beyond end of file

- **WHEN** 文件 2500 行且 `offset=2501`
- **THEN** 返回 `Offset 2501 is beyond end of file (2500 lines total)`

#### Scenario: Model without image input

- **WHEN** 读取图片但模型的 `input` 不含 `image`
- **THEN** 只返回 `Current model does not support images. The image will be omitted from this request.`

### Requirement: bash tool process and environment

`bash` SHALL 要求 `command`，可接受有限且大于零的 `timeout`；shell 解析 MUST 按上游 `getShellConfig`：自定义 `shellPath` → Windows Git Bash 已知路径（`ProgramFiles` / `ProgramFiles(x86)`）→ PATH `bash.exe`；Unix `/bin/bash` → PATH `bash` → `sh`；legacy WSL bash MUST 使用 `bash -s` 并通过 stdin 传命令，其他情况使用 `bash -c`；以独立进程组启动（POSIX，等价上游 `detached: true`；Windows `taskkill`）；合并 stdout/stderr，并每 200ms 推送截断到 50KB/2000 行的输出快照；环境 MUST 复制父进程并覆盖 `PI_SESSION_ID`、`PI_SESSION_FILE`、`PI_PROVIDER`、`PI_MODEL`、`PI_REASONING_LEVEL`，`PATH` MUST 前置 `PIKIT_AGENT_DIR/bin`；默认非 login shell。

#### Scenario: Unix shell resolution

- **WHEN** `/bin/bash` 不存在但 PATH 中有 `bash`
- **THEN** 使用 PATH 中的 `bash`；两者都没有时回退 `sh`

#### Scenario: Windows Git Bash resolution

- **WHEN** 在 Windows 且 `ProgramFiles\Git\bin\bash.exe` 存在
- **THEN** 使用该 Git Bash，而不是 PATH 中的其他 shell

#### Scenario: Legacy WSL uses stdin

- **WHEN** bash 路径是 legacy WSL `System32\bash.exe` 或 `Sysnative\bash.exe`
- **THEN** 使用 `bash -s` 并通过 stdin 传命令

#### Scenario: Shell path is configurable

- **WHEN** 设置 `shellPath` 且文件存在
- **THEN** 使用该路径；不存在时报 `Custom shell path not found`

#### Scenario: Timeout kills the process tree

- **WHEN** 命令超时
- **THEN** 进程树收到 `SIGKILL`（macOS 先 `SIGSTOP`；Windows 用 `taskkill /F /T`），错误文本为 `Command timed out after N seconds`

#### Scenario: Abort kills the process tree

- **WHEN** 运行中止
- **THEN** 进程树被终止，子进程不会在工具返回后继续运行

#### Scenario: Environment inheritance and PI override

- **WHEN** 父进程设置 `ANTHROPIC_API_KEY` 与错误的 `PI_MODEL`
- **THEN** 子进程能看到该密钥，且 `PI_MODEL` 为当前实际模型；`PATH` 含 `PIKIT_AGENT_DIR/bin`

#### Scenario: No output marker

- **WHEN** 命令成功且无输出
- **THEN** 结果文本为 `(no output)`

### Requirement: edit tool

`edit` SHALL 接受 `path` 与 `edits` 数组，`prepare_arguments` MUST 归一 JSON 字符串、单个 edit 对象与旧式顶层 `oldText`/`newText`；每条 `oldText` MUST 在原始内容中恰好出现一次且互不重叠；写回 MUST 保留 BOM 与原行尾；结果 MUST 为 `Successfully replaced N block(s) in <path>.` 并携带 diff/patch 详情。

#### Scenario: CRLF and BOM preserved

- **WHEN** 编辑含 BOM 与 CRLF 的文件
- **THEN** 写回内容仍以相同 BOM 与 CRLF 开头/分行

#### Scenario: Duplicate old text is rejected

- **WHEN** 某条 `oldText` 出现两次
- **THEN** 工具返回错误且文件不变

#### Scenario: Legacy arguments normalized

- **WHEN** 参数是旧式 `oldText`/`newText`
- **THEN** 被转换为单条 `edits` 后正常执行

### Requirement: write tool

`write` SHALL 创建缺失的父目录并以 UTF-8 写入完整内容，结果文本 MUST 为 `Successfully wrote to <path>`。

#### Scenario: Parent directories are created

- **WHEN** 写入 `a/b/c.txt` 且目录不存在
- **THEN** 目录被创建且文件内容与请求一致

### Requirement: grep, find and ls behavior

`grep` SHALL 调用 `rg --no-config --json --line-number --color=never --hidden`，按 JSON 事件输出相对搜索根的 `path:line: text`，支持 `glob`/`ignoreCase`/`literal`/`context`，默认 limit 100，并按上游规则保留 trailing context、500 字符截断与 limit/字节通知；`find` SHALL 调用 `fd --glob --color=never --hidden`，默认 limit 1000，搜索根在 git 仓库外时 MUST 传 `--no-require-git`，pattern 含 `/` 时 MUST 使用 `--full-path` 并补 `**/` 前缀；`ls` SHALL 保持纯 Julia 实现，按大小写不敏感排序、目录加 `/`、默认 limit 500。

#### Scenario: Ignored files are excluded

- **WHEN** 目标目录含被 `.gitignore` 忽略的文件
- **THEN** `grep` 与 `find` 都不返回该文件，因为 rg/fd 尊重 `.gitignore`

#### Scenario: Ambient rg config is ignored

- **WHEN** 用户设置 `RIPGREP_CONFIG_PATH`
- **THEN** 工具仍传 `--no-config`，行为不受环境配置影响

#### Scenario: fd handles git and non-git roots

- **WHEN** 搜索根在 git 仓库内
- **THEN** 不传 `--no-require-git`，使用 fd 的 git-aware 规则
- **WHEN** 搜索根不在 git 仓库内
- **THEN** 传 `--no-require-git`，仍应用 `.gitignore`

#### Scenario: Grep literal and regex modes

- **WHEN** `literal=true` 或提供非法正则
- **THEN** 前者传 `--fixed-strings`；后者返回 rg 的明确正则错误

#### Scenario: Grep limit keeps trailing context

- **WHEN** 匹配数达到 limit 且存在后续匹配
- **THEN** 保留最后一条匹配的 trailing context，并追加 limit 通知

#### Scenario: ls sorts and marks directories

- **WHEN** 目录同时含文件与子目录
- **THEN** 条目大小写不敏感排序，子目录名以 `/` 结尾

### Requirement: Same-path file mutation serialization

`edit` 与 `write` SHALL 以绝对路径为键共享互斥队列，使并行批次中对同一文件的读-改-写按顺序完成；同一调用中的多个 edit MUST 在单次读写中完成。

#### Scenario: Concurrent edits do not lose updates

- **WHEN** 并行批次中的两个工具修改同一文件
- **THEN** 文件内容包含两次修改，且不存在半写结果

### Requirement: Tool registry and prompt text

工具注册表 SHALL 支持 `read`、`bash`、`powershell`、`edit`、`write`、`grep`、`find`、`ls`；默认启用 `read`、`bash`、`edit`、`write`；`grep`、`find`、`ls` 与 `powershell` 需显式选择（`powershell` 仅 Windows 可用）；工具描述、`promptSnippet` 与 `promptGuidelines` MUST 逐字复制上游对应文件；system prompt MUST 按 `preamble → tools → rules → docs → addendum → project_context → cwd` 顺序生成 section，除 `preamble` 外每个值使用同名 XML 包装。

#### Scenario: Default tool set

- **WHEN** 未指定工具选择
- **THEN** 只有 `read`、`bash`、`edit`、`write` 被注册

#### Scenario: PowerShell is opt-in and Windows-only

- **WHEN** 显式选择 `powershell` 且在非 Windows 执行
- **THEN** 工具存在但执行返回仅 Windows 可用的错误

#### Scenario: Prompt section ordering

- **WHEN** 构造 system prompt
- **THEN** section 顺序固定且 `<tools>`/`</tools>` 包装存在

#### Scenario: Context files are discovered

- **WHEN** cwd 向上存在 AGENTS/CLAUDE 文件
- **THEN** 全局候选与祖先候选按根→近的顺序进入 `project_context`

### Requirement: Managed external tools

`grep` 与 `find` SHALL 通过 tools manager 解析 `rg`/`fd`：先查 `PIKIT_AGENT_DIR/bin`（默认 `~/.pikit/agent/bin`），再查 PATH（`rg`、`fd`/`fdfind`）；未找到且未设置 `PIKIT_OFFLINE=1`（对应上游 `PI_OFFLINE`）时 MUST 从 `BurntSushi/ripgrep` / `sharkdp/fd` 的 GitHub Release 下载当前平台架构的归档并解压；Android/Termux MUST 只提示 `pkg install`；不支持的平台架构 MUST 返回可操作错误，不得下载错误架构的二进制。`.tar.gz` MUST 用 `tar xzf` 解压；`.zip` 在 Windows MUST 优先 `System32\tar.exe`，失败后 PowerShell `Expand-Archive`；Unix MUST 优先 `unzip`，失败后 `tar`；`fd` 在 darwin/x64 MUST 固定 10.3.0，其他平台取 latest release。

#### Scenario: Local or PATH tool is preferred

- **WHEN** `PIKIT_AGENT_DIR/bin/rg` 或 PATH 中的 `rg` 存在
- **THEN** 直接使用该路径，不访问网络

#### Scenario: Missing tool downloads when online

- **WHEN** 本地与 PATH 都没有 `fd` 且未设置 `PIKIT_OFFLINE`
- **THEN** 下载并安装 `fd` 到 `PIKIT_AGENT_DIR/bin`，再执行 find

#### Scenario: Offline mode refuses download

- **WHEN** 设置 `PIKIT_OFFLINE=1` 且工具缺失
- **THEN** grep/find 返回明确错误，说明未找到工具且离线模式禁止下载

#### Scenario: Unsupported platform

- **WHEN** 当前平台架构没有预编译 release
- **THEN** 返回手动安装指引，不尝试错误架构的二进制

#### Scenario: Archive extraction follows upstream

- **WHEN** 下载的是 `.zip` 且在 Windows
- **THEN** 优先使用 `System32\tar.exe`，失败后才用 PowerShell `Expand-Archive`

### Requirement: Tool result details

工具结果 `details` SHALL 与上游一致：`read` 使用 `truncation`；`grep` 使用 `truncation`、`matchLimitReached`、`linesTruncated`；`find` 使用 `truncation`、`resultLimitReached`；`ls` 使用 `truncation`、`entryLimitReached`；`edit` 使用 `diff`、`patch`；`bash` 使用 `truncation`、`fullOutputPath`（存在时）；`powershell` 与 `bash` 相同。

#### Scenario: Truncation details are present

- **WHEN** `read`、`grep`、`find` 或 `ls` 触发截断或 limit
- **THEN** 结果 details 包含对应的 `truncation` 或 limit 字段

#### Scenario: Edit keeps diff and patch

- **WHEN** `edit` 成功
- **THEN** details 同时包含 `diff` 与 `patch`

#### Scenario: Bash keeps truncation and full output path

- **WHEN** `bash` 触发截断或产生完整输出临时文件
- **THEN** details 包含 `truncation` 和/或 `fullOutputPath`

#### Scenario: PowerShell details match bash

- **WHEN** `powershell` 执行完成
- **THEN** details 结构与 `BashToolDetails` 相同

### Requirement: Tool operations interfaces

`grep`、`find`、`ls` 与 `read` SHALL 暴露与上游同形的 operations seam：`GrepOperations.is_directory`；`FindOperations.exists`/`glob`；`LsOperations.exists`/`stat`/`readdir`；`ReadOperations.read_file`/`access`/`detect_image_mime_type`/`create_read_stream`。`bash` SHALL 暴露 `BashOperations.exec(command, cwd; on_data, signal, timeout, env) -> (exit_code::Union{Nothing,Int},)`（对应上游 `{exitCode}`）；`powershell` SHALL 使用 `PowerShellOperations = BashOperations`，由本地实现前置 UTF-8 前缀。默认实现 MUST 使用本地 rg/fd/文件系统与子进程；自定义 operations MUST NOT 改变工具 schema 或默认输出格式。

#### Scenario: Custom find glob bypasses fd

- **WHEN** `FindOperations.glob` 提供自定义实现
- **THEN** `find` 使用该实现而不是 fd，输出契约保持不变

#### Scenario: Custom read stream is used

- **WHEN** `ReadOperations.create_read_stream` 存在
- **THEN** 文本读取通过该流进行，而不是一次性读完整文件

#### Scenario: Default operations are local

- **WHEN** 未提供自定义 operations
- **THEN** `grep`/`find` 使用 rg/fd，`ls`/`read` 使用本地文件系统，`bash`/`powershell` 使用本地子进程

#### Scenario: Custom bash exec is used

- **WHEN** `BashOperations.exec` 提供自定义实现
- **THEN** `bash` 通过该实现执行，输出/截断契约保持不变

#### Scenario: PowerShell operations alias bash

- **WHEN** 执行 `powershell`
- **THEN** 使用 `PowerShellOperations`（即 `BashOperations`）并由本地实现前置 UTF-8 前缀

### Requirement: PowerShell tool

`powershell` SHALL 仅在 Windows 可用，要求 `command` 与可选 `timeout`；解析顺序 MUST 为 PATH `pwsh.exe` → `ProgramFiles\PowerShell\7\pwsh.exe` → PATH `powershell.exe` → `System32\WindowsPowerShell\v1.0\powershell.exe`；参数 MUST 为 `-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command`，并在命令前加 UTF-8 输出编码前缀；输出/截断/临时文件/错误文案 MUST 与 `bash` 一致；非 Windows 执行 MUST 返回明确错误；details 与 `BashToolDetails` 一致，operations 为 `PowerShellOperations = BashOperations`。

#### Scenario: PowerShell resolution order

- **WHEN** PATH 中存在 `pwsh.exe`
- **THEN** 优先使用该路径，而不是 `powershell.exe`

#### Scenario: UTF-8 output prefix

- **WHEN** 执行 PowerShell 命令
- **THEN** 命令前附加 `try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}`

#### Scenario: Non-Windows is rejected

- **WHEN** 在非 Windows 平台执行 `powershell`
- **THEN** 返回 “The powershell tool is only available on Windows.” 并标记为工具错误

#### Scenario: Timeout kills the process tree

- **WHEN** PowerShell 命令超时
- **THEN** 进程树收到 `SIGKILL`（Windows `taskkill /F /T`），错误文案与 bash 一致
