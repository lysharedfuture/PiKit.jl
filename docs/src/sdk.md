# PiAISDK

`PiAISDK` is the base layer of the PiKit stack (`PiAISDK ← PiAgentCore ←
PiCodingAgent ← PiKit`) and the Julia counterpart of `@earendil-works/pi-ai`.
It defines the content and message types shared by every layer, the JSON codec
that preserves unknown fields, SSE parsing and the `AssistantMessageEventStream`
event model, the model catalog and credential lookup, retry and context-overflow
classification, and the `openai-completions`, `anthropic-messages`, and offline
`faux` providers. It does not depend on any other PiKit package.

## Quick start

```julia
using PiAISDK

register_faux_provider!(responses=["Hello from faux"])

model = Model("faux-1", "Faux Model", "faux", "faux", "http://faux.invalid"; reasoning=true)
ctx = LLMContext(AbstractMessage[SystemMessage(""), UserMessage("hi")])

s = stream(model, ctx)
for ev in s
    ev isa TextDeltaEvent && print(ev.delta)
end
println()
println(result(s).stop_reason)  # stop
```

For a real provider, use a catalog model such as
`find_model("anthropic/claude-sonnet-4-6")` and pass an API key through
`StreamOptions(; api_key=...)` or the provider environment variable.

## API reference

```@autodocs
Modules = [PiAISDK]
```
