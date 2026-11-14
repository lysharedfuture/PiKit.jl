# PiAISDK

The AI layer of PiKit: message and content types, the JSON codec, Server-Sent
Events and streaming event streams, the model catalog, credential resolution,
retry/overflow classification, and the `openai-completions`,
`anthropic-messages`, and offline `faux` provider implementations. It depends
only on `HTTP`, `JSON`, and Julia stdlib.

Position in the stack: `PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit`.
Installing it alone does not pull in the agent loop, coding tools, sessions, or
the CLI. Upstream counterpart: `@earendil-works/pi-ai` from
[earendil-works/pi](https://github.com/earendil-works/pi).

## Install

```julia
using Pkg
Pkg.add("PiAISDK")                  # once registered
Pkg.develop(path="/path/to/PiKit/PiAISDK")  # local development
```

Requires Julia 1.13+.

## Quick start (offline `faux` provider)

```julia
using PiAISDK

register_faux_provider!(responses=["Hello from faux"])

model = Model("faux-1", "Faux Model", "faux", "faux", "http://faux.invalid"; reasoning=true)
ctx = LLMContext(AbstractMessage[SystemMessage(""), UserMessage("hi")])

s = stream(model, ctx)             # AssistantMessageEventStream
for ev in s
    ev isa TextDeltaEvent && print(ev.delta)
end
println()
println(result(s).stop_reason)     # stop
```

Real providers are selected by `Model.api` (`"openai-completions"` or
`"anthropic-messages"`); keys are resolved from an explicit `api_key`, then
`auth.json`, then the provider environment variable
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `<PROVIDER>_API_KEY`).

## Documentation

<https://lysharedfuture.github.io/PiKit.jl/dev/sdk/>
