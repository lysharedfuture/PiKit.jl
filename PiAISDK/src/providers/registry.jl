const LOG_TAG = "ai_registry"

"""
    PROVIDERS

Registry mapping an api name (for example `"openai-completions"`) to its
stream function `f(model, ctx, opts) -> AssistantMessageEventStream`.
Populate it with `register_provider!`.
"""
const PROVIDERS = Dict{String,Function}()
const PROVIDER_MODELS = Dict{String,Vector{Model}}()

"""
    register_provider!(api, f; model=nothing)

Register the stream function `f(model, ctx, opts)` under the api name `api`.
When `model` is given it is also recorded as a catalog entry for that api.

# Arguments
- `api`: api name used by `Model.api`.
- `f`: function returning an `AssistantMessageEventStream`.
- `model`: optional `Model` to register alongside.
"""
function register_provider!(api::AbstractString, f::Function; model::Union{Nothing,Model}=nothing)
    PROVIDERS[String(api)] = f
    if model !== nothing
        push!(get!(PROVIDER_MODELS, String(api), Model[]), model)
    end
    return nothing
end

"""
    provider_registered(api) -> Bool

Return `true` when a stream function is registered for the api name `api`.
"""
function provider_registered(api::AbstractString)
    return haskey(PROVIDERS, String(api))
end

function error_event_stream(model::Model, message::String; stop_reason="error")
    return AssistantMessageEventStream() do s
        msg = empty_assistant(model; stop_reason=stop_reason, error_message=message)
        push_event!(s, StartEvent(msg))
        push_event!(s, ErrorEvent(stop_reason, msg))
    end
end

"""
    stream(model, ctx, opts=StreamOptions()) -> AssistantMessageEventStream
    stream(model, ctx; kwargs...)

Start a streaming request for `ctx` against `model`, dispatching on
`model.api` through the `PROVIDERS` registry. An unknown api yields a stream
with a single `ErrorEvent`. The call returns immediately; iterate the stream
for events or call `result` for the final message.

# Arguments
- `model`: `Model` selecting api, provider, and endpoint.
- `ctx`: `LLMContext` holding the conversation.
- `opts`: `StreamOptions`; keyword form builds them.
- `kwargs...`: forwarded to the `StreamOptions` constructor.

# Example
```julia
register_faux_provider!(responses=["Hello from faux"])
model = Model("faux-1", "Faux Model", "faux", "faux", "http://faux.invalid")
ctx = LLMContext(AbstractMessage[SystemMessage(""), UserMessage("hi")])
final = result(stream(model, ctx))  # stop_reason == "stop"
```
"""
function stream(model::Model, ctx::LLMContext, opts::StreamOptions)
    f = get(PROVIDERS, model.api, nothing)
    if f === nothing
        return error_event_stream(model, "Unknown provider api: $(model.api)")
    end
    return f(model, ctx, opts)
end

stream(model::Model, ctx::LLMContext; kwargs...) = stream(model, ctx, StreamOptions(; kwargs...))
