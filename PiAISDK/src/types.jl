const LOG_TAG = "ai_types"

abstract type AbstractContent end

struct TextContent <: AbstractContent
    text::String
    text_signature::Union{Nothing,String}
end
TextContent(text::AbstractString) = TextContent(String(text), nothing)

struct ImageContent <: AbstractContent
    data::String
    mime_type::String
end
ImageContent(data::AbstractString, mime_type::AbstractString) = ImageContent(String(data), String(mime_type))

struct ThinkingContent <: AbstractContent
    thinking::String
    thinking_signature::Union{Nothing,String}
    redacted::Bool
end
ThinkingContent(thinking::AbstractString; thinking_signature=nothing, redacted=false) =
    ThinkingContent(String(thinking), thinking_signature, redacted)

struct ToolCall <: AbstractContent
    id::String
    name::String
    arguments::Dict{String,Any}
    thought_signature::Union{Nothing,String}
    namespace::Union{Nothing,String}
    arguments_error::Union{Nothing,String}
end
ToolCall(id, name, arguments; thought_signature=nothing, namespace=nothing, arguments_error=nothing) =
    ToolCall(id, name, arguments, thought_signature, namespace, arguments_error)

mutable struct Cost
    input::Float64
    output::Float64
    cache_read::Float64
    cache_write::Float64
    total::Float64
    total_from_provider::Union{Nothing,Bool}
end
Cost(; input=0.0, output=0.0, cache_read=0.0, cache_write=0.0, total=0.0, total_from_provider=nothing) =
    Cost(input, output, cache_read, cache_write, total, total_from_provider)

mutable struct Usage
    input::Int
    output::Int
    cache_read::Int
    cache_write::Int
    cache_write_1h::Union{Nothing,Int}
    reasoning::Union{Nothing,Int}
    total_tokens::Int
    cost::Cost
end
Usage(; input=0, output=0, cache_read=0, cache_write=0, cache_write_1h=nothing,
        reasoning=nothing, total_tokens=0, cost=Cost()) =
    Usage(input, output, cache_read, cache_write, cache_write_1h, reasoning, total_tokens, cost)

empty_usage() = Usage()
const EMPTY_USAGE = Usage()

token_total(u::Usage) = u.total_tokens > 0 ? u.total_tokens : u.input + u.output + u.cache_read + u.cache_write

function copy_cost(c::Cost)
    return Cost(c.input, c.output, c.cache_read, c.cache_write, c.total, c.total_from_provider)
end

function copy_usage(u::Usage)
    return Usage(u.input, u.output, u.cache_read, u.cache_write, u.cache_write_1h,
                 u.reasoning, u.total_tokens, copy_cost(u.cost))
end

function apply_cost!(u::Usage, mc)
    input_rate = mc.input
    output_rate = mc.output
    cache_read_rate = mc.cache_read
    cache_write_rate = mc.cache_write
    if !isempty(mc.tiers)
        best = nothing
        for tier in mc.tiers
            threshold = get(tier, "inputTokensAbove", 0)
            if u.input > threshold && (best === nothing || threshold > get(best, "inputTokensAbove", 0))
                best = tier
            end
        end
        if best !== nothing
            input_rate = get(best, "input", input_rate)
            output_rate = get(best, "output", output_rate)
            cache_read_rate = get(best, "cacheRead", cache_read_rate)
            cache_write_rate = get(best, "cacheWrite", cache_write_rate)
        end
    end
    c = u.cost
    c.input = u.input * input_rate / 1_000_000
    c.output = u.output * output_rate / 1_000_000
    c.cache_read = u.cache_read * cache_read_rate / 1_000_000
    c.cache_write = u.cache_write * cache_write_rate / 1_000_000
    if c.total_from_provider !== true
        c.total = c.input + c.output + c.cache_read + c.cache_write
    end
    return u
end

abstract type AbstractMessage end
const AbstractAgentMessage = AbstractMessage

