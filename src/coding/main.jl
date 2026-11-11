const LOG_TAG = "coding_main"

function _select_session(opts::CLIOptions, cwd::String, settings::Dict{String,Any})
    dir = opts.session_dir === nothing ? configured_session_dir(settings) : opts.session_dir
    if opts.no_session
        return create_session(cwd; dir=dir, in_memory=true)
    end
    if opts.session !== nothing
        path = find_session(opts.session; dir=dir)
        return load_session(path)
    end
    if opts.continue_session
        sessions = list_sessions(cwd; dir=dir)
        isempty(sessions) && return create_session(cwd; dir=dir)
        return load_session(sessions[1])
    end
    if opts.resume
        sessions = list_sessions(cwd; dir=dir)
        if isempty(sessions)
            return create_session(cwd; dir=dir)
        end
        if is_tty(stdin)
            for (i, path) in enumerate(sessions)
                println("$(i). $(basename(path))")
            end
            line = readline("Session number: ")
            idx = tryparse(Int, strip(line))
            idx === nothing || idx < 1 || idx > length(sessions) || return load_session(sessions[idx])
        end
        return load_session(sessions[1])
    end
    return create_session(cwd; dir=dir, id=opts.session_id, name=opts.name)
end

function _resolve_model(opts::CLIOptions, settings::Dict{String,Any})
    faux_path = get(ENV, "PIKIT_FAUX_RESPONSES", nothing)
    if faux_path !== nothing
        steps = load_faux_responses(faux_path)
        register_faux_provider!(responses=steps)
    end
    pattern = opts.model
    if pattern === nothing && faux_path !== nothing
        pattern = "faux/faux-1"
    end
    if pattern === nothing
        p = opts.provider === nothing ? get(settings, "provider", nothing) : opts.provider
        m = get(settings, "model", nothing)
        if p !== nothing && m !== nothing
            pattern = occursin('/', String(m)) ? String(m) : "$(p)/$(m)"
        elseif m !== nothing
            pattern = String(m)
        end
    elseif opts.provider !== nothing && !occursin('/', pattern)
        pattern = "$(opts.provider)/$(pattern)"
    end
    pattern === nothing && throw(CLIError("No model selected. Use --model or configure ~/.pikit/models.json."))
    model = find_model(pattern)
    model === nothing && throw(CLIError("Model not found: $(pattern)"))
    return model
end

function _session_model_change(sm)
    value = nothing
    for e in sm.entries
        e isa ModelChangeEntry && !isempty(e.model_id) && (value = "$(e.provider)/$(e.model_id)")
    end
    return value
end

function _session_thinking_change(sm)
    value = nothing
    for e in sm.entries
        e isa ThinkingLevelChangeEntry && (value = e.thinking_level)
    end
    return value
end

function _resolve_thinking(opts::CLIOptions, model, settings::Dict{String,Any}; resume_level=nothing)
    level = something(opts.thinking, resume_level, get(settings, "thinking", nothing), "off")
    if !model.reasoning && level != "off"
        println(stderr, "Warning: model $(model.provider)/$(model.id) does not support reasoning; using off.")
        level = "off"
    end
    return String(level)
end

function build_runtime(opts::CLIOptions)
    cwd = pwd()
    trusted = opts.approve === true
    settings = load_settings(cwd; trusted=trusted, cli=Dict{String,Any}())
    sm = _select_session(opts, cwd, settings)
    resume_model = (opts.model === nothing && opts.provider === nothing) ? _session_model_change(sm) : nothing
    if resume_model !== nothing
        model = find_model(resume_model)
        model === nothing && (model = _resolve_model(opts, settings))
    else
        model = _resolve_model(opts, settings)
    end
    resume_thinking = opts.thinking === nothing ? _session_thinking_change(sm) : nothing
    thinking = _resolve_thinking(opts, model, settings; resume_level=resume_thinking)
    tool_names = resolve_tool_names(opts, get(settings, "defaultTools", DEFAULT_TOOL_NAMES))
    if model.provider == "faux" && isempty(tool_names)
        # faux end-to-end tests don't need tools
    end
    session = create_agent_session(
        cwd=cwd, model=model, session_manager=sm, settings=settings,
        tools_names=tool_names, thinking_level=thinking,
        system_prompt=opts.system_prompt,
        append_system_prompt=isempty(opts.append_system_prompt) ? nothing : join(opts.append_system_prompt, "\n\n"),
        no_context_files=opts.no_context_files, trusted=trusted,
        agent_dir=default_agent_dir(), api_key=opts.api_key)
    if opts.fork !== nothing
        forked = fork_session(sm, opts.fork, cwd)
        close!(sm)
        session.session = forked
        session.agent.session_id = forked.header.id
        _rebuild_agent_messages!(session)
    end
    return session
end

function main(args=ARGS)
    opts = try
        parse_cli(args)
    catch err
        if err isa CLIError
            println(stderr, err.message)
            return err.code
        end
        rethrow()
    end
    if opts.help
        print(HELP_TEXT)
        return 0
    elseif opts.version
        println("pikit ", pkgversion(parentmodule(@__MODULE__)))
        return 0
    elseif opts.list_models !== nothing
        print(list_models_text(opts.list_models))
        return 0
    end
    session = nothing
    try
        session = build_runtime(opts)
        prompt_text = initial_prompt(opts)
        if opts.mode != "rpc" && !is_tty(stdin)
            stdin_text = read(stdin, String)
            if !isempty(stdin_text)
                prompt_text = isempty(prompt_text) ? stdin_text : stdin_text * "\n" * prompt_text
            end
        end
        if opts.mode == "rpc"
            return run_rpc_mode(session)
        elseif opts.mode == "json"
            return run_json_mode(session, prompt_text; images=opts.images)
        elseif opts.mode == "repl"
            return run_repl_mode(session; initial_prompt=prompt_text, images=opts.images)
        else
            return run_print_mode(session, prompt_text; images=opts.images)
        end
    catch err
        if err isa CLIError
            println(stderr, err.message)
            return err.code
        elseif err isa InterruptException
            return 130
        end
        println(stderr, "Error: ", sprint(showerror, err))
        return 1
    finally
        session === nothing || close!(session)
    end
end
