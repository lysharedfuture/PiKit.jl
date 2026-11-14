# PiCodingAgent

Coding-agent layer of the PiKit stack. It provides the file and shell tools, the
session v3 JSONL format, context compaction, the system-prompt builder, and the
`AgentSession` runtime that ties them together.

This package corresponds to the library part of
[`@earendil-works/pi-coding-agent`](https://github.com/earendil-works/pi). The
CLI, configuration and RPC layers live in `PiKit`.

PiKit is an independent MIT-licensed project. It is not affiliated with the
upstream authors.

## Position in the stack

```
PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit
```

`PiCodingAgent` depends on `PiAgentCore` (agent loop, tools, events) and
`PiAISDK` (message/content types, streams, providers). It can be installed on
its own, without the CLI.

## Install

```julia
using Pkg
Pkg.add("PiCodingAgent")            # once registered
Pkg.develop(path="/path/to/PiKit/PiCodingAgent")   # local development
```

Requires Julia 1.13+.

## Tools

`create_tools(cwd; names=...)` builds `PiAgentCore.Tool` instances:

| Name | Behavior |
|---|---|
| `read` | Read text files with truncation and `offset`/`limit` paging; attach supported images when the model accepts image input. |
| `bash` | Run a command through the platform shell, streaming output and saving truncated output to a temp file. |
| `edit` | Apply one or more exact, unique `oldText`/`newText` replacements; returns a diff and unified patch. |
| `write` | Create or overwrite a file, creating parent directories. |
| `grep` | Search file contents (optional). |
| `find` | Find files by glob pattern (optional). |
| `ls` | List directory contents (optional). |
| `powershell` | Run PowerShell commands on Windows (optional). |

`DEFAULT_TOOL_NAMES` is `["read", "bash", "edit", "write"]`; the remaining
names are listed in `OPTIONAL_TOOL_NAMES`.

`grep` uses `ripgrep_jll` and `find` uses `fd_jll`; no binaries are downloaded
at runtime.

```julia
using PiCodingAgent

tools = create_tools(pwd(); names=["read", "bash", "edit", "write", "grep", "find", "ls"])
```

## Sessions

`create_session` creates an append-only JSONL session under
`<agent>/sessions/--<cwd-slug>--/`. Entries are linked by `parentId` and the
active branch is resolved from the leaf. `load_session`, `list_sessions`,
`find_session`, and `fork_session` manage existing sessions; `append_message!`
and `append_entry!` extend them. Pass `in_memory=true` to keep a session off
disk (useful in tests).

`build_context` reconstructs model messages from the branch, applying the latest
compaction entry and `context_edit` exclusions. Sessions with a `context_edit`
whose `replacement` is `nothing` exclude that target from model context without
rewriting the log.

## Compaction

`estimate_context_tokens` and `should_compact` decide when a conversation no
longer fits `contextWindow - reserveTokens`. `compact!` summarizes older
messages with the active model, keeps roughly `keepRecentTokens` of recent
context, and appends a `summary` compaction entry. The runtime triggers it
automatically after a turn when `autoCompaction` is enabled, and once more to
recover from a context-overflow error.

## System prompt

`build_system_sections` assembles preamble, tool list, rules, documentation
pointer, addendum, project instruction files (`AGENTS.md`, `CLAUDE.md`, ...),
and the working directory. Sections except the preamble are wrapped in
XML-like tags. `build_system_message` wraps the non-preamble sections in a
`PiAISDK.SystemMessage`.

## Runtime

`create_agent_session` wires tools, session history, system prompt, retry
policy, and event listeners into an `AgentSession`. `subscribe` receives agent
and lifecycle events; `prompt!`, `continue!`, `steer!`, `follow_up!`,
`abort!`, `settle!`, `compact!`, and `close!` drive the run. Automatic retries
and overflow recovery are applied by `prompt!`/`continue!`.

```julia
using PiAISDK, PiCodingAgent

cwd = mktempdir()
PiAISDK.set_responses!([PiAISDK.faux_text("done")])

manager = create_session(cwd; dir=cwd, in_memory=true)
session = create_agent_session(
    cwd=cwd,
    model=PiAISDK.find_model("faux/faux-1"),
    session_manager=manager,
    settings=Dict{String,Any}("autoCompaction" => false),
    tools_names=String[],
)
prompt!(session, "hi")
session.last_assistant.content[1].text   # "done"
close!(session)
```

## Documentation

Full API reference: <https://lysharedfuture.github.io/PiKit.jl/coding-agent/>
