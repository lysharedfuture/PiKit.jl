const LOG_TAG = "agent_core_types"

"""
    Tool(name, description, parameters, execute; label="", prepare_arguments=nothing,
         execution_mode=:parallel)

Describe a callable tool exposed to the model.

`parameters` is a JSON Schema object validated by `PiAISDK.validate_arguments`
before execution. `execute` is called as
`execute(tool_call_id, args, signal, on_update)`, where `on_update` receives
partial results. `prepare_arguments`, when set, may rewrite `args` before
validation. `execution_mode` is `:parallel` or `:sequential`; one sequential
tool forces the whole batch of tool calls to run sequentially.

# Fields
- `name::String`: tool name sent to the model.
- `description::String`: natural-language description.
- `parameters::Dict{String,Any}`: JSON Schema for the arguments.
- `label::String`: display label for user interfaces.
- `prepare_arguments::Union{Nothing,Function}`: optional argument preprocessor.
- `execute::Function`: tool implementation.
- `execution_mode::Symbol`: `:parallel` (default) or `:sequential`.
"""
mutable struct Tool
    name::String
    description::String
    parameters::Dict{String,Any}
    label::String
    prepare_arguments::Union{Nothing,Function}
    execute::Function
    execution_mode::Symbol
end
Tool(name, description, parameters, execute; label="", prepare_arguments=nothing,
     execution_mode=:parallel) =
    Tool(String(name), String(description), Dict{String,Any}(String(k) => v for (k, v) in parameters),
         String(label), prepare_arguments, execute, execution_mode)

"""
    to_tool_declaration(t::Tool) -> PiAISDK.ToolDeclaration

Convert a [`Tool`](@ref) to the provider-facing tool declaration.
"""
to_tool_declaration(t::Tool) = PiAISDK.ToolDeclaration(t.name, t.description, t.parameters)

"""
    ToolResult(content; details=nothing, structured_content=nothing, is_error=false,
               usage=nothing, terminate=false)

Result returned by a [`Tool`](@ref) implementation.

`content` is converted with `PiAISDK.as_content`, so strings and content
vectors are both accepted. When every tool result of a turn sets
`terminate=true`, the agent loop stops after those results are recorded.

# Fields
- `content::Vector{PiAISDK.AbstractContent}`: model-visible tool output.
- `details::Any`: arbitrary payload for hosts and user interfaces.
- `structured_content::Any`: structured form of the result.
- `is_error::Bool`: whether the tool failed.
- `usage::Union{Nothing,PiAISDK.Usage}`: usage attributed to the tool.
- `terminate::Bool`: whether to end the agent loop after this result.
"""
struct ToolResult
    content::Vector{PiAISDK.AbstractContent}
    details::Any
    structured_content::Any
    is_error::Bool
    usage::Union{Nothing,PiAISDK.Usage}
    terminate::Bool
end
function ToolResult(content; details=nothing, structured_content=nothing, is_error=false,
                    usage=nothing, terminate=false)
    return ToolResult(PiAISDK.as_content(content), details, structured_content, is_error, usage, terminate)
end

"""
    AgentContext(messages)
    AgentContext(messages, tools)

Conversation state passed to the agent loop: message history plus available
tools.

# Fields
- `messages::Vector{PiAISDK.AbstractMessage}`: ordered conversation history.
- `tools::Vector{Tool}`: tools the model may call.
"""
struct AgentContext
    messages::Vector{PiAISDK.AbstractMessage}
    tools::Vector{Tool}
end
AgentContext(messages) = AgentContext(PiAISDK.AbstractMessage[messages...], Tool[])

