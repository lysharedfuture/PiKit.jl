const LOG_TAG = "ai_types"

"""
    AbstractContent

Supertype of all content blocks that can appear inside a message:
`TextContent`, `ImageContent`, `ThinkingContent`, and `ToolCall`.
"""
abstract type AbstractContent end

"""
    TextContent(text::AbstractString)
    TextContent(text, text_signature)

Plain text block.

# Fields
- `text::String`: the text.
- `text_signature::Union{Nothing,String}`: provider signature attached to the
  block, or `nothing`.
"""
struct TextContent <: AbstractContent
    text::String
    text_signature::Union{Nothing,String}
end
TextContent(text::AbstractString) = TextContent(String(text), nothing)

"""
    ImageContent(data::AbstractString, mime_type::AbstractString)

Base64-encoded image block.

# Arguments
- `data`: base64 payload without a data-URL prefix.
- `mime_type`: media type such as `"image/png"`.
"""
struct ImageContent <: AbstractContent
    data::String
    mime_type::String
end
ImageContent(data::AbstractString, mime_type::AbstractString) = ImageContent(String(data), String(mime_type))

"""
    ThinkingContent(thinking; thinking_signature=nothing, redacted=false)

Reasoning block emitted by a thinking-capable model.

# Arguments
- `thinking`: the reasoning text.
- `thinking_signature`: provider signature used when replaying the block.
- `redacted`: `true` when the provider withheld the reasoning text.
"""
struct ThinkingContent <: AbstractContent
    thinking::String
    thinking_signature::Union{Nothing,String}
    redacted::Bool
end
ThinkingContent(thinking::AbstractString; thinking_signature=nothing, redacted=false) =
    ThinkingContent(String(thinking), thinking_signature, redacted)

"""
    ToolCall(id, name, arguments; thought_signature=nothing, namespace=nothing, arguments_error=nothing)

Tool invocation requested by a model. `arguments` is the decoded argument
object; `arguments_error` records a JSON decode failure instead of discarding
the call.
"""
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

"""
    Cost(; input=0.0, output=0.0, cache_read=0.0, cache_write=0.0, total=0.0, total_from_provider=nothing)

Monetary cost of one request in US dollars. `total_from_provider` is `true`
when `total` came from the provider rather than being summed locally.
"""
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

"""
    Usage(; input=0, output=0, cache_read=0, cache_write=0, cache_write_1h=nothing, reasoning=nothing, total_tokens=0, cost=Cost())

Token counters and cost for one request. `total_tokens` is reported by the
provider when non-zero; use `token_total` to read the effective total.
"""
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

"""
    empty_usage() -> Usage

Return a fresh `Usage` with every counter at zero and an empty `Cost`.
"""
empty_usage() = Usage()

"""
    EMPTY_USAGE

Shared zero-valued `Usage`. Treat as read-only: `Usage` is mutable, so copy it
with `copy_usage` before accumulating into it.
"""
const EMPTY_USAGE = Usage()

"""
    token_total(u::Usage) -> Int

Return `u.total_tokens` when the provider reported one, otherwise the sum of
input, output, cache-read, and cache-write tokens.
"""
token_total(u::Usage) = u.total_tokens > 0 ? u.total_tokens : u.input + u.output + u.cache_read + u.cache_write

function copy_cost(c::Cost)
    return Cost(c.input, c.output, c.cache_read, c.cache_write, c.total, c.total_from_provider)
end

"""
    copy_usage(u::Usage) -> Usage

Return a copy of `u` that shares no mutable state with the original.
"""
function copy_usage(u::Usage)
    return Usage(u.input, u.output, u.cache_read, u.cache_write, u.cache_write_1h,
                 u.reasoning, u.total_tokens, copy_cost(u.cost))
end

"""
    apply_cost!(u::Usage, mc) -> Usage

Compute `u.cost` from the per-million-token rates in the `ModelCost` `mc` and
the counters in `u`, applying the matching tier when `mc.tiers` is non-empty.
`u.cost.total` is recomputed unless it was provider-reported. Returns `u`.
"""
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

"""
    AbstractMessage

Supertype of every conversation message: `SystemMessage`, `UserMessage`,
`AssistantMessage`, and `ToolResultMessage`.
"""
abstract type AbstractMessage end

"""
    AbstractAgentMessage

Alias of `AbstractMessage` kept for upstream naming compatibility.
"""
const AbstractAgentMessage = AbstractMessage

"""
    as_content(v) -> Vector{AbstractContent}

Normalize `v` to a `Vector{AbstractContent}`. Accepts a content block, a
vector of content blocks, a string (wrapped in `TextContent`), or `nothing`
(empty vector).
"""
as_content(v::AbstractVector{<:AbstractContent}) = AbstractContent[v...]
as_content(v::AbstractVector) = AbstractContent[x for x in v if x isa AbstractContent]
as_content(v::AbstractContent) = AbstractContent[v]
as_content(v::AbstractString) = AbstractContent[TextContent(String(v))]
as_content(::Nothing) = AbstractContent[]

