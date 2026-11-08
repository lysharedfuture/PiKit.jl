const LOG_TAG = "agent_core_agent"

mutable struct PendingQueue
    messages::Vector{AI.AbstractMessage}
    mode::Symbol
end
PendingQueue(; mode=:one_at_a_time) = PendingQueue(AI.AbstractMessage[], mode)

function enqueue!(q::PendingQueue, msg)
    push!(q.messages, msg)
    return nothing
end

function dequeue!(q::PendingQueue)
    isempty(q.messages) && return AI.AbstractMessage[]
    if q.mode == :all
        out = copy(q.messages)
        empty!(q.messages)
        return out
    end
    return AI.AbstractMessage[popfirst!(q.messages)]
end

function clear!(q::PendingQueue)
    empty!(q.messages)
    return nothing
end

mutable struct AgentState
    messages::Vector{AI.AbstractMessage}
    tools::Vector{Tool}
    model::AI.Model
    thinking_level::String
    is_streaming::Bool
    streaming_message::Union{Nothing,AI.AbstractMessage}
    pending_tool_calls::Set{String}
    error_message::Union{Nothing,String}
end

mutable struct Agent
    state::AgentState
    listeners::Vector{Function}
    steering::PendingQueue
    follow_up::PendingQueue
    active_task::Union{Nothing,Task}
    signal::Union{Nothing,AI.AbortToken}
    tool_execution::Symbol
    session_id::Union{Nothing,String}
    convert_to_llm::Function
    transform_context::Union{Nothing,Function}
    get_api_key::Union{Nothing,Function}
    finish_turn::Union{Nothing,Function}
    prepare_request::Union{Nothing,Function}
    prepare_next_turn::Union{Nothing,Function}
    before_tool_call::Union{Nothing,Function}
    after_tool_call::Union{Nothing,Function}
    lock::ReentrantLock
end

function Agent(; model=AI.Model("unconfigured"), tools=Tool[], messages=AI.AbstractMessage[],
               system_prompt=nothing, sections=nothing, thinking_level="off",
               tool_execution=:parallel, session_id=nothing, convert_to_llm=default_convert_to_llm,
               transform_context=nothing, get_api_key=nothing, finish_turn=nothing,
               prepare_request=nothing, prepare_next_turn=nothing, before_tool_call=nothing,
               after_tool_call=nothing)
    msgs = AI.AbstractMessage[messages...]
    tool_list = Tool[tools...]
    if isempty(msgs) || !(msgs[1] isa AI.SystemMessage)
        if system_prompt !== nothing || !isempty(tool_list) || sections !== nothing
            sys = AI.SystemMessage(something(system_prompt, "");
                sections=sections,
                tools_added=[Dict{String,Any}("name" => t.name, "description" => t.description,
                                              "parameters" => t.parameters) for t in tool_list])
            pushfirst!(msgs, sys)
        end
    end
    state = AgentState(msgs, tool_list, model, thinking_level, false, nothing,
                       Set{String}(), nothing)
    return Agent(state, Function[], PendingQueue(), PendingQueue(), nothing, nothing,
                 tool_execution, session_id, convert_to_llm, transform_context,
                 get_api_key, finish_turn, prepare_request, prepare_next_turn,
                 before_tool_call, after_tool_call, ReentrantLock())
end

function system_prompt(agent::Agent)
    parts = String[]
    for m in agent.state.messages
        if m isa AI.SystemMessage
            if m.content isa AbstractString
                isempty(m.content) || push!(parts, m.content)
            else
                for c in m.content
                    c isa AI.TextContent && push!(parts, c.text)
                end
            end
            if m.sections !== nothing
                for (_, v) in m.sections
                    v === nothing || push!(parts, v)
                end
            end
        end
    end
    return join(parts, "\n\n")
end

function _current_context(agent::Agent)
    return AgentContext(agent.state.messages, agent.state.tools)
end

function _emit(agent::Agent, ev)
    lock(agent.lock) do
        process_event!(agent, ev)
        for listener in agent.listeners
            try
                result = listener(ev)
                result isa Task && wait(result)
            catch err
                @error "agent listener failed" _group=LOG_TAG exception=(err, catch_backtrace())
                agent.state.error_message = sprint(showerror, err)
            end
        end
    end
    return nothing
end

function process_event!(agent::Agent, ev)
    state = agent.state
    if ev isa AgentStartEvent
        state.is_streaming = true
        state.error_message = nothing
    elseif ev isa MessageStartEvent
        if ev.message isa AI.AssistantMessage
            state.streaming_message = ev.message
        end
    elseif ev isa MessageUpdateEvent
        state.streaming_message = ev.message
    elseif ev isa MessageEndEvent
        if ev.message isa AI.AssistantMessage
            state.streaming_message = nothing
            if ev.message.stop_reason == "error" || ev.message.stop_reason == "aborted"
                state.error_message = something(ev.message.error_message, "Request $(ev.message.stop_reason)")
            end
        end
    elseif ev isa ToolExecutionStartEvent
        push!(state.pending_tool_calls, ev.tool_call_id)
    elseif ev isa ToolExecutionEndEvent
        delete!(state.pending_tool_calls, ev.tool_call_id)
    elseif ev isa AgentEndEvent
        state.is_streaming = false
    end
    return nothing
end

