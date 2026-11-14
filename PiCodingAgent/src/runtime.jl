const LOG_TAG = "coding_runtime"

"""
    AgentSession

High-level coding agent runtime wrapping a `PiAgentCore.Agent` and a
[`SessionManager`](@ref). It owns the tool set, model, reasoning level, retry
policy, and event listeners.

# Fields
- `agent::PiAgentCore.Agent`: underlying agent.
- `session::SessionManager`: persistent conversation log.
- `cwd::String`: working directory.
- `model::PiAISDK.Model`: active model.
- `thinking_level::String`: reasoning level.
- `tools::Vector{PiAgentCore.Tool}`: registered tools.
- `auto_compaction::Bool`: compact automatically near the context limit.
- `retry::RetryPolicy`: retry policy.
- `settings::Dict{String,Any}`: merged settings.
- `listeners::Vector{Function}`: event subscribers.
- `listener_lock::ReentrantLock`: guards `listeners`.
- `last_assistant`: most recent assistant message of the current run.
- `retry_attempt::Int`: retries performed in the current run.
- `overflow_recovered::Bool`: whether the run already recovered from overflow.
- `is_compacting::Bool`: whether compaction is in progress.
- `abort_requested::Bool`: whether an abort was requested.
- `agent_dir::String`: agent data directory.
- `api_key::Union{Nothing,String}`: optional API key override.
"""
mutable struct AgentSession
    agent::PiAgentCore.Agent
    session::SessionManager
    cwd::String
    model::PiAISDK.Model
    thinking_level::String
    tools::Vector{PiAgentCore.Tool}
    auto_compaction::Bool
    retry::RetryPolicy
    settings::Dict{String,Any}
    listeners::Vector{Function}
    listener_lock::ReentrantLock
    last_assistant::Union{Nothing,PiAISDK.AssistantMessage}
    retry_attempt::Int
    overflow_recovered::Bool
    is_compacting::Bool
    abort_requested::Bool
    agent_dir::String
    api_key::Union{Nothing,String}
end

"""
    subscribe(s::AgentSession, f::Function)

Register an event listener that is called with every session event, including
agent events and lifecycle events such as `entry_appended` and `agent_settled`.

# Arguments
- `s::AgentSession`: session to observe.
- `f::Function`: listener receiving one event object.

# Returns
A zero-argument function that removes the listener.
"""
function subscribe(s::AgentSession, f::Function)
    lock(s.listener_lock) do
        push!(s.listeners, f)
    end
    cancelled = Ref(false)
    return function ()
        cancelled[] && return
        cancelled[] = true
        lock(s.listener_lock) do
            idx = findfirst(l -> l === f, s.listeners)
            idx === nothing || deleteat!(s.listeners, idx)
        end
    end
end

function emit_session(s::AgentSession, ev)
    listeners = lock(s.listener_lock) do
        copy(s.listeners)
    end
    for f in listeners
        try
            r = f(ev)
            r isa Task && wait(r)
        catch err
            @error "session listener failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
    end
    return nothing
end

function _system_message_for(s::AgentSession; system_prompt=nothing, append_system_prompt=nothing,
                             no_context_files=false, trusted=false)
    sections = build_system_sections(s.cwd; tools=s.tools, model=s.model,
        system_prompt=system_prompt, append_system_prompt=append_system_prompt,
        no_context_files=no_context_files, trusted=trusted, agent_dir=s.agent_dir)
    cleaned = Pair{String,Union{String,Nothing}}[p for p in sections if p.first != "preamble"]
    sys = PiAISDK.SystemMessage(""; sections=cleaned)
    sys.tools_added = [Dict{String,Any}("name" => t.name, "description" => t.description,
                                        "parameters" => t.parameters) for t in s.tools]
    return sys
end

"""
    sync_agent_context!(s::AgentSession)

Rebuild the agent message list from the session history, adding the system
message when the session does not start with one. Used after swapping or
forking the underlying session.
"""
function sync_agent_context!(s::AgentSession)
    history = build_context(s.session)
    if isempty(history) || !(history[1] isa PiAISDK.SystemMessage)
        sys = _system_message_for(s)
        append_message!(s.session, sys)
        history = PiAISDK.AbstractMessage[sys; history...]
    end
    s.agent.state.messages = history
    return nothing
