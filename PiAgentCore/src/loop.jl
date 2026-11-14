const LOG_TAG = "agent_core_loop"

function _build_stream_options(config::AgentLoopConfig, model::PiAISDK.Model, signal)
    api_key = config.get_api_key === nothing ? nothing : config.get_api_key(model)
    return PiAISDK.StreamOptions(
        api_key=api_key,
        signal=signal,
        headers=Dict{String,Union{Nothing,String}}(String(k) => String(v) for (k, v) in config.headers),
        identity=config.identity,
        max_tokens=config.max_tokens,
        reasoning=config.reasoning,
        temperature=config.temperature,
        session_id=config.session_id,
        cache_retention=config.cache_retention,
    )
end

function _assistant_from_events(final_msg, partial, model)
    final_msg !== nothing && return final_msg
    partial === nothing && return PiAISDK.empty_assistant(model)
    return partial
end

function stream_assistant_response!(context::AgentContext, new_messages, config::AgentLoopConfig,
                                    signal, emit)
    messages = context.messages
    messages_for_llm = config.convert_to_llm(messages)
    llm_context = PiAISDK.normalize_context(PiAISDK.LLMContext(messages_for_llm))
    if config.transform_context !== nothing
        transformed = config.transform_context(llm_context)
        transformed === nothing || (llm_context = transformed)
    end
    model = config.model
    if config.prepare_request !== nothing
        req = (context=llm_context, model=model, thinking_level=config.reasoning)
        prepared = config.prepare_request(req, signal)
        if prepared !== nothing
            if hasproperty(prepared, :context) && prepared.context !== nothing
                llm_context = prepared.context
            end
            if hasproperty(prepared, :model) && prepared.model !== nothing
                model = prepared.model
            end
            if hasproperty(prepared, :thinking_level) && prepared.thinking_level !== nothing
                config.reasoning = prepared.thinking_level
            end
        end
    end
    opts = _build_stream_options(config, model, signal)
    stream_obj = config.stream_fn(model, llm_context, opts)
    partial = nothing
    final_msg = nothing
    start_emitted = false
    seen_start = false
    for ev in stream_obj
        if ev isa PiAISDK.StartEvent
            seen_start = true
            partial = ev.partial
            push!(messages, partial)
            push!(new_messages, partial)
            emit(MessageStartEvent(partial))
            start_emitted = true
        elseif ev isa PiAISDK.DoneEvent || ev isa PiAISDK.ErrorEvent
            final_msg = ev isa PiAISDK.DoneEvent ? ev.message : ev.error
            if !start_emitted
                partial = final_msg
                push!(messages, final_msg)
                push!(new_messages, final_msg)
                emit(MessageStartEvent(final_msg))
            else
                idx = findlast(m -> m === partial, messages)
                if idx !== nothing
                    messages[idx] = final_msg
                end
                idx2 = findlast(m -> m === partial, new_messages)
                if idx2 !== nothing
                    new_messages[idx2] = final_msg
                end
            end
            emit(MessageEndEvent(final_msg))
        else
            if !start_emitted
                partial = PiAISDK.empty_assistant(model)
                push!(messages, partial)
                push!(new_messages, partial)
                emit(MessageStartEvent(partial))
                start_emitted = true
            end
            evp = getproperty(ev, :partial)
            if evp !== nothing
                partial = evp
                idx = findlast(m -> m === partial, messages)
                if idx === nothing
                    push!(messages, partial)
                    push!(new_messages, partial)
                end
            end
            emit(MessageUpdateEvent(evp, ev))
        end
    end
    if final_msg === nothing
        final_msg = _assistant_from_events(nothing, partial, model)
        if partial === nothing
            push!(messages, final_msg)
            push!(new_messages, final_msg)
            emit(MessageStartEvent(final_msg))
        end
        emit(MessageEndEvent(final_msg))
    end
    return final_msg
end

