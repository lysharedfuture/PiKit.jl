const LOG_TAG = "pikit_cli_modes_json"

function _wire_message_update(ev::PiAgentCore.MessageUpdateEvent)
    assistant = PiAgentCore.assistant_event_to_json(ev.assistant_message_event)
    delete!(assistant, "partial")
    if assistant["type"] == "toolcall_start"
        idx = ev.assistant_message_event.content_index
        if idx >= 1 && idx <= length(ev.message.content) && ev.message.content[idx] isa PiAISDK.ToolCall
            call = ev.message.content[idx]::PiAISDK.ToolCall
            assistant["id"] = call.id
            assistant["toolName"] = call.name
        end
    end
    message = PiAISDK.message_to_json(ev.message)
    return Dict{String,Any}("type" => "message_update", "message" => message,
                            "assistantMessageEvent" => assistant, "usage" => message["usage"])
end

function _named_tuple_to_dict(x)
    if x isa NamedTuple
        return Dict{String,Any}(String(k) => _named_tuple_to_dict(v) for (k, v) in pairs(x))
    elseif x isa AbstractDict
        return Dict{String,Any}(String(k) => _named_tuple_to_dict(v) for (k, v) in x)
    elseif x isa AbstractVector
        return Any[_named_tuple_to_dict(v) for v in x]
    end
    return x
end

"""
    json_mode_event(ev) -> Dict{String,Any}

Convert an agent event to its JSON-mode dictionary. `MessageUpdateEvent` uses
the wire shape described in `docs/src/json.md`, which omits the shared
`partial` assistant message.
"""
function json_mode_event(ev)
    if ev isa PiAgentCore.MessageUpdateEvent
        return _wire_message_update(ev)
    elseif ev isa PiAgentCore.AbstractAgentEvent
        d = PiAgentCore.event_to_json(ev)
        if ev isa PiAgentCore.AgentEndEvent
            d["willRetry"] = false
        end
        return d
    elseif ev isa NamedTuple || ev isa AbstractDict
        return _named_tuple_to_dict(ev)
    end
    return Dict{String,Any}("type" => string(typeof(ev)))
end

"""
    session_json_event(s::AgentSession, ev) -> Dict{String,Any}

[`json_mode_event`](@ref) plus retry state: `agent_end` events gain `willRetry`
computed from the session retry policy and the last assistant message.
"""
function session_json_event(s::AgentSession, ev)
    d = json_mode_event(ev)
    if get(d, "type", "") == "agent_end"
        last_assistant = nothing
        for m in get(d, "messages", Any[])
            if m isa AbstractDict && get(m, "role", "") == "assistant"
                last_assistant = m
            end
        end
        retryable = false
        if last_assistant !== nothing
            msg = PiAISDK.message_from_json(last_assistant)
            retryable = msg isa PiAISDK.AssistantMessage && PiAISDK.is_retryable_assistant_error(msg)
        end
        d["willRetry"] = s.retry.enabled && !s.abort_requested &&
                         s.retry_attempt < s.retry.max_attempts && retryable
    end
    return d
end

"""
    run_json_mode(s::AgentSession, prompt_text::String; images=ImageContent[])

Send one prompt while streaming JSON events (session header first, then one
event per line) to stdout. stdout is protocol only; logs go to the file sink.
Returns the process exit code.
"""
function run_json_mode(s::AgentSession, prompt_text::String; images=PiAISDK.ImageContent[])
    println(stdout, json_write(header_to_json(s.session.header)))
    flush(stdout)
    unsubscribe = subscribe(s, ev -> begin
        println(stdout, json_write(session_json_event(s, ev)))
        flush(stdout)
    end)
    try
        isempty(prompt_text) && isempty(images) && return 0
        prompt!(s, prompt_text; images=images)
        return _assistant_exit_code(s.last_assistant)
    finally
        unsubscribe()
    end
end
