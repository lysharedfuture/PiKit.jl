# PiKit.jl

Unofficial Julia port of the [pi](https://github.com/earendil-works/pi) agent
stack (`pi-ai`, `pi-agent-core`, `pi-coding-agent`). The verified upstream
baseline, capability matrix and known deviations are tracked in
[`upstream-compat.md`](upstream-compat.md).

PiKit is an independent MIT-licensed project. It is not affiliated with the
upstream authors.

## Packages

| Package | Role | Upstream |
|---|---|---|
| [`PiAISDK`](sdk.md) | message/content types, event streams, SSE, JSON codec, schema validation, model catalog, credentials, retry, providers | `pi-ai` |
| [`PiAgentCore`](agent-core.md) | agent loop, hooks, queues, abort, tool execution, event model | `pi-agent-core` |
| [`PiCodingAgent`](coding-agent.md) | coding tools, session v3, compaction, system prompt, `AgentSession` runtime | `pi-coding-agent` (library part) |
| [`PiKit`](pikit.md) | CLI (`print`/`json`/`rpc`/`repl`), config, log sink, `PiKit.main` | `pi-coding-agent` (CLI part) |

Dependency direction is `PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit`; each
package can be installed on its own.

```julia
using Pkg
Pkg.add(["PiAISDK", "PiAgentCore", "PiCodingAgent", "PiKit"])
```

From a checkout, `Pkg.develop(path="/path/to/PiKit")` resolves the subpackages
through the root project.

## PiAISDK

```julia
using PiAISDK

PiAISDK.set_responses!([PiAISDK.faux_text("hello")])
model = PiAISDK.find_model("faux/faux-1")
stream = PiAISDK.stream(model, PiAISDK.LLMContext(PiAISDK.AbstractMessage[PiAISDK.UserMessage("hi")]))
message = PiAISDK.result(stream)
message.content[1].text          # "hello"
```

`PiAISDK` installs no global logger: logs use the caller's logger and never
write `~/.pikit` state.

## PiAgentCore

```julia
using PiAISDK, PiAgentCore

PiAISDK.set_responses!([PiAISDK.faux_text("done")])
agent = PiAgentCore.Agent(model=PiAISDK.find_model("faux/faux-1"),
                          tools=PiAgentCore.Tool[], system_prompt="be brief")
PiAgentCore.subscribe(agent, ev -> println(PiAgentCore.event_type(ev)))
PiAgentCore.prompt!(agent, "hello")
```

## PiCodingAgent

```julia
using PiAISDK, PiCodingAgent

cwd = mktempdir()
PiAISDK.set_responses!([PiAISDK.faux_text("done")])
manager = PiCodingAgent.create_session(cwd; dir=cwd, in_memory=true)
session = PiCodingAgent.create_agent_session(
    cwd=cwd, model=PiAISDK.find_model("faux/faux-1"), session_manager=manager,
    settings=Dict{String,Any}("autoCompaction" => false), tools_names=String[])
PiCodingAgent.prompt!(session, "hi")
session.last_assistant.content[1].text   # "done"
PiCodingAgent.close!(session)
```

`grep` uses `ripgrep_jll` and `find` uses `fd_jll`; no binaries are downloaded
at runtime.

## PiKit

```sh
julia -m PiKit -p "hi"
julia -m PiKit --mode json -p "hi"
julia -m PiKit --version
```

From a repository checkout, `bin/pikit` is equivalent. See [CLI](cli.md),
[JSON events](json.md) and [Sessions](sessions.md).