function _tool_result_message(call, result::ToolResult, duration_ms)
    return PiAISDK.ToolResultMessage(call.id, call.name, result.content;
        details=result.details, usage=result.usage, is_error=result.is_error,
        duration_ms=duration_ms)
end

function _tool_error_result(text; details=nothing)
    return ToolResult(AbstractContent[PiAISDK.TextContent(String(text))]; details=details, is_error=true)
end

function execute_tool_calls(context::AgentContext, assistant::PiAISDK.AssistantMessage,
                            config::AgentLoopConfig, signal, emit)
    calls = PiAISDK.ToolCall[c for c in assistant.content if c isa PiAISDK.ToolCall]
    isempty(calls) && return PiAISDK.ToolResultMessage[], false

    tool_map = Dict{String,Tool}(t.name => t for t in context.tools)
    result_messages = PiAISDK.ToolResultMessage[]
    all_terminate = true

    if assistant.stop_reason == "length"
        for call in calls
            emit(ToolExecutionStartEvent(call.id, call.name, call.arguments))
            text = "Tool call was not executed because the response was truncated (stop_reason=length)."
            result = _tool_error_result(text)
            emit(ToolExecutionEndEvent(call.id, call.name, call.arguments, result, true, 0))
            msg = _tool_result_message(call, result, 0)
            push!(result_messages, msg)
            emit(MessageStartEvent(msg))
            emit(MessageEndEvent(msg))
        end
        return result_messages, false
    end

    prepared = Any[]
    for call in calls
        tool = get(tool_map, call.name, nothing)
        if tool === nothing
            result = _tool_error_result("Tool \"$(call.name)\" not found")
            push!(prepared, (call=call, tool=nothing, args=call.arguments, result=result, duration=0))
            continue
        end
        args = call.arguments
        if call.arguments_error !== nothing
            result = _tool_error_result(call.arguments_error)
            push!(prepared, (call=call, tool=tool, args=args, result=result, duration=0))
            continue
        end
        if tool.prepare_arguments !== nothing
            try
                prepared_args = tool.prepare_arguments(args)
                prepared_args !== nothing && (args = prepared_args)
            catch err
                result = _tool_error_result(sprint(showerror, err))
                push!(prepared, (call=call, tool=tool, args=args, result=result, duration=0))
                continue
            end
        end
        try
            PiAISDK.validate_arguments(tool.name, tool.parameters, args)
        catch err
            result = _tool_error_result(sprint(showerror, err))
            push!(prepared, (call=call, tool=tool, args=args, result=result, duration=0))
            continue
        end
        if config.before_tool_call !== nothing
            decision = config.before_tool_call((tool=tool, args=args, call=call), signal)
            if decision !== nothing && get(decision, :block, false)
                reason = get(decision, :reason, nothing)
                result = _tool_error_result(something(reason, "Tool call blocked"))
                push!(prepared, (call=call, tool=tool, args=args, result=result, duration=0))
                continue
            end
        end
        push!(prepared, (call=call, tool=tool, args=args, result=nothing, duration=0))
    end

    sequential = config.tool_execution == :sequential ||
                 any(p -> p.tool !== nothing && p.tool.execution_mode == :sequential, prepared)

    function run_one!(entry, index)
        entry.result !== nothing && return entry
        tool = entry.tool
        emit(ToolExecutionStartEvent(entry.call.id, entry.call.name, entry.args))
        start_ns = time_ns()
        on_update = partial -> emit(ToolExecutionUpdateEvent(entry.call.id, entry.call.name,
                                                             entry.args, partial))
        result = try
            r = tool.execute(entry.call.id, entry.args, signal, on_update)
            r isa ToolResult ? r : ToolResult(r)
        catch err
            if err isa InterruptException && signal !== nothing && PiAISDK.is_aborted(signal)
                _tool_error_result("Tool aborted")
            else
                _tool_error_result(sprint(showerror, err))
            end
        end
        if config.after_tool_call !== nothing
            override = config.after_tool_call((tool=tool, args=entry.args, call=entry.call,
                                               result=result), signal)
            if override !== nothing
                content = get(override, :content, result.content)
                structured = get(override, :structured_content,
                                 haskey(override, :content) ? nothing : result.structured_content)
                result = ToolResult(content;
                    details=get(override, :details, result.details),
                    structured_content=structured,
                    is_error=get(override, :is_error, result.is_error),
                    usage=get(override, :usage, result.usage),
                    terminate=get(override, :terminate, result.terminate))
            end
        end
        duration = Int(round((time_ns() - start_ns) / 1_000_000))
        emit(ToolExecutionEndEvent(entry.call.id, entry.call.name, entry.args,
                                   result, result.is_error, duration))
        return (call=entry.call, tool=entry.tool, args=entry.args, result=result, duration=duration)
    end

    if sequential
        for i in eachindex(prepared)
            prepared[i] = run_one!(prepared[i], i)
        end
    else
        tasks = Tuple{Int,Task}[]
        for (i, entry) in enumerate(prepared)
            if entry.result !== nothing
                emit(ToolExecutionStartEvent(entry.call.id, entry.call.name, entry.args))
                r = entry.result
                emit(ToolExecutionEndEvent(entry.call.id, entry.call.name, entry.args, r, r.is_error, 0))
                continue
            end
            push!(tasks, (i, @async run_one!(entry, i)))
        end
        for (i, t) in tasks
            try
                prepared[i] = fetch(t)
            catch err
                @error "tool task failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
    end

    for entry in prepared
        entry.result === nothing && continue
        if entry.tool === nothing || (entry.tool !== nothing && entry.result.is_error)
            emit(ToolExecutionStartEvent(entry.call.id, entry.call.name, entry.args))
            emit(ToolExecutionEndEvent(entry.call.id, entry.call.name, entry.args,
                                       entry.result, entry.result.is_error, 0))
        end
        msg = _tool_result_message(entry.call, entry.result, entry.duration)
        push!(result_messages, msg)
        emit(MessageStartEvent(msg))
        emit(MessageEndEvent(msg))
        all_terminate &= entry.result.terminate
    end

    return result_messages, all_terminate
