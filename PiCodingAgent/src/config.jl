const LOG_TAG = "coding_config"

"""
    RetryPolicy(; enabled=true, max_attempts=3, base_delay_ms=2000, max_delay_ms=60_000)

Retry and backoff configuration used for failed model requests and
summarization calls.

# Arguments
- `enabled::Bool`: whether automatic retries are enabled.
- `max_attempts::Int`: maximum number of retry attempts.
- `base_delay_ms::Int`: delay before the first retry, in milliseconds.
- `max_delay_ms::Int`: upper bound for a single retry delay, in milliseconds.
"""
struct RetryPolicy
    enabled::Bool
    max_attempts::Int
    base_delay_ms::Int
    max_delay_ms::Int
end

RetryPolicy(; enabled=true, max_attempts=3, base_delay_ms=2000, max_delay_ms=60_000) =
    RetryPolicy(enabled, max_attempts, base_delay_ms, max_delay_ms)

"""
    default_agent_dir()

Return the agent data directory: `PIKIT_AGENT_DIR` when set, otherwise
`~/.pikit/agent`. Settings, sessions, and helper binaries live below it.
"""
default_agent_dir() = get(ENV, "PIKIT_AGENT_DIR", joinpath(homedir(), ".pikit", "agent"))

"""
    is_tty(io::IO)

Return `true` when `io` refers to a terminal. Never throws; returns `false`
when the file descriptor cannot be inspected.
"""
function is_tty(io::IO)
    try
        fd = reinterpret(Int32, Base.fd(io))
        return Sys.iswindows() ? ccall(:_isatty, Cint, (Int32,), fd) != 0 :
                                 ccall(:isatty, Cint, (Int32,), fd) != 0
    catch err
        @debug "tty detection failed" _group=LOG_TAG exception=(err, catch_backtrace())
        return false
    end
end

function _read_json_file(path)
    isfile(path) || return Dict{String,Any}()
    try
        d = json_parse(read(path, String))
        return d isa AbstractDict ? Dict{String,Any}(String(k) => plain(v) for (k, v) in d) : Dict{String,Any}()
    catch err
        @warn "unable to parse settings" _group=LOG_TAG path=path exception=(err, catch_backtrace())
        return Dict{String,Any}()
    end
end

"""
    user_settings(agent_dir=default_agent_dir())

Read user-level settings from `agent_dir/settings.json`, falling back to the
parent directory's `settings.json`.

# Arguments
- `agent_dir`: agent directory to look in.

# Returns
`Dict{String,Any}` with the parsed settings, or an empty dict when no valid
file exists.
"""
function user_settings(agent_dir=default_agent_dir())
    candidates = [joinpath(agent_dir, "settings.json"), joinpath(dirname(agent_dir), "settings.json")]
    for path in candidates
        isfile(path) && return _read_json_file(path)
    end
    return Dict{String,Any}()
end

"""
    project_settings(cwd::String, trusted::Bool)

Read project settings from `.pikit/settings.json` below `cwd`. Untrusted
projects always yield an empty dict.

# Arguments
- `cwd::String`: project working directory.
- `trusted::Bool`: whether project-level configuration may be loaded.

# Returns
`Dict{String,Any}` with the parsed settings, or an empty dict.
"""
function project_settings(cwd::String, trusted::Bool)
    trusted || return Dict{String,Any}()
    return _read_json_file(joinpath(cwd, ".pikit", "settings.json"))
end

const SETTING_DEFAULTS = Dict{String,Any}(
    "autoCompaction" => true,
    "autoRetry" => true,
    "reserveTokens" => 16384,
    "keepRecentTokens" => 20000,
    "cacheRetention" => "short",
    "defaultTools" => ["read", "bash", "edit", "write"],
)

"""
    load_settings(cwd::String; trusted::Bool=false, agent_dir=default_agent_dir(),
                  cli=Dict{String,Any}())

Merge built-in defaults, user settings, optional project settings, and CLI
overrides (in that order) into one settings dictionary.

# Arguments
- `cwd::String`: project working directory.
- `trusted::Bool`: whether project settings may be applied.
- `agent_dir`: directory containing user settings.
- `cli`: overrides applied last.

# Returns
`Dict{String,Any}` of merged settings.
"""
function load_settings(cwd::String; trusted::Bool=false, agent_dir=default_agent_dir(), cli=Dict{String,Any}())
    merged = Dict{String,Any}(SETTING_DEFAULTS)
    for source in (user_settings(agent_dir), project_settings(cwd, trusted), cli)
        for (k, v) in source
            merged[String(k)] = v
        end
    end
    return merged
end

"""
    retry_policy(settings::AbstractDict)

Build a [`RetryPolicy`](@ref) from a settings dictionary. `autoRetry` (or the
nested `retry.enabled`) toggles retries; `retry.maxRetries`,
`retry.baseDelayMs`, and `retry.maxDelayMs` tune the backoff.

# Arguments
- `settings::AbstractDict`: settings produced by [`load_settings`](@ref).

# Returns
A [`RetryPolicy`](@ref).
"""
function retry_policy(settings::AbstractDict)
    retry = get(settings, "retry", Dict{String,Any}())
    retry isa AbstractDict || (retry = Dict{String,Any}())
    enabled = get(settings, "autoRetry", get(retry, "enabled", true))
    return RetryPolicy(
        enabled=Bool(enabled),
        max_attempts=Int(get(retry, "maxRetries", 3)),
        base_delay_ms=Int(get(retry, "baseDelayMs", 2000)),
        max_delay_ms=Int(get(retry, "maxDelayMs", 60_000)),
    )
end

"""
    configured_session_dir(settings::AbstractDict)

Return the `sessionDir` setting when present, otherwise `nothing`.

# Arguments
- `settings::AbstractDict`: settings dictionary.

# Returns
`String` session directory or `nothing`.
"""
function configured_session_dir(settings::AbstractDict)
    return get(settings, "sessionDir", nothing)
end
