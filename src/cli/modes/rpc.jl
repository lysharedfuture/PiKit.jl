const LOG_TAG = "pikit_cli_modes_rpc"

function _rpc_write(d)
    println(stdout, json_write(d))
    flush(stdout)
    return nothing
end

function _rpc_response(id, command, success; data=nothing, error=nothing)
    d = Dict{String,Any}("id" => id, "type" => "response", "command" => String(command),
                         "success" => success)
    data === nothing || (d["data"] = data)
    error === nothing || (d["error"] = error)
    return d
end

function _rpc_images(raw)
    out = PiAISDK.ImageContent[]
    raw isa AbstractVector || return out
    for item in raw
        item isa AbstractDict || continue
        data = get(item, "data", nothing)
        mime = get(item, "mimeType", "image/png")
        data isa AbstractString && push!(out, PiAISDK.ImageContent(data, mime))
    end
    return out
end

function _replace_session!(s::AgentSession, sm::SessionManager)
    try
        close!(s.session)
    catch err
        @debug "closing replaced session failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    s.session = sm
    s.agent.session_id = sm.header.id
    s.last_assistant = nothing
    sync_agent_context!(s)
    return nothing
end

function _tree_nodes(entries)
    by_parent = Dict{Union{Nothing,String},Vector{AbstractSessionEntry}}()
    for e in entries
        push!(get!(by_parent, e.parent_id, AbstractSessionEntry[]), e)
    end
    function build(parent)
        [Dict{String,Any}("entry" => entry_to_json(e), "children" => build(e.id))
         for e in get(by_parent, parent, AbstractSessionEntry[]) if e.id !== nothing]
    end
    return build(nothing)
end

function _cycle_model(s::AgentSession)
    models = all_models()
    isempty(models) && return s.model
    idx = findfirst(m -> m.provider == s.model.provider && m.id == s.model.id, models)
    next = idx === nothing ? 1 : mod1(idx + 1, length(models))
    return models[next]
end

