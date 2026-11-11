#!/usr/bin/env julia
# Static package-boundary check for the four-package layout.
#
#   julia scripts/check-package-boundaries.jl
#   julia scripts/check-package-boundaries.jl --root /tmp/fixture
#
# Rules enforced for every package P under <root>:
#   * `using`/`import` targets must be declared in P's `[deps]` (or Base/Core);
#     relative imports (`using ..X`) are rejected outright.
#   * `include("...")` must stay inside P's own `src/`.
#   * qualified references to another package must target a declared dependency.
#   * library packages must not use CLI markers (`ARGS`, `exit(`, `@main`) and
#     must not install a global logger.
#   * exported symbol sets: PiKit exports `main`; libraries do not, and
#     PiCodingAgent exports no CLI symbols.
#   * `[sources]` paths must be relative.

using TOML

const PACKAGE_ORDER = ["PiAI", "PiAgentCore", "PiCodingAgent", "PiKit"]
const LIBRARY_PACKAGES = Set(["PiAI", "PiAgentCore", "PiCodingAgent"])
const ALLOWED_BASE = Set(["Base", "Core"])
const CLI_SYMBOLS = Set([
    "main", "parse_cli", "CLIOptions", "CLIError", "HELP_TEXT", "list_models_text",
    "resolve_tool_names", "initial_prompt", "run_print_mode", "run_json_mode",
    "run_rpc_mode", "run_repl_mode", "json_mode_event", "session_json_event",
    "build_runtime",
])

const LIBRARY_MARKERS = [
    (r"\bARGS\b", "CLI argument access"),
    (r"(?<![\w.])exit\s*\(", "process exit"),
    (r"@main", "CLI entry point"),
]
const SUBPACKAGE_MARKERS = [
    (r"install_logging!", "global logger installation"),
    (r"global_logger", "global logger access"),
]

mutable struct Violations
    entries::Vector{String}
end
Violations() = Violations(String[])
add!(v::Violations, path, line, message) =
    push!(v.entries, string(path, ":", line, ": ", message))

package_root(root::AbstractString, name::AbstractString) =
    name == "PiKit" ? root : joinpath(root, name)

function read_manifest(root, name)
    path = joinpath(package_root(root, name), "Project.toml")
    isfile(path) || return nothing
    return TOML.parsefile(path)
end

function exported_symbols(pkgdir::AbstractString)
    names = Set{String}()
    for (dir, _, files) in walkdir(joinpath(pkgdir, "src"))
        for f in files
            endswith(f, ".jl") || continue
            text = read(joinpath(dir, f), String)
            for m in eachmatch(r"^export\s+(.+?)(?=\n\S|\Z)"ms, text)
                for part in split(m.captures[1], ",")
                    name = strip(part)
                    isempty(name) || push!(names, name)
                end
            end
        end
    end
    return names
end

function check_sources!(v::Violations, root, name, deps)
    pkgdir = package_root(root, name)
    src = joinpath(pkgdir, "src")
    isdir(src) || return
    allowed = union(Set(deps), Set([name]), ALLOWED_BASE)
    markers = name in LIBRARY_PACKAGES ? vcat(LIBRARY_MARKERS, SUBPACKAGE_MARKERS) : Pair{Regex,String}[]
    for (dir, _, files) in walkdir(src)
        for f in files
            endswith(f, ".jl") || continue
            path = joinpath(dir, f)
            rel = relpath(path, root)
            for (lineno, raw) in enumerate(eachline(path))
                line = replace(raw, r"#.*$" => "")
                m = match(r"^\s*(using|import)\s+(.+)$", line)
                if m !== nothing
                    symbol_list = false
                    for part in split(m.captures[2], ",")
                        item = strip(part)
                        isempty(item) && continue
                        pieces = split(item, ':')
                        if length(pieces) == 1
                            symbol_list && continue
                            target = item
                        else
                            symbol_list = true
                            target = strip(pieces[1])
                        end
                        isempty(target) && continue
                        if startswith(target, ".")
                            add!(v, rel, lineno, "relative module import: $(target)")
                            continue
                        end
                        mod = strip(first(split(target, '.')))
                        mod in allowed || add!(v, rel, lineno,
                            "undeclared dependency in $(m.captures[1]): $(mod)")
                    end
                end
                im = match(r"include\(\s*\"([^\"]+)\"\s*\)", line)
                if im !== nothing
                    target = normpath(joinpath(dir, im.captures[1]))
                    inside = startswith(target, src * Base.Filesystem.path_separator) || target == src
                    inside || add!(v, rel, lineno, "include escapes package src: $(im.captures[1])")
                end
                for q in eachmatch(r"\b(PiAI|PiAgentCore|PiCodingAgent|PiKit)\.", line)
                    other = q.captures[1]
                    (other == name || other in allowed) && continue
                    add!(v, rel, lineno, "reference to non-dependency package: $(other)")
                end
                for (pattern, message) in markers
                    occursin(pattern, line) && add!(v, rel, lineno, message)
                end
            end
        end
    end
end

function check_exports!(v::Violations, root, name)
    pkgdir = package_root(root, name)
    isdir(joinpath(pkgdir, "src")) || return
    exports = exported_symbols(pkgdir)
    if name == "PiKit"
        "main" in exports || add!(v, pkgdir, 1, "PiKit must export main")
    else
        "main" in exports && add!(v, pkgdir, 1, "library package must not export main")
        bad = sort(collect(intersect(exports, CLI_SYMBOLS)))
        isempty(bad) || add!(v, pkgdir, 1, "library package exports CLI symbols: $(join(bad, ", "))")
    end
end

function check_sources_paths!(v::Violations, root, name, manifest)
    sources = get(manifest, "sources", Dict{String,Any}())
    for (dep, spec) in sources
        spec isa AbstractDict || continue
        path = get(spec, "path", nothing)
        path === nothing && continue
        startswith(String(path), "/") &&
            add!(v, joinpath(package_root(root, name), "Project.toml"), 1,
                 "absolute [sources] path for $(dep): $(path)")
    end
end

function main(args)
    root = normpath(joinpath(@__DIR__, ".."))
    i = 1
    while i <= length(args)
        if args[i] == "--root"
            i < length(args) || error("--root requires a path")
            root = normpath(args[i + 1])
            i += 1
        end
        i += 1
    end
    violations = Violations()
    for name in PACKAGE_ORDER
        manifest = read_manifest(root, name)
        if manifest === nothing
            add!(violations, joinpath(root, name), 1, "missing Project.toml")
            continue
        end
        deps = collect(keys(get(manifest, "deps", Dict{String,Any}())))
        check_sources!(violations, root, name, deps)
        check_exports!(violations, root, name)
        check_sources_paths!(violations, root, name, manifest)
    end
    if isempty(violations.entries)
        println("OK: package boundaries clean (", join(PACKAGE_ORDER, ", "), ")")
        return nothing
    end
    for entry in violations.entries
        println(stderr, "FAIL: ", entry)
    end
    exit(1)
end

main(ARGS)
