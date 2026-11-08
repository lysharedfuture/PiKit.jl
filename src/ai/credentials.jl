const LOG_TAG = "ai_credentials"

function _auth_paths(agent_dir)
    return unique([joinpath(homedir(), ".pikit", "auth.json"),
                   joinpath(dirname(agent_dir), "auth.json"),
                   joinpath(agent_dir, "auth.json")])
end

function _read_auth_file(path)
    isfile(path) || return nothing
    if !Sys.iswindows()
        mode = stat(path).mode & 0o777
        mode != 0o600 && @warn "auth.json permissions are not 0600" _group=LOG_TAG path=path mode=string(mode, base=8)
    end
    try
        return json_parse(read(path, String))
    catch err
        @warn "unable to parse auth.json" _group=LOG_TAG path=path exception=(err, catch_backtrace())
        return nothing
    end
end

function _value_from_auth(data, provider)
    data === nothing && return nothing
    v = get(data, provider, nothing)
    v === nothing && (v = get(data, "apiKeys", nothing))
    v isa AbstractDict && provider in keys(v) && (v = v[provider])
    v isa AbstractDict && (v = get(v, "key", get(v, "apiKey", get(v, "token", nothing))))
    v isa AbstractString && return String(v)
    return nothing
end

function _expand_key(value)
    value isa AbstractString || return nothing
    s = String(value)
    startswith(s, '!') && begin
        @warn "command substitution in apiKey is not supported" _group=LOG_TAG
        return nothing
    end
    m = match(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$", s)
    m !== nothing && return get(ENV, m.captures[1], nothing)
    m = match(r"^\$([A-Za-z_][A-Za-z0-9_]*)$", s)
    m !== nothing && return get(ENV, m.captures[1], nothing)
    return s
end

function _catalog_api_key(provider)
    path = joinpath(@__DIR__, "models.json")
    isfile(path) || return nothing
    raw = json_parse(read(path, String))
    providers = get(raw, "providers", Dict{String,Any}())
    conf = get(providers, provider, nothing)
    conf === nothing && return nothing
    return _expand_key(get(conf, "apiKey", nothing))
end

function resolve_api_key(provider::AbstractString; cli_override=nothing, agent_dir=joinpath(homedir(), ".pikit", "agent"))
    cli_override !== nothing && !isempty(cli_override) && return String(cli_override)
    for path in _auth_paths(agent_dir)
        key = _value_from_auth(_read_auth_file(path), provider)
        key !== nothing && !isempty(key) && return key
    end
    key = _catalog_api_key(provider)
    key !== nothing && !isempty(key) && return key
    return get(ENV, provider_api_key_hint(provider), nothing)
end
