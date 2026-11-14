const LOG_TAG = "pikit_cli_modes_repl"

function _repl_print_stream(ev)
    if ev isa PiAgentCore.MessageUpdateEvent
        inner = ev.assistant_message_event
        if inner isa PiAISDK.TextDeltaEvent
            print(stdout, inner.delta)
            flush(stdout)
        elseif inner isa PiAISDK.ThinkingDeltaEvent
            if is_tty(stdout)
                print(stdout, "\e[2m", inner.delta, "\e[0m")
            else
                print(stdout, inner.delta)
            end
            flush(stdout)
        end
    elseif ev isa PiAgentCore.ToolExecutionStartEvent
        args = json_write(ev.args)
        length(args) > 120 && (args = first(args, 120) * "…")
        println(stdout, "\n[tool] $(ev.tool_name) $(args)")
    elseif ev isa PiAgentCore.ToolExecutionEndEvent
        status = ev.is_error ? "error" : "ok"
        println(stdout, "[tool] $(ev.tool_name) $(status) $(ev.duration_ms)ms")
    elseif ev isa PiAgentCore.MessageEndEvent && ev.message isa PiAISDK.AssistantMessage
        println(stdout)
    end
    return nothing
end

function _repl_help()
    println("""Commands:
  /help              show this help
  /new               start a new session
  /resume            choose a previous session
  /model <id>        switch model
  /thinking <level>  switch thinking level
  /compact [text]    compact the session
  /session           show session information
  /tools             list active tools
  /quit              exit""")
end

function _repl_new_session!(s::AgentSession)
    sm = create_session(s.cwd; dir=s.session.path === nothing ? nothing : dirname(s.session.path))
    _replace_session!(s, sm)
    println("Started session $(sm.header.id)")
end

function _repl_resume!(s::AgentSession)
    sessions = list_sessions(s.cwd; dir=s.session.path === nothing ? nothing : dirname(s.session.path))
    isempty(sessions) && return println("No sessions found")
    for (i, path) in enumerate(sessions)
        println("$(i). $(basename(path))")
    end
    line = readline("Session number: ")
    idx = tryparse(Int, strip(line))
    (idx === nothing || idx < 1 || idx > length(sessions)) && return println("Invalid selection")
    _replace_session!(s, load_session(sessions[idx]))
    println("Resumed $(basename(sessions[idx]))")
end

"""
    run_repl_mode(s::AgentSession; initial_prompt="", images=ImageContent[])

Line-oriented REPL. Streams assistant output, accepts slash commands
(`/help`, `/model`, `/session`, …), and exits on EOF or Ctrl-D. An
`initial_prompt` is sent before the first prompt is read.
"""
function run_repl_mode(s::AgentSession; initial_prompt::String="", images=PiAISDK.ImageContent[])
    unsubscribe = subscribe(s, _repl_print_stream)
    try
        if !isempty(initial_prompt) || !isempty(images)
            try
                prompt!(s, initial_prompt; images=images)
            catch err
                err isa InterruptException ? abort!(s) : @error "repl prompt failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
        while true
            line = try
                readline("pikit> ")
            catch err
                err isa InterruptException && continue
                break
            end
            isempty(strip(line)) && continue
            if startswith(line, "/")
                parts = split(strip(line), ' '; limit=2)
                cmd = parts[1]
                arg = length(parts) > 1 ? parts[2] : ""
                if cmd == "/quit" || cmd == "/exit"
                    break
                elseif cmd == "/help"
                    _repl_help()
                elseif cmd == "/new"
                    _repl_new_session!(s)
                elseif cmd == "/resume"
                    _repl_resume!(s)
                elseif cmd == "/model"
                    model = find_model(arg)
                    model === nothing ? println("Model not found: $(arg)") :
                        (set_model!(s, model); println("Model: $(model.provider)/$(model.id)"))
                elseif cmd == "/thinking"
                    try
                        set_thinking_level!(s, arg)
                        println("Thinking level: $(arg)")
                    catch err
                        println(sprint(showerror, err))
                    end
                elseif cmd == "/compact"
                    compact!(s; reason="manual", instructions=isempty(arg) ? nothing : arg)
                    println("Compaction complete")
                elseif cmd == "/session"
                    state = get_state(s)
                    println("Session: $(state["sessionId"])")
                    println("File: $(something(state["sessionFile"], "(in-memory)"))")
                    println("Messages: $(state["messageCount"])")
                    println("Model: $(s.model.provider)/$(s.model.id)")
                elseif cmd == "/tools"
                    println(join(["$(t.name)" for t in s.tools], ", "))
                else
                    println("Unknown command: $(cmd)")
                end
                continue
            end
            t = @async try
                prompt!(s, line)
            catch err
                err isa InterruptException ? abort!(s) : @error "repl prompt failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
            try
                wait(t)
            catch err
                if err isa InterruptException
                    abort!(s)
                    try
                        wait(t)
                    catch err
                        @debug "REPL prompt task failed after abort" _group=LOG_TAG exception=(err, catch_backtrace())
                    end
                end
            end
        end
        return 0
    finally
        unsubscribe()
    end
end