as_content(v::AbstractVector{<:AbstractContent}) = AbstractContent[v...]
as_content(v::AbstractVector) = AbstractContent[x for x in v if x isa AbstractContent]
as_content(v::AbstractContent) = AbstractContent[v]
as_content(v::AbstractString) = AbstractContent[TextContent(String(v))]
as_content(::Nothing) = AbstractContent[]

structure_content(c::Union{AbstractString,Vector{AbstractContent}}) =
    c isa AbstractString ? String(c) : as_content(c)

mutable struct SystemMessage <: AbstractMessage
    content::Union{String,Vector{AbstractContent}}
    sections::Union{Nothing,Vector{Pair{String,Union{String,Nothing}}}}
    tools_added::Vector{Dict{String,Any}}
    tools_removed::Vector{Dict{String,Any}}
    timestamp::Int64
    extra::Dict{String,Any}
end
SystemMessage(content=""; sections=nothing, tools_added=Dict{String,Any}[],
              tools_removed=Dict{String,Any}[], timestamp=time_millis(), extra=Dict{String,Any}()) =
    SystemMessage(structure_content(content), sections, tools_added, tools_removed, timestamp, extra)

struct UserMessage <: AbstractMessage
    content::Union{String,Vector{AbstractContent}}
    timestamp::Int64
    extra::Dict{String,Any}
end
UserMessage(content; timestamp=time_millis(), extra=Dict{String,Any}()) =
    UserMessage(structure_content(content), timestamp, extra)

mutable struct AssistantMessage <: AbstractMessage
    content::Vector{AbstractContent}
    api::String
    provider::String
    model::String
    response_model::Union{Nothing,String}
    response_id::Union{Nothing,String}
    usage::Usage
    stop_reason::String
    error_message::Union{Nothing,String}
    provider_thinking_level::Union{Nothing,String}
    thinking_level::Union{Nothing,String}
    timestamp::Int64
    duration_ms::Union{Nothing,Int}
    extra::Dict{String,Any}
end
function AssistantMessage(content=AbstractContent[];
                          api="", provider="", model="", response_model=nothing,
                          response_id=nothing, usage=empty_usage(), stop_reason="pending",
                          error_message=nothing, provider_thinking_level=nothing,
                          thinking_level=nothing, timestamp=time_millis(),
                          duration_ms=nothing, extra=Dict{String,Any}())
    return AssistantMessage(as_content(content), api, provider, model, response_model,
                            response_id, usage, stop_reason, error_message,
                            provider_thinking_level, thinking_level, timestamp,
                            duration_ms, extra)
end

struct ToolResultMessage <: AbstractMessage
    tool_call_id::String
    tool_name::String
    content::Vector{AbstractContent}
    details::Any
    usage::Union{Nothing,Usage}
    is_error::Bool
    timestamp::Int64
    duration_ms::Union{Nothing,Int}
    extra::Dict{String,Any}
end
function ToolResultMessage(tool_call_id, tool_name, content;
                           details=nothing, usage=nothing, is_error=false,
                           timestamp=time_millis(), duration_ms=nothing,
                           extra=Dict{String,Any}())
    return ToolResultMessage(String(tool_call_id), String(tool_name), as_content(content),
                             details, usage, is_error, timestamp, duration_ms, extra)
end

abstract type AbstractAssistantMessageEvent end

struct StartEvent <: AbstractAssistantMessageEvent
    partial::AssistantMessage
end
struct TextStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end
struct TextDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end
struct TextEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    content::String
    partial::AssistantMessage
end
struct ThinkingStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end
struct ThinkingDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end
struct ThinkingEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    content::String
    partial::AssistantMessage
end
struct ToolCallStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end
struct ToolCallDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end
struct ToolCallEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    tool_call::ToolCall
    partial::AssistantMessage
end
struct DoneEvent <: AbstractAssistantMessageEvent
    reason::String
    message::AssistantMessage
end
struct ErrorEvent <: AbstractAssistantMessageEvent
    reason::String
    error::AssistantMessage
end

struct ModelCost
    input::Float64
    output::Float64
    cache_read::Float64
    cache_write::Float64
    tiers::Vector{Dict{String,Any}}
