# PiAgentCore

Agent loop layer of [PiKit.jl](https://github.com/lysharedfuture/PiKit.jl), an
unofficial Julia port of the `pi` agent stack. Not affiliated with the upstream
authors; MIT licensed.

`PiAgentCore` turns the message and provider primitives of `PiAISDK` into a
running agent: it streams assistant responses, validates and executes tool
calls (in parallel or sequentially), and emits a uniform event stream. It owns
no tools, sessions or CLI — those live in `PiCodingAgent` and `PiKit`.

## Position in the stack

```
PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit
```

- `PiAISDK`: messages, content types, providers, SSE streams, model catalog.
- `PiAgentCore`: agent loop, hooks, tool execution, event model, steering and
  follow-up queues, abort, listeners.
- `PiCodingAgent`: coding tools, session format, compaction, `AgentSession`.
- `PiKit`: CLI (`print`/`json`/`rpc`/`repl`), config, log sink.

## Upstream mapping

| PiKit package | Upstream package |
|---|---|
| `PiAgentCore` | `@earendil-works/pi-agent-core` |

The verified upstream baseline and known deviations are tracked in
[`docs/src/upstream-compat.md`](../docs/src/upstream-compat.md).

## Install

```julia
using Pkg
Pkg.add("PiAgentCore")                        # once registered
Pkg.develop(path="/path/to/PiKit/PiAgentCore") # local development
```

Requires Julia 1.13+ and `PiAISDK`; no HTTP or JSON dependency of its own.

## Minimal example

The `faux` provider from `PiAISDK` lets the loop run offline.

```julia
using PiAISDK, PiAgentCore

PiAISDK.set_responses!([PiAISDK.faux_text("Hello from PiAgentCore")])
model = PiAISDK.find_model("faux/faux-1")

context = AgentContext(AbstractMessage[])
config = AgentLoopConfig(model=model)
produced = run_agent_loop([UserMessage("hi")], context, config, nothing, _ -> nothing)
println(produced[end].content[1].text)   # Hello from PiAgentCore
```

For a stateful agent that owns its history and listeners:

```julia
agent = Agent(model=model, system_prompt="You are terse.")
subscribe(agent, ev -> println(event_type(ev)))
prompt!(agent, "hi")
println(agent.state.messages[end].content[1].text)
```

`Agent` runs the loop in a background task; `wait_idle`, `abort!`, `steer!` and
`follow_up!` control it.

## Documentation

- Agent core page: <https://lysharedfuture.github.io/PiKit.jl/dev/agent-core/>
- Full stack docs: <https://lysharedfuture.github.io/PiKit.jl/dev/>

## Development

```sh
julia --project=PiAgentCore -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```
