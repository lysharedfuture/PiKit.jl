#!/usr/bin/env julia
# Enforce the documentation, licence, naming and monorepo-tag rules from
# .omp/RULES.md. Static checks only: no package is loaded.
#
#   julia --startup-file=no --project=scripts scripts/check-project-rules.jl

using TOML

const DEFAULT_ROOT = normpath(joinpath(@__DIR__, ".."))
const SUBPACKAGES = ["PiAISDK", "PiAgentCore", "PiCodingAgent"]
const ROOT_PACKAGE = "PiKit"
const PACKAGES = vcat([ROOT_PACKAGE], SUBPACKAGES)
const DOC_PAGES = Dict(
    "PiAISDK" => "sdk.md",
    "PiAgentCore" => "agent-core.md",
    "PiCodingAgent" => "coding-agent.md",
    "PiKit" => "pikit.md",
)
const RESERVED_NAME_START = "Ju"
const RESERVED_NAME_END = "jl"

struct Problems
    entries::Vector{String}
end
Problems() = Problems(String[])
fail!(p::Problems, msg) = push!(p.entries, msg)

package_dir(root, name) = name == ROOT_PACKAGE ? root : joinpath(root, name)

function check_name!(problems, name)
    if !(name isa AbstractString && occursin(r"^[A-Z][A-Za-z0-9]*$", name))
        fail!(problems, "invalid package name $(repr(name)): must start upper-case and be ASCII alphanumeric")
        return
    end
    length(name) >= 5 || fail!(problems, "package name $(repr(name)) is shorter than 5 characters")
    occursin(r"[a-z]", name) || fail!(problems, "package name $(repr(name)) needs a lower-case letter")
    startswith(name, RESERVED_NAME_START) &&
        fail!(problems, "package name $(repr(name)) must not start with $(RESERVED_NAME_START)")
    endswith(name, RESERVED_NAME_END) &&
        fail!(problems, "package name $(repr(name)) must not end with $(RESERVED_NAME_END)")
    occursin("julia", lowercase(name)) &&
        fail!(problems, "package name $(repr(name)) must not contain \"julia\"")
    return nothing
end

function check_manifest!(problems, root, name)
    dir = package_dir(root, name)
    path = joinpath(dir, "Project.toml")
    if !isfile(path)
        fail!(problems, "missing $(relpath(path, root))")
        return nothing
    end
    manifest = TOML.parsefile(path)
    declared = get(manifest, "name", nothing)
    declared == name || fail!(problems, "$(relpath(path, root)): name is $(repr(declared)), expected $(repr(name))")
    for field in ("uuid", "version")
        haskey(manifest, field) || fail!(problems, "$(relpath(path, root)): missing $(field)")
    end
    compat = get(manifest, "compat", Dict{String,Any}())
    haskey(compat, "julia") || fail!(problems, "$(relpath(path, root)): missing [compat] julia")
    for (dep, range) in compat
        dep == "julia" && continue
        isempty(string(range)) && fail!(problems, "$(relpath(path, root)): empty [compat] for $(dep)")
    end
    check_name!(problems, name)
    return manifest
end

function check_license!(problems, root, name)
    path = joinpath(package_dir(root, name), "LICENSE")
    isfile(path) || fail!(problems, "missing $(relpath(path, root)) (AutoMerge requires a top-level licence)")
end

function check_readme!(problems, root, name)
    path = joinpath(package_dir(root, name), "README.md")
    if !isfile(path)
        fail!(problems, "missing $(relpath(path, root))")
        return
    end
    text = read(path, String)
    length(text) >= 200 || fail!(problems, "$(relpath(path, root)) is too short for a package README")
    occursin("lysharedfuture.github.io", text) ||
        fail!(problems, "$(relpath(path, root)) does not link to the documentation site")
    if name == ROOT_PACKAGE
        occursin("badge", lowercase(text)) || fail!(problems, "$(relpath(path, root)) is missing the docs badge")
    end
end

function check_docs!(problems, root)
    makefile = joinpath(root, "docs", "make.jl")
    if !isfile(makefile)
        fail!(problems, "missing docs/make.jl")
        return
    end
    make = read(makefile, String)
    occursin("checkdocs = :exports", make) ||
        fail!(problems, "docs/make.jl must set checkdocs = :exports")
    for name in PACKAGES
        page = get(DOC_PAGES, name, nothing)
        page === nothing && continue
        path = joinpath(root, "docs", "src", page)
        if !isfile(path)
            fail!(problems, "missing docs/src/$(page)")
            continue
        end
        text = read(path, String)
        occursin("@autodocs", text) || fail!(problems, "docs/src/$(page) has no @autodocs block")
        occursin("Modules = [$(name)]", text) ||
            fail!(problems, "docs/src/$(page) does not document Modules = [$(name)]")
        occursin("\"$(page)\"", make) || fail!(problems, "docs/make.jl does not list $(page)")
    end
end

function check_tagbot!(problems, root)
    path = joinpath(root, ".github", "workflows", "TagBot.yml")
    if !isfile(path)
        fail!(problems, "missing .github/workflows/TagBot.yml")
        return
    end
    text = read(path, String)
    steps = count("JuliaRegistries/TagBot@", text)
    steps >= length(PACKAGES) ||
        fail!(problems, "TagBot.yml has $(steps) TagBot steps, expected at least $(length(PACKAGES))")
    for name in SUBPACKAGES
        occursin("subdir: $(name)", text) ||
            fail!(problems, "TagBot.yml has no step with subdir: $(name)")
    end
    subdir_steps = count(r"subdir:"m, text)
    steps > subdir_steps ||
        fail!(problems, "TagBot.yml has no root step without subdir")
end

function main(args)
    root = DEFAULT_ROOT
    checked_name = nothing
    i = 1
    while i <= length(args)
        if args[i] == "--root"
            i < length(args) || error("--root requires a path")
            root = normpath(args[i + 1])
            i += 1
        elseif args[i] == "--check-name"
            i < length(args) || error("--check-name requires a package name")
            checked_name = args[i + 1]
            i += 1
        end
        i += 1
    end
    if checked_name !== nothing
        problems = Problems()
        check_name!(problems, checked_name)
        isempty(problems.entries) && return println("OK: name ", checked_name)
        for entry in problems.entries
            println(stderr, "FAIL: ", entry)
        end
        return exit(1)
    end
    problems = Problems()
    for name in PACKAGES
        check_manifest!(problems, root, name)
        check_license!(problems, root, name)
        check_readme!(problems, root, name)
    end
    check_docs!(problems, root)
    check_tagbot!(problems, root)
    if isempty(problems.entries)
        println("OK: project rules clean (", join(PACKAGES, ", "), ")")
        return nothing
    end
    for entry in problems.entries
        println(stderr, "FAIL: ", entry)
    end
    exit(1)
end

main(ARGS)
