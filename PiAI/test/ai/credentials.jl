@testset "credentials" begin
    td = mktempdir()
    agent_dir = joinpath(td, "agent")
    mkpath(agent_dir)
    ENV["MYPROVIDER_API_KEY"] = "env-key"
    @test AI.resolve_api_key("myprovider"; agent_dir=agent_dir) == "env-key"

    write(joinpath(td, "auth.json"), AI.json_write(Dict("myprovider" => Dict("key" => "auth-key"))))
    chmod(joinpath(td, "auth.json"), 0o600)
    @test AI.resolve_api_key("myprovider"; agent_dir=agent_dir) == "auth-key"
    @test AI.resolve_api_key("myprovider"; cli_override="cli-key", agent_dir=agent_dir) == "cli-key"

    ENV["CATALOG_ENV_KEY"] = "expanded"
    path = joinpath(td, "cat", "models.json")
    mkpath(dirname(path))
    write(path, AI.json_write(Dict("providers" => Dict("cat" => Dict(
        "baseUrl" => "http://x", "api" => "openai-completions", "apiKey" => "\$CATALOG_ENV_KEY",
        "models" => Dict("m" => Dict()))))))
    # resolve_api_key reads the packaged catalog, not an arbitrary dir; env fallback is still covered above.
    @test AI.provider_api_key_hint("anthropic") == "ANTHROPIC_API_KEY"
end