function _handle_rpc_command(s::AgentSession, d, running::Ref{Union{Nothing,Task}})
    id = get(d, "id", nothing)
    cmd = String(get(d, "type", get(d, "command", "")))
    data = Dict{String,Any}()
    if cmd == "prompt"
        text = String(get(d, "message", get(d, "text", "")))
        images = _rpc_images(get(d, "images", Any[]))
        behavior = get(d, "streamingBehavior", nothing)
        if running[] !== nothing && !istaskdone(running[])
            if behavior == "steer"
                steer!(s, text)
                _rpc_write(_rpc_response(id, cmd, true; data=Dict{String,Any}("disposition" => "queued")))
                return
            elseif behavior == "followUp"
                follow_up!(s, text)
                _rpc_write(_rpc_response(id, cmd, true; data=Dict{String,Any}("disposition" => "queued")))
                return
            end
            _rpc_write(_rpc_response(id, cmd, false; error="Agent is already processing"))
            return
        end
        running[] = @async begin
            try
                prompt!(s, text; images=images)
            catch err
                @error "rpc prompt failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
        _rpc_write(_rpc_response(id, cmd, true; data=Dict{String,Any}("disposition" => "started")))
        return
    elseif cmd == "steer"
        steer!(s, String(get(d, "message", get(d, "text", ""))))
        data["disposition"] = "queued"
    elseif cmd == "follow_up"
        follow_up!(s, String(get(d, "message", get(d, "text", ""))))
        data["disposition"] = "queued"
    elseif cmd == "abort"
        abort!(s)
    elseif cmd == "clear_queue"
        clear_queues!(s)
    elseif cmd == "get_state"
        data = get_state(s)
    elseif cmd == "get_messages"
        data["messages"] = Any[PiAISDK.message_to_json(m) for m in build_context(s.session)]
    elseif cmd == "set_model"
        pattern = String(get(d, "model", get(d, "id", "")))
        model = find_model(pattern; provider=get(d, "provider", nothing))
        model === nothing && error("Model not found: $(pattern)")
        set_model!(s, model)
        data = Dict{String,Any}("provider" => model.provider, "id" => model.id)
    elseif cmd == "cycle_model"
        model = _cycle_model(s)
        set_model!(s, model)
        data = Dict{String,Any}("provider" => model.provider, "id" => model.id)
    elseif cmd == "get_available_models"
        data["models"] = Any[Dict{String,Any}("provider" => m.provider, "id" => m.id, "name" => m.name) for m in all_models()]
    elseif cmd == "set_thinking_level"
        set_thinking_level!(s, String(get(d, "level", "off")))
        data["level"] = s.thinking_level
    elseif cmd == "cycle_thinking_level"
        idx = findfirst(==(s.thinking_level), PiAISDK.THINKING_LEVELS)
        level = PiAISDK.THINKING_LEVELS[mod1((idx === nothing ? 1 : idx) + 1, length(PiAISDK.THINKING_LEVELS))]
        set_thinking_level!(s, level)
        data["level"] = level
    elseif cmd == "get_available_thinking_levels"
        data["levels"] = collect(PiAISDK.THINKING_LEVELS)
    elseif cmd == "set_steering_mode"
        s.agent.steering.mode = Symbol(get(d, "mode", "one_at_a_time"))
        data["mode"] = String(s.agent.steering.mode)
    elseif cmd == "set_follow_up_mode"
        s.agent.follow_up.mode = Symbol(get(d, "mode", "one_at_a_time"))
        data["mode"] = String(s.agent.follow_up.mode)
    elseif cmd == "compact"
        compact!(s; reason="manual")
        data["tokensBefore"] = nothing
    elseif cmd == "set_auto_compaction"
        s.auto_compaction = Bool(get(d, "enabled", true))
        data["enabled"] = s.auto_compaction
    elseif cmd == "set_auto_retry"
        enabled = Bool(get(d, "enabled", true))
        s.retry = RetryPolicy(enabled=enabled, max_attempts=s.retry.max_attempts,
                              base_delay_ms=s.retry.base_delay_ms, max_delay_ms=s.retry.max_delay_ms)
        data["enabled"] = enabled
    elseif cmd == "abort_retry"
        abort!(s)
    elseif cmd == "bash"
        command = String(get(d, "command", ""))
        bash_id = get(d, "id", nothing)
        result = default_bash_exec(command, s.cwd; env=get_shell_env(model=s.model.id,
            session_id=s.session.header.id, session_file=s.session.path, agent_dir=s.agent_dir))
        trunc = truncate_tail(result.output)
        bash_id === nothing || _rpc_write(Dict{String,Any}("type" => "bash_execution_update",
            "id" => bash_id, "delta" => trunc.content))
        data["exitCode"] = result.exit_code
        data["output"] = result.output
        data["truncated"] = trunc.truncated
    elseif cmd == "abort_bash"
        data["aborted"] = true
    elseif cmd == "new_session"
        sm = create_session(s.cwd; dir=s.session.path === nothing ? nothing : dirname(s.session.path))
        _replace_session!(s, sm)
        data["sessionId"] = sm.header.id
    elseif cmd == "switch_session"
        path = find_session(String(get(d, "session", get(d, "path", ""))))
        _replace_session!(s, load_session(path))
        data["sessionId"] = s.session.header.id
    elseif cmd == "fork"
        entry = String(get(d, "entryId", get(d, "entry", "")))
        sm = fork_session(s.session, entry, s.cwd)
        _replace_session!(s, sm)
        data["sessionId"] = sm.header.id
    elseif cmd == "clone"
        leaf = s.session.leaf_id
        leaf === nothing && error("Session has no entries to clone")
        sm = fork_session(s.session, leaf, s.cwd)
        _replace_session!(s, sm)
        data["sessionId"] = sm.header.id
    elseif cmd == "get_fork_messages"
        data["messages"] = Any[PiAISDK.message_to_json(e.message) for e in s.session.entries if e isa MessageEntry]
    elseif cmd == "get_session_stats"
        data["sessionId"] = s.session.header.id
        data["messageCount"] = length(s.agent.state.messages)
        data["tokens"] = estimate_context_tokens(build_context(s.session))
    elseif cmd == "get_last_assistant_text"
        last = nothing
        for m in s.agent.state.messages
            m isa PiAISDK.AssistantMessage && (last = m)
        end
        data["text"] = last === nothing ? nothing : _assistant_text(last)
    elseif cmd == "set_session_name"
        set_session_name!(s, String(get(d, "name", "")))
        data["name"] = String(get(d, "name", ""))
    elseif cmd == "get_entries"
        data["entries"] = Any[entry_to_json(e) for e in s.session.entries]
    elseif cmd == "get_tree"
        data["tree"] = _tree_nodes(s.session.entries)
    else
        _rpc_write(_rpc_response(id, cmd, false; error="unsupported command: $(cmd)"))
        return
    end
    _rpc_write(_rpc_response(id, cmd, true; data=data))
    return
end

function run_rpc_mode(s::AgentSession)
    running = Ref{Union{Nothing,Task}}(nothing)
    unsubscribe = subscribe(s, ev -> _rpc_write(session_json_event(s, ev)))
    try
        for line in eachline(stdin)
            isempty(strip(line)) && continue
            d = try
                json_parse(line)
            catch err
                _rpc_write(Dict{String,Any}("type" => "response", "command" => "parse",
                                            "success" => false, "error" => sprint(showerror, err)))
                continue
            end
            d isa AbstractDict || continue
            try
                _handle_rpc_command(s, d, running)
            catch err
                _rpc_write(_rpc_response(get(d, "id", nothing),
                    String(get(d, "type", get(d, "command", ""))), false;
                    error=sprint(showerror, err)))
            end
        end
        return 0
    finally
        unsubscribe()
        abort!(s)
        if running[] !== nothing
            try
                wait(running[])
            catch err
                @debug "RPC running task failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
    end
end
