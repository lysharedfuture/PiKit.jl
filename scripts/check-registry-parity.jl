#!/usr/bin/env julia
# Compare a LocalRegistry entry against the repository commit it claims to
# describe. Used before promoting a locally registered version to General.
#
#   julia --startup-file=no --project=scripts scripts/check-registry-parity.jl \
#       --registry /path/to/PiKitRegistry [--commit HEAD]
#
# Without --registry (or PIKIT_REGISTRY_PATH) the check is skipped so CI stays
# green until the development registry exists.

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PACKAGES = ["PiAISDK", "PiAgentCore", "PiCodingAgent", "PiKit"]

struct Problems
    entries::Vector{String}
end
Problems() = Problems(String[])
fail!(p::Problems, msg) = push!(p.entries, msg)

function git_output(args::Vector{String})
    io = IOBuffer()
    proc = run(pipeline(ignorestatus(`git -C $(ROOT) $(args)`); stdout=io, stderr=devnull); wait=true)
    proc.exitcode == 0 || return nothing
    return strip(String(take!(io)))
end

function tree_for(commit, name)
    spec = name == "PiKit" ? "$(commit)^{tree}" : "$(commit):$(name)"
    return git_output(["rev-parse", spec])
end

function main(args)
    registry = get(ENV, "PIKIT_REGISTRY_PATH", nothing)
    commit = "HEAD"
    i = 1
    while i <= length(args)
        if args[i] == "--registry"
            i < length(args) || error("--registry requires a path")
            registry = args[i + 1]
            i += 1
        elseif args[i] == "--commit"
            i < length(args) || error("--commit requires a revision")
            commit = args[i + 1]
            i += 1
        end
        i += 1
    end
    if registry === nothing
        println("skip: no development registry configured (set --registry or PIKIT_REGISTRY_PATH)")
        return nothing
    end
    registry = normpath(registry)
    index_path = joinpath(registry, "Registry.toml")
    isfile(index_path) || error("missing $(index_path)")
    index = TOML.parsefile(index_path)
    packages = get(index, "packages", Dict{String,Any}())
    by_name = Dict{String,Any}()
    for (uuid, entry) in packages
        entry isa AbstractDict || continue
        by_name[string(get(entry, "name", ""))] = entry
    end

    problems = Problems()
    commit_sha = git_output(["rev-parse", commit])
    commit_sha === nothing && error("unknown commit: $(commit)")
    for name in PACKAGES
        entry = get(by_name, name, nothing)
        if entry === nothing
            println("skip: $(name) is not in $(registry)")
            continue
        end
        reg_dir = joinpath(registry, string(entry["path"]))
        versions_path = joinpath(reg_dir, "Versions.toml")
        isfile(versions_path) || (fail!(problems, "missing $(versions_path)"); continue)
        versions = TOML.parsefile(versions_path)
        latest = isempty(versions) ? nothing : last(sort(collect(keys(versions)); by=VersionNumber))
        latest === nothing && (fail!(problems, "$(name) has no registered version"); continue)
        registered_tree = String(get(versions[latest], "git-tree-sha1", ""))
        isempty(registered_tree) && (fail!(problems, "$(name) $(latest) has no git-tree-sha1"); continue)
        actual_tree = tree_for(commit_sha, name)
        actual_tree === nothing && (fail!(problems, "cannot resolve tree for $(commit):$(name)"); continue)
        actual_tree == registered_tree ||
            fail!(problems, "$(name) $(latest): registry tree $(registered_tree) != $(commit) tree $(actual_tree)")
        package_toml = joinpath(reg_dir, "Package.toml")
        if isfile(package_toml)
            pkg = TOML.parsefile(package_toml)
            expected_subdir = name == "PiKit" ? nothing : name
            declared_subdir = get(pkg, "subdir", nothing)
            if expected_subdir === nothing
                declared_subdir === nothing ||
                    fail!(problems, "$(name) must not declare subdir $(declared_subdir)")
            else
                String(declared_subdir) == expected_subdir ||
                    fail!(problems, "$(name) subdir is $(repr(declared_subdir)), expected $(repr(expected_subdir))")
            end
        end
    end
    if isempty(problems.entries)
        println("OK: registry matches $(commit) (", join(PACKAGES, ", "), ")")
        return nothing
    end
    for entry in problems.entries
        println(stderr, "FAIL: ", entry)
    end
    exit(1)
end

main(ARGS)