"""
    AgentLoopConfig(; kwargs...)

Configuration for [`run_loop`](@ref) and [`run_agent_loop`](@ref). Every field
has a default and the `Base.@kwdef` constructor accepts it as a keyword.

# Hooks
- `stream_fn::Function`: `(model, context, options) -> stream`; defaults to `PiAISDK.stream`.
- `convert_to_llm::Function`: maps stored messages to LLM messages; defaults to [`default_convert_to_llm`](@ref).
- `transform_context::Union{Nothing,Function}`: optional `LLMContext -> LLMContext` transform applied per request.
- `get_api_key::Union{Nothing,Function}`: optional `model -> api_key`.
- `prepare_request::Union{Nothing,Function}`: optional `(request, signal)` hook returning `context`, `model` and/or `thinking_level` overrides.
- `prepare_next_turn::Union{Nothing,Function}`: optional `(turn, signal)` hook returning extra `messages`.
- `finish_turn::Union{Nothing,Function}`: optional `(turn, signal)` hook returning `:end` or `:continue`.
- `get_steering_messages::Union{Nothing,Function}`: optional `() -> messages` drained between turns.
- `get_follow_up_messages::Union{Nothing,Function}`: optional `() -> messages` drained after a turn without tool calls.
- `before_tool_call::Union{Nothing,Function}`: optional `(call, signal)` hook returning `(block=..., reason=...)`.
- `after_tool_call::Union{Nothing,Function}`: optional `(call, signal)` hook returning result overrides.

# Model and request options
- `model::PiAISDK.Model`: model used for streaming; defaults to `Model("unconfigured")`.
- `reasoning`, `session_id`, `identity`, `temperature`, `max_tokens`, `headers`, `cache_retention`: forwarded to `PiAISDK.StreamOptions`.
- `tool_choice`, `sampling_params`, `metadata`: carried for callers; not read by `run_loop`.
- `tool_execution::Symbol`: `:parallel` (default) or `:sequential`; other values raise `ArgumentError`.
"""
Base.@kwdef mutable struct AgentLoopConfig
    model::PiAISDK.Model = PiAISDK.Model("unconfigured")
    stream_fn::Function = PiAISDK.stream
    convert_to_llm::Function = default_convert_to_llm
    transform_context::Union{Nothing,Function} = nothing
    get_api_key::Union{Nothing,Function} = nothing
    finish_turn::Union{Nothing,Function} = nothing
    prepare_request::Union{Nothing,Function} = nothing
    prepare_next_turn::Union{Nothing,Function} = nothing
    get_steering_messages::Union{Nothing,Function} = nothing
    get_follow_up_messages::Union{Nothing,Function} = nothing
    before_tool_call::Union{Nothing,Function} = nothing
    after_tool_call::Union{Nothing,Function} = nothing
    tool_execution::Symbol = :parallel
    reasoning::Union{Nothing,String} = nothing
    session_id::Union{Nothing,String} = nothing
    identity::Dict{String,Any} = Dict{String,Any}()
    temperature::Union{Nothing,Float64} = nothing
    max_tokens::Union{Nothing,Int} = nothing
    tool_choice::Union{Nothing,String} = nothing
    headers::Dict{String,String} = Dict{String,String}()
    sampling_params::Dict{String,Any} = Dict{String,Any}()
    cache_retention::Union{Nothing,String} = nothing
    metadata::Dict{String,Any} = Dict{String,Any}()
end

function _validate_tool_execution(config)
    config.tool_execution in (:parallel, :sequential) ||
        throw(ArgumentError("tool_execution must be :parallel or :sequential"))
    return nothing
end

"""
    AbstractAgentEvent

Supertype of all agent loop events delivered to the `emit` callback and to
[`subscribe`](@ref PiAgentCore.subscribe) listeners.
"""
abstract type AbstractAgentEvent end

"""
    AgentStartEvent()

Emitted once when an agent run starts.
"""
struct AgentStartEvent <: AbstractAgentEvent end
"""
    AgentEndEvent(messages)

Emitted once when an agent run ends.

# Fields
- `messages::Vector{PiAISDK.AbstractMessage}`: messages produced by the run.
"""
struct AgentEndEvent <: AbstractAgentEvent
    messages::Vector{PiAISDK.AbstractMessage}