structure_content(c::Union{AbstractString,Vector{AbstractContent}}) =
    c isa AbstractString ? String(c) : as_content(c)

"""
    SystemMessage(content=""; sections=nothing, tools_added=Dict{String,Any}[], tools_removed=Dict{String,Any}[], timestamp=time_millis(), extra=Dict{String,Any}())

System prompt message. `content` may be a string or a vector of content
blocks; `sections` holds named prompt sections as `name => text` pairs;
`tools_added` and `tools_removed` describe the tool set in effect from this
message onward. `extra` preserves unknown fields across JSON round trips.
"""
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

"""
    UserMessage(content; timestamp=time_millis(), extra=Dict{String,Any}())

Message authored by the user. `content` may be a string or a vector of
content blocks.
"""
struct UserMessage <: AbstractMessage
    content::Union{String,Vector{AbstractContent}}
    timestamp::Int64
    extra::Dict{String,Any}
end
UserMessage(content; timestamp=time_millis(), extra=Dict{String,Any}()) =
    UserMessage(structure_content(content), timestamp, extra)

"""
    AssistantMessage(content=AbstractContent[]; api="", provider="", model="", response_model=nothing, response_id=nothing, usage=empty_usage(), stop_reason="pending", error_message=nothing, provider_thinking_level=nothing, thinking_level=nothing, timestamp=time_millis(), duration_ms=nothing, extra=Dict{String,Any}())

Model response. `stop_reason` is one of `STOP_REASONS`; `error_message` is
set when `stop_reason` is `"error"` or `"aborted"`; `partial` messages in
stream events are the message built so far. `extra` preserves unknown fields
across JSON round trips.
"""
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

"""
    ToolResultMessage(tool_call_id, tool_name, content; details=nothing, usage=nothing, is_error=false, timestamp=time_millis(), duration_ms=nothing, extra=Dict{String,Any}())

Result of executing the tool call `tool_call_id`. `details` carries
tool-specific structured output, `usage` the optional token usage, and
`is_error` marks failed executions.
"""
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

"""
    AbstractAssistantMessageEvent

Supertype of the streaming events pushed by a provider into an
`AssistantMessageEventStream`.
"""
abstract type AbstractAssistantMessageEvent end

"""
    StartEvent(partial)

Emitted once before the first content event. `partial` is the empty assistant
message being filled in.
"""
struct StartEvent <: AbstractAssistantMessageEvent
    partial::AssistantMessage
end

"""
    TextStartEvent(content_index, partial)

A text block at `content_index` started.
"""
struct TextStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end

"""
    TextDeltaEvent(content_index, delta, partial)

Incremental text `delta` for the block at `content_index`.
"""
struct TextDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end

"""
    TextEndEvent(content_index, content, partial)

The text block at `content_index` completed with `content`.
"""
struct TextEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    content::String
    partial::AssistantMessage
end

"""
    ThinkingStartEvent(content_index, partial)

A thinking block at `content_index` started.
"""
struct ThinkingStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end

"""
    ThinkingDeltaEvent(content_index, delta, partial)

Incremental reasoning `delta` for the block at `content_index`.
"""
struct ThinkingDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end

"""
    ThinkingEndEvent(content_index, content, partial)

The thinking block at `content_index` completed with `content`.
"""
struct ThinkingEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    content::String
    partial::AssistantMessage
end

"""
    ToolCallStartEvent(content_index, partial)

A tool call at `content_index` started.
"""
struct ToolCallStartEvent <: AbstractAssistantMessageEvent
    content_index::Int
    partial::AssistantMessage
end

"""
    ToolCallDeltaEvent(content_index, delta, partial)

Incremental JSON `delta` of the tool call arguments at `content_index`.
"""
struct ToolCallDeltaEvent <: AbstractAssistantMessageEvent
    content_index::Int
    delta::String
    partial::AssistantMessage
end

"""
    ToolCallEndEvent(content_index, tool_call, partial)

The tool call at `content_index` completed; `tool_call` holds the parsed call.
"""
struct ToolCallEndEvent <: AbstractAssistantMessageEvent
    content_index::Int
    tool_call::ToolCall
    partial::AssistantMessage
end

"""
    DoneEvent(reason, message)

Terminal event of a successful stream. `reason` is the final stop reason.
"""
struct DoneEvent <: AbstractAssistantMessageEvent
    reason::String
    message::AssistantMessage
end

"""
    ErrorEvent(reason, error)

Terminal event of a failed or aborted stream; `error` is the final assistant
message carrying `error_message`.
"""
struct ErrorEvent <: AbstractAssistantMessageEvent
    reason::String
    error::AssistantMessage
end

"""
    ModelCost(input, output, cache_read, cache_write)
    ModelCost(input, output, cache_read, cache_write, tiers)

Per-million-token price list of a model. `tiers` optionally overrides the
base rates for prompts above an `"inputTokensAbove"` threshold.
"""
struct ModelCost
    input::Float64
    output::Float64
    cache_read::Float64
    cache_write::Float64
    tiers::Vector{Dict{String,Any}}
