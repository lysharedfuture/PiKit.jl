const LOG_TAG = "coding_tools_bash"

const MAX_TIMEOUT_MS = 2_147_483_647
const MAX_TIMEOUT_SECONDS = MAX_TIMEOUT_MS ÷ 1000
const BASH_UPDATE_THROTTLE_MS = 200

const BASH_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "command" => Dict{String,Any}("type" => "string", "description" => "Shell command to execute"),
        "timeout" => Dict{String,Any}("type" => "number", "description" => "Timeout in seconds (optional, no default timeout)"),
    ),
    "required" => ["command"],
    "additionalProperties" => false,
)

"""
    BashOperations

Execution backend for [`bash_tool`](@ref).

# Fields
- `exec::Function`: called as
  `exec(command, cwd; on_data, signal, timeout, env, shell_path)` and returns a
  `NamedTuple` with `exit_code`, `output`, `timed_out`, `aborted`, and
  `full_output_path`.
"""
struct BashOperations
    exec::Function
end

function resolve_timeout_seconds(timeout)
    timeout === nothing && return nothing
    timeout isa Number || throw(ArgumentError("Invalid timeout: must be a finite number of seconds"))
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("Invalid timeout: must be a finite number of seconds"))
    timeout * 1000 > MAX_TIMEOUT_MS && throw(ArgumentError("Invalid timeout: maximum is $(MAX_TIMEOUT_SECONDS) seconds"))
    return Float64(timeout)
end

function _read_if_exists(path)
    isfile(path) || return ""
    try
        return read(path, String)
    catch err
        @debug "output file read failed" _group=LOG_TAG exception=(err, catch_backtrace())
        return ""
    end
end

"""
    default_bash_exec(command::String, cwd::String; on_data=nothing, signal=nothing,
                      timeout=nothing, env=nothing, shell_path=nothing)

Run `command` through the platform shell, streaming output snapshots to
`on_data` at most every ~200 ms and honoring abort signals and timeouts.

# Arguments
- `command::String`: shell command to run.
- `cwd::String`: working directory.
- `on_data`: callback receiving the current sanitized output snapshot.
- `signal`: `PiAISDK.AbortToken` used to kill the process tree.
- `timeout`: timeout in seconds, or `nothing` for no timeout.
- `env`: environment variables to apply.
- `shell_path`: explicit shell executable.

# Returns
`NamedTuple` with `exit_code`, `output`, `timed_out`, `aborted`, and
`full_output_path`.
"""
function default_bash_exec(command::String, cwd::String; on_data=nothing,
                           signal::Union{Nothing,PiAISDK.AbortToken}=nothing,
                           timeout::Union{Nothing,Float64}=nothing,
                           env::Union{Nothing,Dict{String,String}}=nothing,
                           shell_path::Union{Nothing,String}=nothing)
    config = get_shell_config(shell_path)
    outfile = tempname()
    out_io = open(outfile, "w")
    args = copy(config.args)
    if config.command_transport == :argv
        push!(args, command)
    end
    cmd = Cmd(vcat([config.shell], args))
    env !== nothing && (cmd = setenv(cmd, env))
    Sys.iswindows() || (cmd = detach(cmd))
    stdin_io = config.command_transport == :stdin ? IOBuffer(command) : nothing
    process = try
        if stdin_io === nothing
            run(pipeline(cmd; stdout=out_io, stderr=out_io); wait=false)
        else
            run(pipeline(cmd; stdin=stdin_io, stdout=out_io, stderr=out_io); wait=false)
        end
    catch err
        close(out_io)
        return (exit_code=1, output=sprint(showerror, err), timed_out=false, aborted=false, full_output_path=outfile)
    end
    started = time()
    last_snapshot = 0.0
    timed_out = false
    aborted = false
    while process_running(process)
        if signal !== nothing && PiAISDK.is_aborted(signal)
            kill_process_tree(Base.Libc.getpid(process))
            aborted = true
            break
        end
        if timeout !== nothing && time() - started > timeout
            kill_process_tree(Base.Libc.getpid(process))
            timed_out = true
            break
        end
        if on_data !== nothing && time() - last_snapshot >= BASH_UPDATE_THROTTLE_MS / 1000
            last_snapshot = time()
            snapshot = _read_if_exists(outfile)
            try
                on_data(sanitize_binary_output(snapshot))
            catch err
                @debug "bash on_data failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
        sleep(0.05)
    end
    try
        wait(process)
    catch err
        @debug "shell process wait failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    exit_code = process.exitcode
    try
        isopen(out_io) && close(out_io)
    catch err
        @debug "closing bash output file failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    output = sanitize_binary_output(_read_if_exists(outfile))
    return (exit_code=exit_code, output=output, timed_out=timed_out, aborted=aborted,
            full_output_path=outfile)
