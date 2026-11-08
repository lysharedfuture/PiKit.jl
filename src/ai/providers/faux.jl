const LOG_TAG = "ai_provider_faux"

mutable struct FauxState
    responses::Vector{Any}
    call_count::Int
    last_context::Union{Nothing,LLMContext}
    last_model::Union{Nothing,Model}
    lock::ReentrantLock
end
const FAUX_STATE = FauxState(Any[], 0, nothing, nothing, ReentrantLock())

faux_text(s) = TextContent(String(s))
faux_thinking(s) = ThinkingContent(String(s); thinking_signature=nothing)
faux_tool_call(name, args; id=nothing) = ToolCall(something(id, "call_$(time_millis())"), String(name),
                                                Dict{String,Any}(String(k) => plain(v) for (k, v) in args))

function faux_assistant_message(content; stop_reason="stop", error_message=nothing, usage=empty_usage(),
                                model_id="faux-1")
    return AssistantMessage(content; api="faux", provider="faux", model=model_id,
                            stop_reason=stop_reason, error_message=error_message,
                            usage=copy_usage(usage))
end

function set_responses!(steps)
    lock(FAUX_STATE.lock) do
        FAUX_STATE.responses = Any[steps...]
        FAUX_STATE.call_count = 0
    end
    return nothing
end

function append_responses!(steps)
    lock(FAUX_STATE.lock) do
        append!(FAUX_STATE.responses, steps)
    end
    return nothing
end

function reset_faux!()
    lock(FAUX_STATE.lock) do
        empty!(FAUX_STATE.responses)
        FAUX_STATE.call_count = 0
        FAUX_STATE.last_context = nothing
        FAUX_STATE.last_model = nothing
    end
    return nothing
end

faux_call_count() = lock(() -> FAUX_STATE.call_count, FAUX_STATE.lock)
faux_last_context() = lock(() -> FAUX_STATE.last_context, FAUX_STATE.lock)
faux_last_model() = lock(() -> FAUX_STATE.last_model, FAUX_STATE.lock)

function faux_chunks(text::String)
    chunks = String[]
    i = firstindex(text)
    while i <= lastindex(text)
        n = 12 + rand(0:8)
        j = nextind(text, i, n) - 1
        j > lastindex(text) && (j = lastindex(text))
        push!(chunks, text[i:j])
        i = nextind(text, j)
    end
    return chunks
end

function _step_to_message(step, model, ctx)
    if step isa Function
        step = step(model, ctx)
    end
    if step isa AssistantMessage
        step.api = isempty(step.api) ? "faux" : step.api
        step.provider = isempty(step.provider) ? "faux" : step.provider
        step.model = isempty(step.model) ? model.id : step.model
        return step
    elseif step isa AbstractContent
        reason = step isa ToolCall ? "toolUse" : "stop"
        return faux_assistant_message(AbstractContent[step]; stop_reason=reason)
    elseif step isa AbstractString
        return faux_assistant_message(AbstractContent[TextContent(String(step))])
    elseif step === nothing
        return nothing
    end
    throw(ArgumentError("unsupported faux response step: $(typeof(step))"))
end