end

"""
    create_agent_session(; cwd=pwd(), model::PiAISDK.Model, session_manager::SessionManager,
                         settings=Dict{String,Any}(), tools_names=DEFAULT_TOOL_NAMES,
                         thinking_level="off", system_prompt=nothing,
                         append_system_prompt=nothing, no_context_files=false,
                         trusted=false, agent_dir=default_agent_dir(), api_key=nothing)

Build a fully wired [`AgentSession`](@ref): create the tools, restore context
from the session, prepend a system message when needed, and subscribe the
persistence and compaction handler.

# Arguments
- `cwd`: working directory.
- `model`: model to run.
- `session_manager`: persistent session to use.
- `settings`: merged settings (retry, compaction, API keys, shell path).
- `tools_names`: tool names to create.
- `thinking_level`: initial reasoning level.
- `system_prompt`, `append_system_prompt`, `no_context_files`, `trusted`:
  forwarded to system-prompt construction.
- `agent_dir`: agent data directory.
- `api_key`: explicit API key, overriding stored credentials.

# Returns
An [`AgentSession`](@ref).

# Example
```julia
manager = create_session(pwd(); in_memory=true)
session = create_agent_session(; model=model, session_manager=manager)
prompt!(session, "Summarize this repository")
```
"""
function create_agent_session(; cwd::String=pwd(), model::PiAISDK.Model, session_manager::SessionManager,
                              settings::Dict{String,Any}=Dict{String,Any}(),
                              tools_names=DEFAULT_TOOL_NAMES,
                              thinking_level::String="off",
                              system_prompt=nothing, append_system_prompt=nothing,
                              no_context_files::Bool=false, trusted::Bool=false,
                              agent_dir::String=default_agent_dir(),
                              api_key::Union{Nothing,String}=nothing)
    env = get_shell_env(model=model.id, session_id=session_manager.header.id,
                        session_file=session_manager.path, provider=model.provider,
                        reasoning=thinking_level, agent_dir=agent_dir)
    tools = create_tools(cwd; names=tools_names, model=model,
                         shell_path=get(settings, "shellPath", nothing), env=env)
    if api_key === nothing
        keys = get(settings, "apiKeys", nothing)
        if keys isa AbstractDict && haskey(keys, model.provider)
            api_key = String(keys[model.provider])
        end
    end
    retry = retry_policy(settings)
    auto_compaction = Bool(get(settings, "autoCompaction", true))
    session = AgentSession(PiAgentCore.Agent(model=model), session_manager, String(cwd), model,
                           thinking_level, tools, auto_compaction, retry, settings,
                           Function[], ReentrantLock(), nothing, 0, false, false, false,
                           agent_dir, api_key)
    history = build_context(session_manager)
    if isempty(history) || !(history[1] isa PiAISDK.SystemMessage)
        sys = _system_message_for(session; system_prompt=system_prompt,
            append_system_prompt=append_system_prompt, no_context_files=no_context_files,
            trusted=trusted)
        append_message!(session_manager, sys)
        history = PiAISDK.AbstractMessage[sys; history...]
    end
    agent = PiAgentCore.Agent(model=model, tools=tools, messages=history,
        thinking_level=thinking_level, session_id=session_manager.header.id,
        convert_to_llm=coding_convert_to_llm,
        get_api_key=model -> resolve_api_key(model.provider; cli_override=api_key, agent_dir=agent_dir))
    agent.prepare_request = (req, signal) -> (context=PiAISDK.LLMContext(build_context(session_manager)),)
    session.agent = agent
    PiAgentCore.subscribe(agent, ev -> _handle_agent_event!(session, ev))
    return session
end

function _stream_options(s::AgentSession, signal=nothing)
    return PiAISDK.StreamOptions(
        api_key=resolve_api_key(s.model.provider; cli_override=s.api_key, agent_dir=s.agent_dir),
        signal=signal,
        session_id=s.session.header.id,
        reasoning=s.thinking_level,
        cache_retention=get(s.settings, "cacheRetention", "short"),
        max_tokens=get(s.settings, "maxTokens", nothing),
        temperature=get(s.settings, "temperature", nothing),
    )
