const LOG_TAG = "coding_tools_shell_env"

const POWERSHELL_ARGS = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]

struct ShellConfig
    shell::String
    args::Vector{String}
    command_transport::Symbol
end

function _is_legacy_wsl_bash(path::String)
    normalized = lowercase(replace(path, '\\' => '/'))
    system_root = get(ENV, "SystemRoot", "")
    if !isempty(system_root)
        root = lowercase(rstrip(replace(system_root, '\\' => '/'), '/'))
        return normalized == "$(root)/system32/bash.exe" || normalized == "$(root)/sysnative/bash.exe"
    end
    return occursin(r"^[a-z]:/windows/(?:system32|sysnative)/bash\.exe$", normalized)
end

function _bash_shell_config(shell::String)
    if _is_legacy_wsl_bash(shell)
        return ShellConfig(shell, ["-s"], :stdin)
    end
    return ShellConfig(shell, ["-c"], :argv)
end

function find_executable_on_path(executable::String)
    path = Sys.which(executable)
    return path === nothing ? nothing : String(path)
end

function get_shell_config(custom_shell_path::Union{Nothing,String}=nothing)
    if custom_shell_path !== nothing && !isempty(custom_shell_path)
        ispath(custom_shell_path) || throw(ErrorException("Custom shell path not found: $(custom_shell_path)"))
        return _bash_shell_config(custom_shell_path)
    end
    if Sys.iswindows()
        candidates = String[]
        pf = get(ENV, "ProgramFiles", "")
        isempty(pf) || push!(candidates, joinpath(pf, "Git", "bin", "bash.exe"))
        pfx86 = get(ENV, "ProgramFiles(x86)", "")
        isempty(pfx86) || push!(candidates, joinpath(pfx86, "Git", "bin", "bash.exe"))
        for path in candidates
            ispath(path) && return _bash_shell_config(path)
        end
        bash = find_executable_on_path("bash.exe")
        bash === nothing || return _bash_shell_config(bash)
        throw(ErrorException("No bash shell found. Install Git for Windows or add bash to PATH."))
    end
    ispath("/bin/bash") && return _bash_shell_config("/bin/bash")
    bash = find_executable_on_path("bash")
    bash === nothing || return _bash_shell_config(bash)
    return ShellConfig("sh", ["-c"], :argv)
end

function get_powershell_config()
    Sys.iswindows() || throw(ErrorException("The powershell tool is only available on Windows."))
    shell = find_executable_on_path("pwsh.exe")
    if shell === nothing
        pf = get(ENV, "ProgramFiles", "")
        if !isempty(pf)
            candidate = joinpath(pf, "PowerShell", "7", "pwsh.exe")
            ispath(candidate) && (shell = candidate)
        end
    end
    shell === nothing && (shell = find_executable_on_path("powershell.exe"))
    if shell === nothing
        root = get(ENV, "SystemRoot", "C:\\Windows")
        candidate = joinpath(root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
        ispath(candidate) && (shell = candidate)
    end
    shell === nothing && throw(ErrorException("No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH."))
    return ShellConfig(shell, copy(POWERSHELL_ARGS), :argv)
end

function get_shell_env(; model=nothing, session_id=nothing, session_file=nothing,
                       provider=nothing, reasoning=nothing, agent_dir=default_agent_dir())
    env = Dict{String,String}(String(k) => String(v) for (k, v) in ENV)
    path_key = Sys.iswindows() ? something(findfirst(k -> lowercase(k) == "path", collect(keys(env)),), "PATH") : "PATH"
    path_key = path_key isa Int ? collect(keys(env))[path_key] : "PATH"
    bin_dir = joinpath(agent_dir, "bin")
    current = get(env, path_key, "")
    entries = split(current, Sys.iswindows() ? ';' : ':'; keepempty=false)
    if !(bin_dir in entries)
        env[path_key] = isempty(current) ? bin_dir : bin_dir * (Sys.iswindows() ? ";" : ":") * current
    end
    for key in ("PI_SESSION_ID", "PI_SESSION_FILE", "PI_PROVIDER", "PI_MODEL", "PI_REASONING_LEVEL")
        delete!(env, key)
    end
    session_id === nothing || (env["PI_SESSION_ID"] = String(session_id))
    session_file === nothing || (env["PI_SESSION_FILE"] = String(session_file))
    provider === nothing || (env["PI_PROVIDER"] = String(provider))
    model === nothing || (env["PI_MODEL"] = String(model))
    reasoning === nothing || (env["PI_REASONING_LEVEL"] = String(reasoning))
    return env
end

function sanitize_binary_output(s::String)
    return String([c for c in s if !(c in ('\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07',
                                            '\x08', '\x0b', '\x0c', '\x0e', '\x0f', '\x10', '\x11', '\x12',
                                            '\x13', '\x14', '\x15', '\x16', '\x17', '\x18', '\x19', '\x1a',
                                            '\x1b', '\x1c', '\x1d', '\x1e', '\x1f', '\ufff9', '\ufffa', '\ufffb'))])
end

function kill_process_tree(pid::Integer)
    if Sys.iswindows()
        root = get(ENV, "SystemRoot", "C:\\Windows")
        taskkill = joinpath(root, "System32", "taskkill.exe")
        try
            run(pipeline(`$taskkill /F /T /PID $pid`; stdout=devnull, stderr=devnull); wait=true)
        catch err
            @debug "taskkill failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
        return nothing
    end
    if Sys.isapple()
        ccall(:kill, Cint, (Cint, Cint), -Cint(pid), Cint(19))
    end
    result = ccall(:kill, Cint, (Cint, Cint), -Cint(pid), Cint(9))
    result == 0 || ccall(:kill, Cint, (Cint, Cint), Cint(pid), Cint(9))
    return nothing
end