end
ModelCost(input, output, cache_read, cache_write) =
    ModelCost(Float64(input), Float64(output), Float64(cache_read), Float64(cache_write), Dict{String,Any}[])

struct Model
    id::String
    name::String
    api::String
    provider::String
    base_url::String
    reasoning::Bool
    input::Vector{String}
    context_window::Int
    max_tokens::Int
    cost::ModelCost
    thinking_level_map::Dict{String,Union{String,Nothing}}
    compat::Dict{String,Any}
end
function Model(id, name="", api="", provider="", base_url=""; reasoning=false,
               input=["text"], context_window=128_000, max_tokens=16_384,
               cost=ModelCost(0, 0, 0, 0), thinking_level_map=Dict{String,Union{String,Nothing}}(),
               compat=Dict{String,Any}())
    return Model(String(id), String(name), String(api), String(provider), String(base_url),
                 reasoning, String[String(x) for x in input], context_window, max_tokens,
                 cost, thinking_level_map, compat)
end

struct ToolDeclaration
    name::String
    description::String
    parameters::Dict{String,Any}
end

mutable struct AbortToken
    flag::Bool
    callbacks::Vector{Function}
    lock::ReentrantLock
end
AbortToken() = AbortToken(false, Function[], ReentrantLock())

is_aborted(t::AbortToken) = lock(t.lock) do
    t.flag
end
is_aborted(::Nothing) = false

function on_abort(f::Function, t::AbortToken)
    already_aborted = lock(t.lock) do
        if t.flag
            true
        else
            push!(t.callbacks, f)
            false
        end
    end
    if already_aborted
        try
            f()
        catch err
            @debug "abort callback failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
    end
    return nothing
end

function abort!(t::AbortToken)
    callbacks = lock(t.lock) do
        t.flag && return Function[]
        t.flag = true
        cbs = copy(t.callbacks)
        empty!(t.callbacks)
        cbs
    end
    for f in callbacks
        try
            f()
        catch err
            @debug "abort callback failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
    end
    return nothing
end

Base.@kwdef struct StreamOptions
    api_key::Union{Nothing,String} = nothing
    signal::Union{Nothing,AbortToken} = nothing
    headers::Dict{String,Union{Nothing,String}} = Dict{String,Union{Nothing,String}}()
    env::Dict{String,String} = Dict{String,String}()
    identity::Dict{String,Any} = Dict{String,Any}()
    on_payload::Union{Nothing,Function} = nothing
    on_response::Union{Nothing,Function} = nothing
    timeout_ms::Union{Nothing,Int} = nothing
    max_retries::Int = 2
    max_retry_delay_ms::Int = 60_000
    temperature::Union{Nothing,Float64} = nothing
    max_tokens::Union{Nothing,Int} = nothing
    reasoning::Union{Nothing,String} = nothing
    thinking_budgets::Dict{String,Int} = Dict("low" => 2048, "medium" => 8192, "high" => 16384, "xhigh" => 32768, "max" => 32768)
    session_id::Union{Nothing,String} = nothing
    cache_retention::Union{Nothing,String} = nothing
end

struct LLMContext
    messages::Vector{AbstractMessage}
end

const STOP_REASONS = ("pending", "stop", "length", "toolUse", "error", "aborted", "deferred")

const THINKING_LEVELS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")

time_millis() = Int64(floor(time() * 1000))

function normalize_context(ctx::LLMContext)
    messages = AbstractMessage[ctx.messages...]
    if isempty(messages) || !(messages[1] isa SystemMessage)
        pushfirst!(messages, SystemMessage(""))
    end
    return LLMContext(messages)
end

function empty_assistant(model::Model; stop_reason="pending", error_message=nothing,
                         provider_thinking_level=nothing, thinking_level=nothing)
    return AssistantMessage(AbstractContent[];
        api=model.api, provider=model.provider, model=model.id,
        usage=empty_usage(), stop_reason=stop_reason, error_message=error_message,
        provider_thinking_level=provider_thinking_level,
        thinking_level=thinking_level)
end