end

function _persist_message!(s::AgentSession, msg)
    if msg isa PiAISDK.AssistantMessage
        msg.stop_reason in ("error", "aborted", "pending") && return
    end
    entry = append_message!(s.session, msg)
    emit_session(s, (type="entry_appended", entry=entry_to_json(entry)))
    return
end

function _handle_agent_event!(s::AgentSession, ev)
    if ev isa PiAgentCore.MessageEndEvent
        msg = ev.message
        _persist_message!(s, msg)
        if msg isa PiAISDK.AssistantMessage
            s.last_assistant = msg
        end
    elseif ev isa PiAgentCore.TurnEndEvent
        if s.auto_compaction && !s.is_compacting
            messages = build_context(s.session)
            tokens = estimate_context_tokens(messages)
            reserve = Int(get(s.settings, "reserveTokens", 16384))
            if should_compact(tokens, s.model.context_window, reserve)
                try
                    compact!(s; reason="threshold")
                catch err
                    @warn "threshold compaction failed" _group=LOG_TAG exception=(err, catch_backtrace())
                end
            end
        end
    end
    emit_session(s, ev)
    return nothing
end

"""
    prompt!(s::AgentSession, text::AbstractString; images=PiAISDK.ImageContent[])
    prompt!(s::AgentSession, messages::AbstractVector{<:PiAISDK.AbstractMessage})

Send a new user turn to the agent and run it to completion, including
automatic retry, context-overflow recovery, and threshold compaction.

# Arguments
- `s::AgentSession`: running session.
- `text::AbstractString`: user text.
- `images`: image attachments to include with the text.
- `messages`: pre-built messages to send instead of text.

# Returns
`nothing`; observe progress through [`subscribe`](@ref PiCodingAgent.subscribe).

# Example
```julia
prompt!(session, "What does src/PiCodingAgent.jl export?")
```
"""
function prompt!(s::AgentSession, text::AbstractString; images=PiAISDK.ImageContent[])
    s.agent.state.model = s.model
    s.agent.state.thinking_level = s.thinking_level
    s.abort_requested = false
    s.retry_attempt = 0
    s.overflow_recovered = false
    s.last_assistant = nothing
    PiAgentCore.prompt!(s.agent, text; images=images)
    return finish_run!(s)
end

function prompt!(s::AgentSession, messages::AbstractVector{<:PiAISDK.AbstractMessage})
    s.abort_requested = false
    s.retry_attempt = 0
    s.overflow_recovered = false
    s.last_assistant = nothing
    PiAgentCore.prompt!(s.agent, messages)
    return finish_run!(s)
end

"""
    continue!(s::AgentSession)

Resume the agent from its current messages, for example after appending tool
results. Runs the same post-processing as [`prompt!`](@ref PiCodingAgent.prompt!).

# Returns
`nothing`.
"""
function continue!(s::AgentSession)
    s.abort_requested = false
    s.retry_attempt = 0
    s.overflow_recovered = false
    s.last_assistant = nothing
    PiAgentCore.continue!(s.agent)
    return finish_run!(s)
end

function _drop_last_error_assistant!(s::AgentSession)
    msgs = s.agent.state.messages
    while !isempty(msgs)
        last = msgs[end]
        if last isa PiAISDK.AssistantMessage && last.stop_reason in ("error", "aborted")
            pop!(msgs)
        else
            break
        end
    end
    return nothing
end