end
"""
    TurnStartEvent()

Emitted at the start of each turn, before the assistant response is streamed.
"""
struct TurnStartEvent <: AbstractAgentEvent end
"""
    TurnEndEvent(message, tool_results)

Emitted at the end of each turn.

# Fields
- `message::PiAISDK.AssistantMessage`: assistant message produced by the turn.
- `tool_results::Vector{PiAISDK.ToolResultMessage}`: tool results of the turn, empty when no tool ran.
"""
struct TurnEndEvent <: AbstractAgentEvent
    message::PiAISDK.AssistantMessage
    tool_results::Vector{PiAISDK.ToolResultMessage}
end
"""
    MessageStartEvent(message)

Emitted when a message enters the conversation.
"""
struct MessageStartEvent <: AbstractAgentEvent
    message::PiAISDK.AbstractMessage
end
"""
    MessageUpdateEvent(message, assistant_message_event)

Emitted for each streaming delta of an assistant message.

# Fields
- `message::PiAISDK.AssistantMessage`: current partial assistant message.
- `assistant_message_event::PiAISDK.AbstractAssistantMessageEvent`: underlying provider event.
"""
struct MessageUpdateEvent <: AbstractAgentEvent
    message::PiAISDK.AssistantMessage
    assistant_message_event::PiAISDK.AbstractAssistantMessageEvent
end
"""
    MessageEndEvent(message)

Emitted when a message is final.
"""
struct MessageEndEvent <: AbstractAgentEvent
    message::PiAISDK.AbstractMessage
end
"""
    ToolExecutionStartEvent(tool_call_id, tool_name, args)

Emitted before a tool starts executing.
"""
struct ToolExecutionStartEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
end
"""
    ToolExecutionUpdateEvent(tool_call_id, tool_name, args, partial_result)

Emitted when a tool reports a partial result through its `on_update` callback.
"""
struct ToolExecutionUpdateEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
    partial_result::Any
end
"""
    ToolExecutionEndEvent(tool_call_id, tool_name, args, result, is_error, duration_ms)

Emitted when a tool finishes, successfully or not.
"""
struct ToolExecutionEndEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
    result::Any
    is_error::Bool
    duration_ms::Int
end

"""
    event_type(ev::AbstractAgentEvent) -> String

Return the wire name of an agent event, such as `"agent_start"`,
`"message_update"` or `"tool_execution_end"`.
"""
event_type(::AgentStartEvent) = "agent_start"
event_type(::AgentEndEvent) = "agent_end"
event_type(::TurnStartEvent) = "turn_start"
event_type(::TurnEndEvent) = "turn_end"
event_type(::MessageStartEvent) = "message_start"
event_type(::MessageUpdateEvent) = "message_update"
event_type(::MessageEndEvent) = "message_end"
event_type(::ToolExecutionStartEvent) = "tool_execution_start"
event_type(::ToolExecutionUpdateEvent) = "tool_execution_update"
event_type(::ToolExecutionEndEvent) = "tool_execution_end"

"""
    assistant_event_to_json(ev) -> Dict{String,Any}

Convert a `PiAISDK` assistant message event (text, thinking and tool-call
start/delta/end events plus `DoneEvent`/`ErrorEvent`) to a JSON-ready
dictionary using camelCase keys such as `contentIndex`.
"""
function assistant_event_to_json(ev::PiAISDK.StartEvent)
    return Dict{String,Any}("type" => "start", "partial" => PiAISDK.message_to_json(ev.partial))
