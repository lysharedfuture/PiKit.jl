const LOG_TAG = "coding_tools_path_utils"

const UNICODE_SPACES = ['\u00a0', '\u202f', '\u2009', '\u2007', '\u2008']

function _normalize_spaces(s::String)
    return String([c in UNICODE_SPACES ? ' ' : c for c in s])
end

function expand_home(path::String)
    path == "~" && return homedir()
    (startswith(path, "~/") || startswith(path, "~\\")) || return path
    return joinpath(homedir(), path[3:end])
end

function resolve_to_cwd(path::AbstractString, cwd::AbstractString)
    p = String(path)
    startswith(p, '@') && (p = p[2:end])
    p = _normalize_spaces(p)
    p = expand_home(p)
    return isabspath(p) ? normpath(p) : normpath(abspath(joinpath(String(cwd), p)))
end

path_exists(path::AbstractString) = ispath(String(path))

function resolve_read_path(path::AbstractString, cwd::AbstractString)
    resolved = resolve_to_cwd(path, cwd)
    path_exists(resolved) && return resolved
    variants = String[]
    push!(variants, _normalize_spaces(resolved))
    push!(variants, Unicode.normalize(resolved, :NFC))
    push!(variants, Unicode.normalize(resolved, :NFD))
    push!(variants, replace(resolved, '‘' => '\'', '’' => '\'', '“' => '"', '”' => '"'))
    for v in variants
        path_exists(v) && return v
    end
    return resolved
end
