@testset "logging audit" begin
    root = dirname(@__DIR__)
    roots = [joinpath(root, "src"), joinpath(root, "PiAISDK", "src"),
             joinpath(root, "PiAgentCore", "src"), joinpath(root, "PiCodingAgent", "src")]
    tagged = String[]
    bare_catch = String[]
    for src in roots
        for (dir, _, files) in walkdir(src)
            for f in files
                endswith(f, ".jl") || continue
                path = joinpath(dir, f)
                text = read(path, String)
                occursin("const LOG_TAG", text) && push!(tagged, path)
                if occursin(r"catch\s*\n?\s*end", text) || occursin("catch; nothing", text)
                    push!(bare_catch, path)
                end
            end
        end
    end
    @test !isempty(tagged)
    @test any(p -> endswith(p, "logging.jl"), tagged)
    @test isempty(bare_catch)

    # tags are unique and namespaced by package
    tags = Dict{String,String}()
    for path in tagged
        m = match(r"const LOG_TAG = \"([a-z0-9_]+)\"", read(path, String))
        m === nothing && continue
        tag = m.captures[1]
        @test !haskey(tags, tag)
        tags[tag] = path
    end
    for (tag, path) in tags
        rel = relpath(path, root)
        prefix = if startswith(rel, "PiAgentCore/")
            "agent_core_"
        elseif startswith(rel, "PiCodingAgent/")
            "coding_"
        elseif startswith(rel, "PiAISDK/")
            "ai_"
        else
            "pikit_"
        end
        @test startswith(tag, prefix)
    end

    # every log call uses _group, never a plain tag= key
    for src in roots
        for (dir, _, files) in walkdir(src)
            for f in files
                endswith(f, ".jl") || continue
                text = read(joinpath(dir, f), String)
                for m in eachmatch(r"@(info|warn|error|debug)\s+\"[^\"]*\"\s+([^\n]*)", text)
                    @test occursin("_group=", m.captures[2])
                end
            end
        end
    end

    # only PiKit installs the global logger; subpackages must stay silent
    for pkg in ("PiAISDK", "PiAgentCore", "PiCodingAgent")
        for (dir, _, files) in walkdir(joinpath(root, pkg, "src"))
            for f in files
                endswith(f, ".jl") || continue
                text = read(joinpath(dir, f), String)
                @test !occursin("install_logging!", text)
                @test !occursin("global_logger", text)
            end
        end
    end
end
