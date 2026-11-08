const LOG_TAG = "agent_core_types"

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

to_tool_declaration(t::Tool) = AI.ToolDeclaration(t.name, t.description, t.parameters)

struct ToolResult
    content::Vector{AI.AbstractContent}
    details::Any
    structured_content::Any
    is_error::Bool
    usage::Union{Nothing,AI.Usage}
    terminate::Bool
end
function ToolResult(content; details=nothing, structured_content=nothing, is_error=false,
                    usage=nothing, terminate=false)
    return ToolResult(AI.as_content(content), details, structured_content, is_error, usage, terminate)
end

struct AgentContext
    messages::Vector{AI.AbstractMessage}
    tools::Vector{Tool}
end
AgentContext(messages) = AgentContext(AI.AbstractMessage[messages...], Tool[])

Base.@kwdef mutable struct AgentLoopConfig
    model::AI.Model = AI.Model("unconfigured")
    stream_fn::Function = AI.stream
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

abstract type AbstractAgentEvent end

struct AgentStartEvent <: AbstractAgentEvent end
struct AgentEndEvent <: AbstractAgentEvent
    messages::Vector{AI.AbstractMessage}
end
struct TurnStartEvent <: AbstractAgentEvent end
struct TurnEndEvent <: AbstractAgentEvent
    message::AI.AssistantMessage
    tool_results::Vector{AI.ToolResultMessage}
end
struct MessageStartEvent <: AbstractAgentEvent
    message::AI.AbstractMessage
end
struct MessageUpdateEvent <: AbstractAgentEvent
    message::AI.AssistantMessage
    assistant_message_event::AI.AbstractAssistantMessageEvent
end
struct MessageEndEvent <: AbstractAgentEvent
    message::AI.AbstractMessage
end
struct ToolExecutionStartEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
end
struct ToolExecutionUpdateEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
    partial_result::Any
end
struct ToolExecutionEndEvent <: AbstractAgentEvent
    tool_call_id::String
    tool_name::String
    args::Dict{String,Any}
    result::Any
    is_error::Bool
    duration_ms::Int
end

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

function assistant_event_to_json(ev::AI.StartEvent)
    return Dict{String,Any}("type" => "start", "partial" => AI.message_to_json(ev.partial))
end
for (T, name) in ((AI.TextStartEvent, "text_start"), (AI.ThinkingStartEvent, "thinking_start"),
                  (AI.ToolCallStartEvent, "toolcall_start"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "partial" => AI.message_to_json(ev.partial))
    end
end
for (T, name) in ((AI.TextDeltaEvent, "text_delta"), (AI.ThinkingDeltaEvent, "thinking_delta"),
                  (AI.ToolCallDeltaEvent, "toolcall_delta"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "delta" => ev.delta, "partial" => AI.message_to_json(ev.partial))
    end
end
for (T, name) in ((AI.TextEndEvent, "text_end"), (AI.ThinkingEndEvent, "thinking_end"))
    @eval function assistant_event_to_json(ev::$T)
        return Dict{String,Any}("type" => $name, "contentIndex" => ev.content_index,
                                "content" => ev.content, "partial" => AI.message_to_json(ev.partial))
    end
end
function assistant_event_to_json(ev::AI.ToolCallEndEvent)
    return Dict{String,Any}("type" => "toolcall_end", "contentIndex" => ev.content_index,
                            "toolCall" => AI.to_json(ev.tool_call), "partial" => AI.message_to_json(ev.partial))
end
function assistant_event_to_json(ev::AI.DoneEvent)
    return Dict{String,Any}("type" => "done", "reason" => ev.reason, "message" => AI.message_to_json(ev.message))
end
function assistant_event_to_json(ev::AI.ErrorEvent)
    return Dict{String,Any}("type" => "error", "reason" => ev.reason, "error" => AI.message_to_json(ev.error))
end

function event_to_json(ev::AgentStartEvent)
    return Dict{String,Any}("type" => event_type(ev))
end
function event_to_json(ev::AgentEndEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "messages" => Any[AI.message_to_json(m) for m in ev.messages])
end
function event_to_json(ev::TurnStartEvent)
    return Dict{String,Any}("type" => event_type(ev))
end
function event_to_json(ev::TurnEndEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "message" => AI.message_to_json(ev.message),
                            "toolResults" => Any[AI.message_to_json(m) for m in ev.tool_results])
end
function event_to_json(ev::MessageStartEvent)
    return Dict{String,Any}("type" => event_type(ev), "message" => AI.message_to_json(ev.message))
end
function event_to_json(ev::MessageUpdateEvent)
    return Dict{String,Any}("type" => event_type(ev),
                            "message" => AI.message_to_json(ev.message),
                            "assistantMessageEvent" => assistant_event_to_json(ev.assistant_message_event))
end
function event_to_json(ev::MessageEndEvent)
    return Dict{String,Any}("type" => event_type(ev), "message" => AI.message_to_json(ev.message))
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

function default_convert_to_llm(messages)
    out = AI.AbstractMessage[]
    for m in messages
        if m isa AI.SystemMessage || m isa AI.UserMessage || m isa AI.AssistantMessage || m isa AI.ToolResultMessage
            push!(out, m)
        end
    end
    return out
end
