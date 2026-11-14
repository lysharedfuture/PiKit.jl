const LOG_TAG = "agent_core_agent"

"""
    PendingQueue(; mode=:one_at_a_time)

FIFO queue of messages used for steering and follow-up delivery.

`mode` is `:one_at_a_time` (drain one message per call) or `:all` (drain and
clear the whole queue). Prefer [`steer!`](@ref PiAgentCore.steer!) and [`follow_up!`](@ref PiAgentCore.follow_up!) on an
[`Agent`](@ref) over enqueuing directly.

# Fields
- `messages::Vector{PiAISDK.AbstractMessage}`: queued messages.
- `mode::Symbol`: dequeue policy.
"""
mutable struct PendingQueue
    messages::Vector{PiAISDK.AbstractMessage}
    mode::Symbol
end
PendingQueue(; mode=:one_at_a_time) = PendingQueue(PiAISDK.AbstractMessage[], mode)

function enqueue!(q::PendingQueue, msg)
    push!(q.messages, msg)
    return nothing
end

function dequeue!(q::PendingQueue)
    isempty(q.messages) && return PiAISDK.AbstractMessage[]
    if q.mode == :all
        out = copy(q.messages)
        empty!(q.messages)
        return out
    end
    return PiAISDK.AbstractMessage[popfirst!(q.messages)]
end

function clear!(q::PendingQueue)
    empty!(q.messages)
    return nothing
end

"""
    AgentState

Observable state of an [`Agent`](@ref).

# Fields
- `messages::Vector{PiAISDK.AbstractMessage}`: conversation history, mutated by runs.
- `tools::Vector{Tool}`: tools available to the agent.
- `model::PiAISDK.Model`: model used for requests.
- `thinking_level::String`: reasoning level passed to the provider.
- `is_streaming::Bool`: whether a run is in progress.
- `streaming_message::Union{Nothing,PiAISDK.AbstractMessage}`: current partial assistant message.
- `pending_tool_calls::Set{String}`: tool call ids currently executing.
- `error_message::Union{Nothing,String}`: last error reported by the run.
"""
mutable struct AgentState
    messages::Vector{PiAISDK.AbstractMessage}
    tools::Vector{Tool}
    model::PiAISDK.Model
    thinking_level::String
    is_streaming::Bool
    streaming_message::Union{Nothing,PiAISDK.AbstractMessage}
    pending_tool_calls::Set{String}
    error_message::Union{Nothing,String}
end

"""
    Agent(; model=PiAISDK.Model("unconfigured"), tools=Tool[], messages=PiAISDK.AbstractMessage[],
          system_prompt=nothing, sections=nothing, thinking_level="off",
          tool_execution=:parallel, session_id=nothing, convert_to_llm=default_convert_to_llm,
          transform_context=nothing, get_api_key=nothing, finish_turn=nothing,
          prepare_request=nothing, prepare_next_turn=nothing, before_tool_call=nothing,
          after_tool_call=nothing)

Stateful agent that runs [`run_agent_loop`](@ref) in a background task, keeps
its own message history, tool list and listener set, and exposes steering,
follow-up and abort controls.

When the first message is not a `PiAISDK.SystemMessage`, a system message is
created from `system_prompt`, `sections` and the tool declarations. Hook
keywords are forwarded to [`AgentLoopConfig`](@ref) on each run.

Use [`prompt!`](@ref PiAgentCore.prompt!) to start a run, [`subscribe`](@ref PiAgentCore.subscribe) to observe events and
[`wait_idle`](@ref) to block until it finishes.
"""
mutable struct Agent
    state::AgentState
    listeners::Vector{Function}
    steering::PendingQueue
    follow_up::PendingQueue
    active_task::Union{Nothing,Task}
    signal::Union{Nothing,PiAISDK.AbortToken}
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