function subscribe(agent::Agent, f::Function)
    lock(agent.lock) do
        push!(agent.listeners, f)
    end
    cancelled = Ref(false)
    return function ()
        cancelled[] && return
        cancelled[] = true
        lock(agent.lock) do
            idx = findfirst(l -> l === f, agent.listeners)
            idx === nothing || deleteat!(agent.listeners, idx)
        end
    end
end

function _build_config(agent::Agent)
    return AgentLoopConfig(
        model=agent.state.model,
        stream_fn=AI.stream,
        convert_to_llm=agent.convert_to_llm,
        transform_context=agent.transform_context,
        get_api_key=agent.get_api_key,
        finish_turn=agent.finish_turn,
        prepare_request=agent.prepare_request,
        prepare_next_turn=agent.prepare_next_turn,
        get_steering_messages=() -> dequeue!(agent.steering),
        get_follow_up_messages=() -> dequeue!(agent.follow_up),
        before_tool_call=agent.before_tool_call,
        after_tool_call=agent.after_tool_call,
        tool_execution=agent.tool_execution,
        reasoning=agent.state.thinking_level,
        session_id=agent.session_id,
    )
end

function _run(agent::Agent, prompts, continuation::Bool)
    signal = AI.AbortToken()
    agent.signal = signal
    agent.state.is_streaming = true
    ended = Ref(false)
    emit = ev -> begin
        ev isa AgentEndEvent && (ended[] = true)
        _emit(agent, ev)
    end
    task = @async begin
        agent.active_task = current_task()
        try
            config = _build_config(agent)
            context = _current_context(agent)
            if continuation
                run_agent_loop_continue(context, config, signal, emit)
            else
                run_agent_loop(prompts, context, config, signal, emit)
            end
        catch err
            @error "agent run failed" _group=LOG_TAG exception=(err, catch_backtrace())
            if !ended[]
                msg = AI.empty_assistant(agent.state.model;
                    stop_reason=AI.is_aborted(signal) ? "aborted" : "error",
                    error_message=sprint(showerror, err))
                push!(agent.state.messages, msg)
                emit(MessageStartEvent(msg))
                emit(MessageEndEvent(msg))
                emit(TurnEndEvent(msg, AI.ToolResultMessage[]))
                emit(AgentEndEvent(AI.AbstractMessage[msg]))
            end
        finally
            agent.state.is_streaming = false
            agent.active_task = nothing
        end
    end
    wait(task)
    return nothing
end

function _ensure_idle(agent::Agent)
    if agent.state.is_streaming || agent.active_task !== nothing
        throw(ErrorException("Agent is already processing."))
    end
end

function prompt!(agent::Agent, text::AbstractString; images=AI.ImageContent[])
    _ensure_idle(agent)
    content = if isempty(images)
        String(text)
    else
        AI.AbstractContent[AI.TextContent(String(text)), images...]
    end
    msg = AI.UserMessage(content)
    _run(agent, AI.AbstractMessage[msg], false)
    return nothing
end

function prompt!(agent::Agent, msg::AI.AbstractMessage)
    _ensure_idle(agent)
    _run(agent, AI.AbstractMessage[msg], false)
    return nothing
end

function prompt!(agent::Agent, msgs::AbstractVector{<:AI.AbstractMessage})
    _ensure_idle(agent)
    _run(agent, AI.AbstractMessage[msgs...], false)
    return nothing
end

function continue!(agent::Agent)
    _ensure_idle(agent)
    msgs = agent.state.messages
    isempty(msgs) && throw(ErrorException("Cannot continue: no messages"))
    non_system = [m for m in msgs if !(m isa AI.SystemMessage)]
    isempty(non_system) && throw(ErrorException("Cannot continue: only system messages"))
    last = msgs[end]
    if last isa AI.AssistantMessage
        queued = dequeue!(agent.steering)
        isempty(queued) && (queued = dequeue!(agent.follow_up))
        isempty(queued) && throw(ErrorException("Cannot continue from message role: assistant"))
        _run(agent, queued, false)
    else
        _run(agent, AI.AbstractMessage[], true)
    end
    return nothing
end

function steer!(agent::Agent, text::AbstractString)
    enqueue!(agent.steering, AI.UserMessage(String(text)))
    return nothing
end
function steer!(agent::Agent, msg::AI.AbstractMessage)
    enqueue!(agent.steering, msg)
    return nothing
end
function follow_up!(agent::Agent, text::AbstractString)
    enqueue!(agent.follow_up, AI.UserMessage(String(text)))
    return nothing
end
function follow_up!(agent::Agent, msg::AI.AbstractMessage)
    enqueue!(agent.follow_up, msg)
    return nothing
end

function clear_queues!(agent::Agent)
    clear!(agent.steering)
    clear!(agent.follow_up)
    return nothing
end

function peek_queued(agent::Agent)
    return (steering=copy(agent.steering.messages), follow_up=copy(agent.follow_up.messages))
end

function abort!(agent::Agent)
    agent.signal === nothing || AI.abort!(agent.signal)
    return nothing
end

function wait_idle(agent::Agent)
    t = agent.active_task
    t === nothing || wait(t)
    return nothing
end

function reset!(agent::Agent)
    _ensure_idle(agent)
    baseline = AI.AbstractMessage[]
    for m in agent.state.messages
        m isa AI.SystemMessage && push!(baseline, m)
    end
    agent.state.messages = baseline
    agent.state.error_message = nothing
    agent.state.streaming_message = nothing
    empty!(agent.state.pending_tool_calls)
    clear_queues!(agent)
    return nothing
end