end

function _apply_prepare_next_turn(config, message, tool_results)
    if config.prepare_next_turn !== nothing
        prepared = config.prepare_next_turn((message=message, tool_results=tool_results), nothing)
        if prepared !== nothing && hasproperty(prepared, :messages) && prepared.messages !== nothing
            return PiAISDK.AbstractMessage[prepared.messages...]
        end
    end
    return PiAISDK.AbstractMessage[]
end

"""
    run_loop(context, new_messages, config, signal, emit, stream_fn=config.stream_fn)

Run the agent loop over `context`.

`new_messages` are appended to the conversation and emitted before the first
turn. Each turn streams one assistant message, executes its tool calls when
present, and emits turn, message and tool events through `emit`. The loop stops
when the assistant produces no tool calls, a tool result requests termination,
the assistant reports `"error"`/`"aborted"`, or `config.finish_turn` returns
`:end`. Steering and follow-up messages from `config` are drained between
turns.

Returns the messages produced by the run.

# Arguments
- `context::AgentContext`: conversation state; mutated in place.
- `new_messages`: messages to append before the loop starts.
- `config::AgentLoopConfig`: model, hooks and tool execution mode.
- `signal`: abort token checked by providers and tools (may be `nothing`).
- `emit`: callback invoked with every [`AbstractAgentEvent`](@ref).
- `stream_fn`: streaming function; assigned to `config.stream_fn`.
"""
function run_loop(context::AgentContext, new_messages, config::AgentLoopConfig,
                  signal, emit, stream_fn=config.stream_fn)
    _validate_tool_execution(config)
    config.stream_fn = stream_fn
    messages = context.messages
    produced = PiAISDK.AbstractMessage[]
    emit(AgentStartEvent())
    try
        for m in new_messages
            push!(messages, m)
            push!(produced, m)
            emit(MessageStartEvent(m))
            emit(MessageEndEvent(m))
        end
        has_more = true
        explicit_continuation = false
        while true
            emit(TurnStartEvent())
            assistant = stream_assistant_response!(context, produced, config, signal, emit)
            if assistant.stop_reason in ("error", "aborted")
                emit(TurnEndEvent(assistant, PiAISDK.ToolResultMessage[]))
                return produced
            end
            tool_results, all_terminate = PiAISDK.ToolResultMessage[], false
            has_tool_calls = any(c -> c isa PiAISDK.ToolCall, assistant.content)
            if assistant.stop_reason == "toolUse" ||
               (assistant.stop_reason == "length" && has_tool_calls)
                tool_results, all_terminate = execute_tool_calls(context, assistant, config, signal, emit)
                append!(produced, tool_results)
            end
            emit(TurnEndEvent(assistant, tool_results))
            if all_terminate && !isempty(tool_results)
                return produced
            end
            has_more = assistant.stop_reason == "toolUse" && !isempty(tool_results)
            steering = config.get_steering_messages === nothing ? PiAISDK.AbstractMessage[] :
                       PiAISDK.AbstractMessage[config.get_steering_messages()...]
            if !isempty(steering)
                for m in steering
                    push!(messages, m)
                    push!(produced, m)
                    emit(MessageStartEvent(m))
                    emit(MessageEndEvent(m))
                end
                explicit_continuation = false
                continue
            end
            if has_more
                explicit_continuation = false
                continue
            end
            follow_up = config.get_follow_up_messages === nothing ? PiAISDK.AbstractMessage[] :
                        PiAISDK.AbstractMessage[config.get_follow_up_messages()...]
            if !isempty(follow_up)
                for m in follow_up
                    push!(messages, m)
                    push!(produced, m)
                    emit(MessageStartEvent(m))
                    emit(MessageEndEvent(m))
                end
                explicit_continuation = false
                continue
            end
            if config.finish_turn !== nothing
                decision = config.finish_turn((message=assistant, tool_results=tool_results), signal)
                if decision === :end
                    return produced
                elseif decision === :continue
                    if isempty(tool_results) && isempty(steering) && isempty(follow_up)
                        explicit_continuation = true
                        continue
                    end
                end
            end
            if explicit_continuation
                explicit_continuation = false
                continue
            end
            break
        end
        return produced
    finally
        emit(AgentEndEvent(produced))
    end
