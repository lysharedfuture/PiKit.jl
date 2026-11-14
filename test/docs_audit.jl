@testset "documentation audit" begin
    import PiAISDK
    import PiAgentCore
    import PiCodingAgent

    root = dirname(@__DIR__)
    packages = [(PiAISDK, "PiAISDK"), (PiAgentCore, "PiAgentCore"),
                (PiCodingAgent, "PiCodingAgent"), (PiKit, "PiKit")]
    for (mod, name) in packages
        @test isempty(setdiff(Base.Docs.undocumented_names(mod), [nameof(mod)]))
        dir = name == "PiKit" ? root : joinpath(root, name)
        @test isfile(joinpath(dir, "README.md"))
        @test isfile(joinpath(dir, "LICENSE"))
    end

    # every page listed in docs/make.jl exists and has an @autodocs block
    make = read(joinpath(root, "docs", "make.jl"), String)
    @test occursin("checkdocs = :exports", make)
    for page in ("sdk.md", "agent-core.md", "coding-agent.md", "pikit.md")
        @test occursin("\"$(page)\"", make)
        text = read(joinpath(root, "docs", "src", page), String)
        @test occursin("@autodocs", text)
    end
end
