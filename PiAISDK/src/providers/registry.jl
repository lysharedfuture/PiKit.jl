const LOG_TAG = "ai_registry"

const PROVIDERS = Dict{String,Function}()
const PROVIDER_MODELS = Dict{String,Vector{Model}}()

function register_provider!(api::AbstractString, f::Function; model::Union{Nothing,Model}=nothing)
    PROVIDERS[String(api)] = f
    if model !== nothing
        push!(get!(PROVIDER_MODELS, String(api), Model[]), model)
    end
    return nothing
end

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

function stream(model::Model, ctx::LLMContext, opts::StreamOptions)
    f = get(PROVIDERS, model.api, nothing)
    if f === nothing
        return error_event_stream(model, "Unknown provider api: $(model.api)")
    end
    return f(model, ctx, opts)
end

stream(model::Model, ctx::LLMContext; kwargs...) = stream(model, ctx, StreamOptions(; kwargs...))
