const LOG_TAG = "coding_tools_powershell"

const POWERSHELL_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "command" => Dict{String,Any}("type" => "string", "description" => "PowerShell command to execute"),
        "timeout" => Dict{String,Any}("type" => "number", "description" => "Timeout in seconds (optional, no default timeout)")),
    "required" => ["command"],
    "additionalProperties" => false,
)

"""
    PowerShellOperations

Alias for [`BashOperations`](@ref); the PowerShell tool shares the bash
execution interface.
"""
const PowerShellOperations = BashOperations

function powershell_exec(command::String, cwd::String; on_data=nothing,
                         signal::Union{Nothing,PiAISDK.AbortToken}=nothing,
                         timeout::Union{Nothing,Float64}=nothing,
                         env::Union{Nothing,Dict{String,String}}=nothing,
                         shell_path::Union{Nothing,String}=nothing)
    Sys.iswindows() || return (exit_code=1, output="The powershell tool is only available on Windows.",
                               timed_out=false, aborted=false, full_output_path="")
    config = get_powershell_config()
    prefix = "try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}; "
    full_command = prefix * command
    args = vcat(config.args, [full_command])
    cmd = Cmd(vcat([config.shell], args))
    Sys.iswindows() || (cmd = detach(cmd))
    env !== nothing && (cmd = setenv(cmd, env))
    outfile = tempname()
    out_io = open(outfile, "w")
    process = try
        run(pipeline(cmd; stdout=out_io, stderr=out_io); wait=false)
    catch err
        close(out_io)
        return (exit_code=1, output=sprint(showerror, err), timed_out=false, aborted=false, full_output_path=outfile)
    end
    started = time()
    timed_out = false
    aborted = false
    while process_running(process)
        if signal !== nothing && PiAISDK.is_aborted(signal)
            kill_process_tree(Base.Libc.getpid(process)); aborted = true; break
        end
        if timeout !== nothing && time() - started > timeout
            kill_process_tree(Base.Libc.getpid(process)); timed_out = true; break
        end
        on_data === nothing || on_data(sanitize_binary_output(_read_if_exists(outfile)))
        sleep(0.05)
    end
    try
        wait(process)
    catch err
        @debug "powershell wait failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    try
        isopen(out_io) && close(out_io)
    catch err
        @debug "closing powershell output file failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    return (exit_code=process.exitcode, output=sanitize_binary_output(_read_if_exists(outfile)),
            timed_out=timed_out, aborted=aborted, full_output_path=outfile)
end

"""
    powershell_tool(cwd::String; env=nothing)

Create the `powershell` tool. The tool is Windows-only; elsewhere it returns
an error result. Output is truncated like [`bash_tool`](@ref).

# Arguments
- `cwd::String`: working directory.
- `env`: extra environment variables.

# Returns
A `PiAgentCore.Tool`.
"""
function powershell_tool(cwd::String; env::Union{Nothing,Dict{String,String}}=nothing)
    execute = function (id, args, signal, on_update)
        Sys.iswindows() || return PiAgentCore.ToolResult(
            AbstractContent[TextContent("The powershell tool is only available on Windows.")]; is_error=true)
        command = String(args["command"])
        timeout_seconds = try
            resolve_timeout_seconds(get(args, "timeout", nothing))
        catch err
            return PiAgentCore.ToolResult(AbstractContent[TextContent(sprint(showerror, err))]; is_error=true)
        end
        result = powershell_exec(command, cwd; signal=signal, timeout=timeout_seconds, env=env)
        trunc = truncate_tail(result.output)
        formatted = format_bash_output(result.output, result.exit_code, trunc,
                                       result.full_output_path, result.timed_out,
                                       timeout_seconds, result.aborted)
        return PiAgentCore.ToolResult(AbstractContent[TextContent(formatted.text)];
            details=formatted.details, is_error=formatted.is_error)
    end
    description = "Execute a PowerShell command in the current working directory. Returns stdout and stderr. Output is truncated to last $(DEFAULT_MAX_LINES) lines or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first)."
    return PiAgentCore.Tool("powershell", description, POWERSHELL_SCHEMA, execute; label="powershell")
end