function finish_run!(s::AgentSession)
    while true
        last = s.last_assistant
        if last === nothing
            emit_session(s, (type="agent_settled", aborted=s.abort_requested))
            return nothing
        end
        if last.stop_reason == "aborted"
            s.abort_requested = true
            emit_session(s, (type="agent_settled", aborted=true))
            return nothing
        end
        if last.stop_reason != "error"
            emit_session(s, (type="agent_settled", aborted=false))
            return nothing
        end
        overflow = PiAISDK.is_context_overflow(last; context_window=s.model.context_window)
        if overflow && !s.overflow_recovered
            s.overflow_recovered = true
            try
                compact!(s; reason="overflow")
            catch err
                @warn "overflow compaction failed" _group=LOG_TAG exception=(err, catch_backtrace())
                emit_session(s, (type="agent_settled", aborted=false))
                return nothing
            end
            _drop_last_error_assistant!(s)
            s.last_assistant = nothing
            PiAgentCore.continue!(s.agent)
            continue
        end
        if s.retry.enabled && s.retry_attempt < s.retry.max_attempts && PiAISDK.is_retryable_assistant_error(last)
            s.retry_attempt += 1
            delay = retry_delay_ms(s.retry, s.retry_attempt)
            emit_session(s, (type="auto_retry_start", attempt=s.retry_attempt,
                             maxAttempts=s.retry.max_attempts, delayMs=delay,
                             errorMessage=something(last.error_message, "Request failed")))
            PiAISDK.sleep_abortable(delay / 1000, s.agent.signal)
            if s.abort_requested || PiAISDK.is_aborted(s.agent.signal)
                emit_session(s, (type="auto_retry_end", success=false, attempt=s.retry_attempt,
                                 finalError=something(last.error_message, "Request aborted")))
                emit_session(s, (type="agent_settled", aborted=true))
                return nothing
            end
            _drop_last_error_assistant!(s)
            s.last_assistant = nothing
            try
                PiAgentCore.continue!(s.agent)
            catch err
                emit_session(s, (type="auto_retry_end", success=false, attempt=s.retry_attempt,
                                 finalError=sprint(showerror, err)))
                emit_session(s, (type="agent_settled", aborted=false))
                return nothing
            end
            emit_session(s, (type="auto_retry_end", success=true, attempt=s.retry_attempt))
            continue
        end
        emit_session(s, (type="auto_retry_end", success=false, attempt=s.retry_attempt,
                         finalError=something(last.error_message, "Request failed")))
        emit_session(s, (type="agent_settled", aborted=false))
        return nothing
    end
end

"""
    compact!(s::AgentSession; reason="manual", instructions=nothing,
              keep_recent_tokens=nothing, reserve_tokens=nothing)

Compact the session with the current model, reading defaults from the session
settings. `instructions` is accepted for API compatibility and currently
unused.

# Arguments
- `s::AgentSession`: session to compact.
- `reason::String`: label reported in compaction events.
- `keep_recent_tokens`: override for the retained recent tokens.
- `reserve_tokens`: override for the reserved context tokens.

# Returns
The appended [`CompactionEntry`](@ref), or `nothing`.

# Example
```julia
compact!(session)
```
"""
function compact!(s::AgentSession; reason::String="manual", instructions=nothing,
                  keep_recent_tokens=nothing, reserve_tokens=nothing)
    s.is_compacting = true
    try
        opts = _stream_options(s, s.agent.signal)
        keep = something(keep_recent_tokens, get(s.settings, "keepRecentTokens", 20000))
        reserve = something(reserve_tokens, get(s.settings, "reserveTokens", 16384))
        return compact!(s.session, s.model, opts, s.retry; reason=reason,
                        keep_recent_tokens=keep, reserve_tokens=reserve,
                        signal=s.agent.signal, emit=ev -> emit_session(s, ev))
    finally
        s.is_compacting = false
    end
end

"""
    abort!(s::AgentSession)

Request cancellation of the current run. The agent stops at the next safe point
and the run settles with `aborted=true`.

# Returns
`nothing`.
"""
function abort!(s::AgentSession)
    s.abort_requested = true
    PiAgentCore.abort!(s.agent)
    return nothing
end

"""
    steer!(s::AgentSession, text::AbstractString)

Queue a steering message that is injected into the agent while the current turn
runs.

# Arguments
- `s::AgentSession`: running session.
- `text::AbstractString`: steering text.

# Returns
`nothing`.
"""
function steer!(s::AgentSession, text::AbstractString)
    PiAgentCore.steer!(s.agent, text)
    emit_session(s, (type="queue_update", steering=String[m isa PiAISDK.UserMessage ? (m.content isa AbstractString ? m.content : "") : "" for m in s.agent.steering.messages], followUp=String[]))
    return nothing
end