end
for (T, name) in ((PiAISDK.TextStartEvent, "text_start"), (PiAISDK.ThinkingStartEvent, "thinking_start"),
                  (PiAISDK.ToolCallStartEvent, "toolcall_start"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "partial" => PiAISDK.message_to_json(ev.partial))
    end
end
for (T, name) in ((PiAISDK.TextDeltaEvent, "text_delta"), (PiAISDK.ThinkingDeltaEvent, "thinking_delta"),
                  (PiAISDK.ToolCallDeltaEvent, "toolcall_delta"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "delta" => ev.delta, "partial" => PiAISDK.message_to_json(ev.partial))
    end
end
for (T, name) in ((PiAISDK.TextEndEvent, "text_end"), (PiAISDK.ThinkingEndEvent, "thinking_end"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "content" => ev.content, "partial" => PiAISDK.message_to_json(ev.partial))
    end
end
function assistant_event_to_json(ev::PiAISDK.ToolCallEndEvent)
    return Dict{String,Any}("type" => "toolcall_end", "contentIndex" => ev.content_index,
                            "toolCall" => PiAISDK.to_json(ev.tool_call), "partial" => PiAISDK.message_to_json(ev.partial))
end
function assistant_event_to_json(ev::PiAISDK.DoneEvent)
    return Dict{String,Any}("type" => "done", "reason" => ev.reason, "message" => PiAISDK.message_to_json(ev.message))
end
function assistant_event_to_json(ev::PiAISDK.ErrorEvent)
    return Dict{String,Any}("type" => "error", "reason" => ev.reason, "error" => PiAISDK.message_to_json(ev.error))
end

"""
    event_to_json(ev::AbstractAgentEvent) -> Dict{String,Any}

Convert an [`AbstractAgentEvent`](@ref) to a JSON-ready dictionary with a
`type` key and the event payload. Messages are converted with
`PiAISDK.message_to_json` and streaming deltas with
[`assistant_event_to_json`](@ref).
"""
function event_to_json(ev::AgentStartEvent)
    return Dict{String,Any}("type" => event_type(ev))
end
function event_to_json(ev::AgentEndEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "messages" => Any[PiAISDK.message_to_json(m) for m in ev.messages])
end
function event_to_json(ev::TurnStartEvent)
    return Dict{String,Any}("type" => event_type(ev))
end
function event_to_json(ev::TurnEndEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "message" => PiAISDK.message_to_json(ev.message),
                            "toolResults" => Any[PiAISDK.message_to_json(m) for m in ev.tool_results])
end
function event_to_json(ev::MessageStartEvent)
    return Dict{String,Any}("type" => event_type(ev), "message" => PiAISDK.message_to_json(ev.message))
end
function event_to_json(ev::MessageUpdateEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "message" => PiAISDK.message_to_json(ev.message),
                            "assistantMessageEvent" => assistant_event_to_json(ev.assistant_message_event))
end
function event_to_json(ev::MessageEndEvent)
    return Dict{String,Any}("type" => event_type(ev), "message" => PiAISDK.message_to_json(ev.message))
end
function event_to_json(ev::ToolExecutionStartEvent)
    return Dict{String,Any}("type" => event_type(ev), "toolCallId" => ev.tool_call_id,
                            "toolName" => ev.tool_name, "args" => ev.args)
end
function event_to_json(ev::ToolExecutionUpdateEvent)
    return Dict{String,Any}("type" => event_type(ev), "toolCallId" => ev.tool_call_id,
                            "toolName" => ev.tool_name, "args" => ev.args,
                            "partialResult" => ev.partial_result)
end
function event_to_json(ev::ToolExecutionEndEvent)
    d = Dict{String,Any}("type" => event_type(ev), "toolCallId" => ev.tool_call_id,
                         "toolName" => ev.tool_name, "args" => ev.args,
                         "result" => ev.result, "isError" => ev.is_error,
                         "durationMs" => ev.duration_ms)
    return d
end

"""
    default_convert_to_llm(messages) -> Vector{PiAISDK.AbstractMessage}

Keep only `SystemMessage`, `UserMessage`, `AssistantMessage` and
`ToolResultMessage` entries before a model request, dropping any other message
type from the agent history.
"""
function default_convert_to_llm(messages)
    out = PiAISDK.AbstractMessage[]
    for m in messages
        if m isa PiAISDK.SystemMessage || m isa PiAISDK.UserMessage || m isa PiAISDK.AssistantMessage || m isa PiAISDK.ToolResultMessage
            push!(out, m)
        end
    end
    return out
end
