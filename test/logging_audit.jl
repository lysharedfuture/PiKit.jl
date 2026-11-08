@testset "logging audit" begin
    src = joinpath(dirname(@__DIR__), "src")
    tagged = String[]
    bare_catch = String[]
    for (root, _, files) in walkdir(src)
        for f in files
            endswith(f, ".jl") || continue
            path = joinpath(root, f)
            text = read(path, String)
            occursin("const LOG_TAG", text) && push!(tagged, path)
            if occursin(r"catch\s*\n?\s*end", text) || occursin("catch; nothing", text)
                push!(bare_catch, path)
            end
        end
    end
    @test !isempty(tagged)
    @test any(p -> endswith(p, "logging.jl"), tagged)
    @test isempty(bare_catch)

    # every log call uses _group, never a plain tag= key
    for (root, _, files) in walkdir(src)
        for f in files
            endswith(f, ".jl") || continue
            text = read(joinpath(root, f), String)
            for m in eachmatch(r"@(info|warn|error|debug)\s+\"[^\"]*\"\s+([^\n]*)", text)
                @test occursin("_group=", m.captures[2])
            end
        end
    end
end