"""
    follow_up!(s::AgentSession, text::AbstractString)

Queue a message that runs after the current turn finishes.

# Arguments
- `s::AgentSession`: running session.
- `text::AbstractString`: follow-up text.

# Returns
`nothing`.
"""
function follow_up!(s::AgentSession, text::AbstractString)
    PiAgentCore.follow_up!(s.agent, text)
    emit_session(s, (type="queue_update", steering=String[], followUp=String[String(text)]))
    return nothing
end

"""
    clear_queues!(s::AgentSession)

Drop all queued steering and follow-up messages.

# Returns
`nothing`.
"""
function clear_queues!(s::AgentSession)
    PiAgentCore.clear_queues!(s.agent)
    emit_session(s, (type="queue_update", steering=String[], followUp=String[]))
    return nothing
end

"""
    set_model!(s::AgentSession, model::PiAISDK.Model)

Switch the active model and record a [`ModelChangeEntry`](@ref) in the session.

# Arguments
- `s::AgentSession`: session to update.
- `model::PiAISDK.Model`: new model.

# Returns
`nothing`.
"""
function set_model!(s::AgentSession, model::PiAISDK.Model)
    s.model = model
    s.agent.state.model = model
    append_entry!(s.session, ModelChangeEntry(new_entry_id(Set{String}(e.id for e in s.session.entries if e.id !== nothing)),
        s.session.leaf_id, now_iso(), model.provider, model.id, Dict{String,Any}()))
    return nothing
end

"""
    set_thinking_level!(s::AgentSession, level::String)

Set the reasoning level and record a [`ThinkingLevelChangeEntry`](@ref).

# Arguments
- `s::AgentSession`: session to update.
- `level::String`: one of `PiAISDK.THINKING_LEVELS`.

# Returns
`nothing`.

# Throws
`ArgumentError` for an unknown level.
"""
function set_thinking_level!(s::AgentSession, level::String)
    level in PiAISDK.THINKING_LEVELS || throw(ArgumentError("Unknown thinking level: $(level)"))
    s.thinking_level = level
    s.agent.state.thinking_level = level
    append_entry!(s.session, ThinkingLevelChangeEntry(new_entry_id(Set{String}(e.id for e in s.session.entries if e.id !== nothing)),
        s.session.leaf_id, now_iso(), level, Dict{String,Any}()))
    emit_session(s, (type="thinking_level_changed", level=level))
    return nothing
end

"""
    set_session_name!(s::AgentSession, name::String)

Set the session display name and record a [`SessionInfoEntry`](@ref).

# Arguments
- `s::AgentSession`: session to update.
- `name::String`: display name.

# Returns
`nothing`.
"""
function set_session_name!(s::AgentSession, name::String)
    append_entry!(s.session, SessionInfoEntry(new_entry_id(Set{String}(e.id for e in s.session.entries if e.id !== nothing)),
        s.session.leaf_id, now_iso(), name, Dict{String,Any}()))
    emit_session(s, (type="session_info_changed", name=name))
    return nothing
end

"""
    get_state(s::AgentSession)

Return a snapshot of session state.

# Returns
`Dict{String,Any}` with `sessionId`, `sessionFile`, `model`, `thinkingLevel`,
`isStreaming`, and `messageCount`.
"""
function get_state(s::AgentSession)
    return Dict{String,Any}(
        "sessionId" => s.session.header.id,
        "sessionFile" => s.session.path,
        "model" => Dict{String,Any}("provider" => s.model.provider, "id" => s.model.id),
        "thinkingLevel" => s.thinking_level,
        "isStreaming" => s.agent.state.is_streaming,
        "messageCount" => length(s.agent.state.messages),
    )
end

"""
    settle!(s::AgentSession)

Wait until the agent is idle and emit a final `agent_settled` event.

# Returns
`nothing`.
"""
function settle!(s::AgentSession)
    PiAgentCore.wait_idle(s.agent)
    emit_session(s, (type="agent_settled", aborted=s.abort_requested))
    return nothing
end

"""
    close!(s::AgentSession)

Abort and wait for the agent, then close the session file. The session is not
usable afterwards.

# Returns
`nothing`.
"""
function close!(s::AgentSession)
    PiAgentCore.abort!(s.agent)
    PiAgentCore.wait_idle(s.agent)
    close!(s.session)
    return nothing
end