end
ModelCost(input, output, cache_read, cache_write) =
    ModelCost(Float64(input), Float64(output), Float64(cache_read), Float64(cache_write), Dict{String,Any}[])

"""
    Model(id, name="", api="", provider="", base_url=""; reasoning=false, input=["text"], context_window=128_000, max_tokens=16_384, cost=ModelCost(0, 0, 0, 0), thinking_level_map=Dict{String,Union{String,Nothing}}(), compat=Dict{String,Any}())

Model descriptor used to build requests. `api` selects the registered provider
stream function (for example `"openai-completions"`); `provider` is the
credential/catalog key; `input` lists accepted modalities; `compat` holds
provider quirk flags.
"""
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

"""
    ToolDeclaration(name, description, parameters)

Tool advertised to a model. `parameters` is a JSON Schema object describing
the accepted arguments.
"""
struct ToolDeclaration
    name::String
    description::String
    parameters::Dict{String,Any}
end

"""
    AbortToken()

Cooperative cancellation signal. Pending requests poll `is_aborted` and
registered callbacks are run by `abort!`.
"""
mutable struct AbortToken
    flag::Bool
    callbacks::Vector{Function}
    lock::ReentrantLock
end
AbortToken() = AbortToken(false, Function[], ReentrantLock())

"""
    is_aborted(token) -> Bool

Return `true` once `abort!` has fired on `token`. `nothing` is treated as a
token that never aborts.
"""
is_aborted(t::AbortToken) = lock(t.lock) do
    t.flag
end
is_aborted(::Nothing) = false

"""
    on_abort(f, token)

Register `f` to run when `token` is aborted. If the token is already aborted,
`f` runs immediately in the calling task. Exceptions from `f` are logged at
debug level and swallowed.
"""
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

"""
    abort!(token)

Set the abort flag and run every registered callback once. Callbacks are
removed before they run, so a second call is a no-op. Callback exceptions are
logged at debug level and swallowed.
"""
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

"""
    StreamOptions(; kwargs...)

Options for one `stream` call.

# Keyword arguments
- `api_key`: explicit credential; otherwise resolved by the provider.
- `signal`: `AbortToken` polled during the request.
- `headers`: extra HTTP headers; a `nothing` value removes a default header.
- `env`, `identity`: caller metadata carried through unchanged; the built-in
  providers do not read them.
- `on_payload`: `f(body, model)` called before sending, returning a replacement
  body or `nothing`.
- `on_response`: `f(status, headers, model)` called when the HTTP response
  arrives.
- `timeout_ms`: read timeout; defaults to 600000 ms.
- `max_retries`: retry attempts for retryable HTTP failures (default `2`).
- `max_retry_delay_ms`: cap for retry backoff (default `60000`).
- `temperature`, `max_tokens`: request overrides; `max_tokens` defaults to
  `model.max_tokens`.
- `reasoning`: thinking level name, one of `THINKING_LEVELS`.
- `thinking_budgets`: token budgets per thinking level.
- `session_id`: prompt-cache key for OpenAI-compatible providers.
- `cache_retention`: `"none"`, `"short"` (default), or `"long"`.
"""
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

"""
    LLMContext(messages)

Conversation state handed to a provider. `messages` is used as given; pass a
context through `normalize_context` when a leading `SystemMessage` must be
guaranteed.
"""
struct LLMContext
    messages::Vector{AbstractMessage}
end

"""
    STOP_REASONS

Valid values of `AssistantMessage.stop_reason`: `"pending"`, `"stop"`,
`"length"`, `"toolUse"`, `"error"`, `"aborted"`, and `"deferred"`.
"""
const STOP_REASONS = ("pending", "stop", "length", "toolUse", "error", "aborted", "deferred")

"""
    THINKING_LEVELS

Valid thinking levels, from `"off"` to `"max"`.
"""
const THINKING_LEVELS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")

"""
    time_millis() -> Int64

Current wall-clock time as Unix milliseconds.
"""
time_millis() = Int64(floor(time() * 1000))

"""
    normalize_context(ctx::LLMContext) -> LLMContext

Return a copy of `ctx` with an empty `SystemMessage` prepended when the first
message is not a system message or the context is empty.
"""
function normalize_context(ctx::LLMContext)
    messages = AbstractMessage[ctx.messages...]
    if isempty(messages) || !(messages[1] isa SystemMessage)
        pushfirst!(messages, SystemMessage(""))
    end
    return LLMContext(messages)
end

"""
    empty_assistant(model; stop_reason="pending", error_message=nothing, provider_thinking_level=nothing, thinking_level=nothing) -> AssistantMessage

Build an empty `AssistantMessage` tagged with `model`'s id, api, and provider,
suitable as the `partial` of stream events.
"""
function empty_assistant(model::Model; stop_reason="pending", error_message=nothing,
                         provider_thinking_level=nothing, thinking_level=nothing)
    return AssistantMessage(AbstractContent[];
        api=model.api, provider=model.provider, model=model.id,
        usage=empty_usage(), stop_reason=stop_reason, error_message=error_message,
        provider_thinking_level=provider_thinking_level,
        thinking_level=thinking_level)
end