function Agent(; model=PiAISDK.Model("unconfigured"), tools=Tool[], messages=PiAISDK.AbstractMessage[],
               system_prompt=nothing, sections=nothing, thinking_level="off",
               tool_execution=:parallel, session_id=nothing, convert_to_llm=default_convert_to_llm,
               transform_context=nothing, get_api_key=nothing, finish_turn=nothing,
               prepare_request=nothing, prepare_next_turn=nothing, before_tool_call=nothing,
               after_tool_call=nothing)
    msgs = PiAISDK.AbstractMessage[messages...]
    tool_list = Tool[tools...]
    if isempty(msgs) || !(msgs[1] isa PiAISDK.SystemMessage)
        if system_prompt !== nothing || !isempty(tool_list) || sections !== nothing
            sys = PiAISDK.SystemMessage(something(system_prompt, "");
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

"""
    system_prompt(agent::Agent) -> String

Concatenate the text of every `PiAISDK.SystemMessage` in the agent history,
including its `sections` values, separated by blank lines.
"""
function system_prompt(agent::Agent)
    parts = String[]
    for m in agent.state.messages
        if m isa PiAISDK.SystemMessage
            if m.content isa AbstractString
                isempty(m.content) || push!(parts, m.content)
            else
                for c in m.content
                    c isa PiAISDK.TextContent && push!(parts, c.text)
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

"""
    process_event!(agent::Agent, ev::AbstractAgentEvent)

Apply one agent event to `agent.state`: streaming flags, the current partial
message, pending tool call ids and the last error message.
"""
function process_event!(agent::Agent, ev)
    state = agent.state
    if ev isa AgentStartEvent
        state.is_streaming = true
        state.error_message = nothing
    elseif ev isa MessageStartEvent
        if ev.message isa PiAISDK.AssistantMessage
            state.streaming_message = ev.message
        end
    elseif ev isa MessageUpdateEvent
        state.streaming_message = ev.message
    elseif ev isa MessageEndEvent
        if ev.message isa PiAISDK.AssistantMessage
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

"""
    subscribe(agent::Agent, f::Function) -> Function

Register `f` to receive every [`AbstractAgentEvent`](@ref) emitted by `agent`.

Listeners run while the agent lock is held; a listener returning a `Task` is
awaited, and listener errors are logged and stored in
`agent.state.error_message`.

Returns a zero-argument function that removes the listener.
"""
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
        stream_fn=PiAISDK.stream,
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
    signal = PiAISDK.AbortToken()
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
                msg = PiAISDK.empty_assistant(agent.state.model;
                    stop_reason=PiAISDK.is_aborted(signal) ? "aborted" : "error",
                    error_message=sprint(showerror, err))
                push!(agent.state.messages, msg)
                emit(MessageStartEvent(msg))
                emit(MessageEndEvent(msg))
                emit(TurnEndEvent(msg, PiAISDK.ToolResultMessage[]))
                emit(AgentEndEvent(PiAISDK.AbstractMessage[msg]))
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

"""
    prompt!(agent::Agent, text::AbstractString; images=PiAISDK.ImageContent[])
    prompt!(agent::Agent, msg::PiAISDK.AbstractMessage)
    prompt!(agent::Agent, msgs::AbstractVector{<:PiAISDK.AbstractMessage})

Start an agent run seeded with the given content and block until it finishes.
Events are delivered to subscribers, and prompt and reply messages are appended
to `agent.state.messages`.

Throws `ErrorException("Agent is already processing.")` when a run is active.
"""
function prompt!(agent::Agent, text::AbstractString; images=PiAISDK.ImageContent[])
    _ensure_idle(agent)
    content = if isempty(images)
        String(text)
    else
        PiAISDK.AbstractContent[PiAISDK.TextContent(String(text)), images...]
    end
    msg = PiAISDK.UserMessage(content)
    _run(agent, PiAISDK.AbstractMessage[msg], false)
    return nothing
end

function prompt!(agent::Agent, msg::PiAISDK.AbstractMessage)
    _ensure_idle(agent)
    _run(agent, PiAISDK.AbstractMessage[msg], false)
    return nothing
end

function prompt!(agent::Agent, msgs::AbstractVector{<:PiAISDK.AbstractMessage})
    _ensure_idle(agent)
    _run(agent, PiAISDK.AbstractMessage[msgs...], false)
    return nothing
end

"""
    continue!(agent::Agent)

Continue a finished conversation without a new prompt.

Requires at least one non-system message. When the last message is an assistant
message, queued steering or follow-up messages are used as the new input;
otherwise the loop resumes directly. Throws `ErrorException` when there is
nothing to continue from.
"""
function continue!(agent::Agent)
    _ensure_idle(agent)
    msgs = agent.state.messages
    isempty(msgs) && throw(ErrorException("Cannot continue: no messages"))
    non_system = [m for m in msgs if !(m isa PiAISDK.SystemMessage)]
    isempty(non_system) && throw(ErrorException("Cannot continue: only system messages"))
    last = msgs[end]
    if last isa PiAISDK.AssistantMessage
        queued = dequeue!(agent.steering)
        isempty(queued) && (queued = dequeue!(agent.follow_up))
        isempty(queued) && throw(ErrorException("Cannot continue from message role: assistant"))
        _run(agent, queued, false)
    else
        _run(agent, PiAISDK.AbstractMessage[], true)
    end
    return nothing
end

"""
    steer!(agent::Agent, text::AbstractString)
    steer!(agent::Agent, msg::PiAISDK.AbstractMessage)

Queue a steering message that is delivered between turns of a running agent.
"""
function steer!(agent::Agent, text::AbstractString)
    enqueue!(agent.steering, PiAISDK.UserMessage(String(text)))
    return nothing
end
function steer!(agent::Agent, msg::PiAISDK.AbstractMessage)
    enqueue!(agent.steering, msg)
    return nothing
end
"""
    follow_up!(agent::Agent, text::AbstractString)
    follow_up!(agent::Agent, msg::PiAISDK.AbstractMessage)

Queue a follow-up message that is delivered after a turn ends without
requesting more tool calls.
"""
function follow_up!(agent::Agent, text::AbstractString)
    enqueue!(agent.follow_up, PiAISDK.UserMessage(String(text)))
    return nothing
end
function follow_up!(agent::Agent, msg::PiAISDK.AbstractMessage)
    enqueue!(agent.follow_up, msg)
    return nothing
end

"""
    clear_queues!(agent::Agent)

Discard all queued steering and follow-up messages.
"""
function clear_queues!(agent::Agent)
    clear!(agent.steering)
    clear!(agent.follow_up)
    return nothing
end

"""
    peek_queued(agent::Agent) -> NamedTuple

Return copies of the queued messages as `(steering=..., follow_up=...)` without
dequeuing them.
"""
function peek_queued(agent::Agent)
    return (steering=copy(agent.steering.messages), follow_up=copy(agent.follow_up.messages))
end

"""
    abort!(agent::Agent)

Signal the abort token of the active run, if any. The running loop stops after
the current provider or tool step.
"""
function abort!(agent::Agent)
    agent.signal === nothing || PiAISDK.abort!(agent.signal)
    return nothing
end

"""
    wait_idle(agent::Agent)

Block until the agent's active run task finishes. Returns immediately when no
run is active.
"""
function wait_idle(agent::Agent)
    t = agent.active_task
    t === nothing || wait(t)
    return nothing
end

"""
    reset!(agent::Agent)

Reset the agent to its system-message baseline: drop all non-system messages,
clear errors, streaming state and pending tool calls, and empty the steering and
follow-up queues.

Throws `ErrorException("Agent is already processing.")` while a run is active.
"""
function reset!(agent::Agent)
    _ensure_idle(agent)
    baseline = PiAISDK.AbstractMessage[]
    for m in agent.state.messages
        m isa PiAISDK.SystemMessage && push!(baseline, m)
    end
    agent.state.messages = baseline
    agent.state.error_message = nothing
    agent.state.streaming_message = nothing
    empty!(agent.state.pending_tool_calls)
    clear_queues!(agent)
    return nothing
end