function _emit_faux_blocks!(s, partial, msg)
    for c in msg.content
        if c isa TextContent
            push!(partial.content, TextContent("", c.text_signature))
            idx = length(partial.content)
            push_event!(s, TextStartEvent(idx, partial))
            for chunk in faux_chunks(c.text)
                old = partial.content[idx]::TextContent
                partial.content[idx] = TextContent(old.text * chunk, old.text_signature)
                push_event!(s, TextDeltaEvent(idx, chunk, partial))
            end
            push_event!(s, TextEndEvent(idx, c.text, partial))
        elseif c isa ThinkingContent
            push!(partial.content, ThinkingContent("", c.thinking_signature, c.redacted))
            idx = length(partial.content)
            push_event!(s, ThinkingStartEvent(idx, partial))
            if c.redacted
                partial.content[idx] = ThinkingContent(c.thinking, c.thinking_signature, true)
            else
                for chunk in faux_chunks(c.thinking)
                    old = partial.content[idx]::ThinkingContent
                    partial.content[idx] = ThinkingContent(old.thinking * chunk, old.thinking_signature, false)
                    push_event!(s, ThinkingDeltaEvent(idx, chunk, partial))
                end
            end
            push_event!(s, ThinkingEndEvent(idx, c.thinking, partial))
        elseif c isa ToolCall
            push!(partial.content, ToolCall(c.id, c.name, Dict{String,Any}()))
            idx = length(partial.content)
            push_event!(s, ToolCallStartEvent(idx, partial))
            argtext = json_write(c.arguments)
            for chunk in faux_chunks(argtext)
                push_event!(s, ToolCallDeltaEvent(idx, chunk, partial))
            end
            partial.content[idx] = c
            push_event!(s, ToolCallEndEvent(idx, c, partial))
        end
    end
    return nothing
end

function stream_faux(model::Model, ctx::LLMContext, opts::StreamOptions)
    return AssistantMessageEventStream() do s
        start_ns = time_ns()
        step = lock(FAUX_STATE.lock) do
            FAUX_STATE.call_count += 1
            FAUX_STATE.last_context = ctx
            FAUX_STATE.last_model = model
            isempty(FAUX_STATE.responses) ? nothing : popfirst!(FAUX_STATE.responses)
        end
        partial = empty_assistant(model)
        push_event!(s, StartEvent(partial))
        if step === nothing
            msg = faux_assistant_message(AbstractContent[]; stop_reason="error",
                                         error_message="No faux response queued", model_id=model.id)
            msg.duration_ms = _duration_ms(start_ns)
            push_event!(s, ErrorEvent("error", msg))
            return
        end
        msg = _step_to_message(step, model, ctx)
        _emit_faux_blocks!(s, partial, msg)
        partial.usage = copy_usage(msg.usage)
        partial.response_model = something(msg.response_model, model.id)
        partial.response_id = msg.response_id
        partial.error_message = msg.error_message
        partial.duration_ms = _duration_ms(start_ns)
        reason = msg.stop_reason
        if reason in ("error", "aborted")
            partial.stop_reason = reason
            push_event!(s, ErrorEvent(reason, partial))
        else
            reason = reason in ("stop", "length", "toolUse", "deferred") ? reason : "stop"
            partial.stop_reason = reason
            push_event!(s, DoneEvent(reason, partial))
        end
    end
end

function load_faux_responses(path::AbstractString)
    raw = json_parse(read(path, String))
    raw isa AbstractVector || throw(ArgumentError("faux responses must be a JSON array"))
    steps = Any[]
    for item in raw
        item isa AbstractDict || continue
        if haskey(item, "toolCall")
            tc = item["toolCall"]
            push!(steps, faux_tool_call(String(get(tc, "name", "unknown")),
                                        get(tc, "arguments", Dict{String,Any}()),
                                        id=get(tc, "id", nothing)))
        elseif haskey(item, "thinking")
            push!(steps, faux_thinking(get(item, "thinking", "")))
        elseif haskey(item, "content")
            content = item["content"]
            blocks = content isa AbstractString ? AbstractContent[TextContent(String(content))] :
                     AbstractContent[TextContent(String(c)) for c in content]
            push!(steps, faux_assistant_message(blocks;
                stop_reason=String(get(item, "stopReason", "stop")),
                error_message=get(item, "errorMessage", nothing)))
        end
    end
    return steps
end

function register_faux_provider!(; models=["faux-1"], responses=Any[])
    set_responses!(responses)
    for id in models
        model = Model(id, id, "faux", "faux", "http://faux.invalid"; reasoning=true)
        register_provider!("faux", stream_faux; model=model)
    end
    return nothing
end