end

"""
    DEFAULT_BASH_OPERATIONS

[`BashOperations`](@ref) backed by [`default_bash_exec`](@ref).
"""
const DEFAULT_BASH_OPERATIONS = BashOperations(default_bash_exec)

function format_bash_output(output::String, exit_code, trunc::TruncationResult, full_path,
                            timed_out, timeout_seconds, aborted)
    text = rstrip(output, '\n')
    details = nothing
    if trunc.truncated
        text = trunc.content
        details = Dict{String,Any}("truncation" => _trunc_json(trunc), "fullOutputPath" => full_path)
        start_line = trunc.total_lines - trunc.output_lines + 1
        end_line = trunc.total_lines
        if trunc.last_line_partial
            last_line_size = format_size(sizeof(last(split_lines_for_counting(output))))
            text *= "\n\n[Showing last $(format_size(trunc.output_bytes)) of line $(end_line) (line is $(last_line_size)). Full output: $(full_path)]"
        elseif trunc.truncated_by == "lines"
            text *= "\n\n[Showing lines $(start_line)-$(end_line) of $(trunc.total_lines). Full output: $(full_path)]"
        else
            text *= "\n\n[Showing lines $(start_line)-$(end_line) of $(trunc.total_lines) ($(format_size(DEFAULT_MAX_BYTES)) limit). Full output: $(full_path)]"
        end
    end
    isempty(text) && (text = "(no output)")
    is_error = false
    if aborted
        text = isempty(text) ? "Command aborted" : text * "\n\nCommand aborted"
        is_error = true
    elseif timed_out
        status_text = "Command timed out after $(timeout_seconds) seconds"
        text = text == "(no output)" ? status_text : text * "\n\n" * status_text
        is_error = true
    elseif exit_code === nothing
        text = text == "(no output)" ? "Command terminated without an exit code" : text * "\n\nCommand terminated without an exit code"
        is_error = true
    elseif exit_code != 0
        text = text * "\n\nCommand exited with code $(exit_code)"
        is_error = true
    end
    return (text=text, details=details, is_error=is_error)
end

"""
    bash_tool(cwd::String; operations::BashOperations=DEFAULT_BASH_OPERATIONS,
              env=nothing, shell_path=nothing)

Create the `bash` tool. Output is truncated to the last [`DEFAULT_MAX_LINES`](@ref)
lines or [`DEFAULT_MAX_BYTES`](@ref) bytes; when truncated, the full output is
saved to a temporary file whose path is reported.

# Arguments
- `cwd::String`: working directory.
- `operations::BashOperations`: execution backend.
- `env`: extra environment variables for the shell.
- `shell_path`: explicit shell executable.

# Returns
A `PiAgentCore.Tool`.
"""
function bash_tool(cwd::String; operations::BashOperations=DEFAULT_BASH_OPERATIONS,
                   env::Union{Nothing,Dict{String,String}}=nothing,
                   shell_path::Union{Nothing,String}=nothing)
    execute = function (id, args, signal, on_update)
        command = String(args["command"])
        timeout_seconds = try
            resolve_timeout_seconds(get(args, "timeout", nothing))
        catch err
            return PiAgentCore.ToolResult(AbstractContent[TextContent(sprint(showerror, err))]; is_error=true)
        end
        update_cb = on_update === nothing ? nothing : output -> begin
            trunc = truncate_tail(output)
            on_update(Dict{String,Any}("content" => Any[PiAISDK.to_json(TextContent(trunc.content))],
                                       "details" => Dict{String,Any}()))
        end
        result = try
            operations.exec(command, cwd; on_data=update_cb, signal=signal,
                            timeout=timeout_seconds, env=env, shell_path=shell_path)
        catch err
            return PiAgentCore.ToolResult(AbstractContent[TextContent(sprint(showerror, err))]; is_error=true)
        end
        trunc = truncate_tail(result.output)
        formatted = format_bash_output(result.output, result.exit_code, trunc,
                                       result.full_output_path, result.timed_out,
                                       timeout_seconds, result.aborted)
        structured = Dict{String,Any}(
            "output" => result.output,
            "truncated" => trunc.truncated,
            "exit_code" => result.exit_code,
            "wall_time_seconds" => 0.0,
        )
        trunc.truncated && (structured["full_output_path"] = result.full_output_path)
        return PiAgentCore.ToolResult(AbstractContent[TextContent(formatted.text)];
            details=formatted.details, structured_content=structured, is_error=formatted.is_error)
    end
    description = "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last $(DEFAULT_MAX_LINES) lines or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
    return PiAgentCore.Tool("bash", description, BASH_SCHEMA, execute; label="bash")
end