end

"""
    run_agent_loop(prompts, context, config, signal, emit, stream_fn=config.stream_fn)

Run one agent loop seeded with `prompts` and return the messages produced by
the run. Equivalent to [`run_loop`](@ref) with `prompts` as the new messages.

# Example
```julia
using PiAISDK, PiAgentCore
set_responses!([faux_text("Hello")])
produced = run_agent_loop(AbstractMessage[], AgentContext(AbstractMessage[]), AgentLoopConfig(model=find_model("faux/faux-1")), nothing, _ -> nothing)
```
"""
run_agent_loop(prompts, context::AgentContext, config::AgentLoopConfig, signal, emit, stream_fn=config.stream_fn) =
    run_loop(context, PiAISDK.AbstractMessage[prompts...], config, signal, emit, stream_fn)

"""
    run_agent_loop_continue(context, config, signal, emit, stream_fn=config.stream_fn)

Resume the agent loop on an existing context without appending new messages.
Equivalent to [`run_loop`](@ref) with an empty `new_messages`.
"""
run_agent_loop_continue(context::AgentContext, config::AgentLoopConfig, signal, emit, stream_fn=config.stream_fn) =
    run_loop(context, PiAISDK.AbstractMessage[], config, signal, emit, stream_fn)

"""
    declare_tool_changes(context::AgentContext, pending)

Upstream compatibility stub for declaring pending tool changes to the loop.

Returns `context` unchanged; `pending` is not applied.
"""
function declare_tool_changes(context::AgentContext, pending)
    return context
end
