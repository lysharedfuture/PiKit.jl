@testset "model catalog" begin
    m = AI.find_model("anthropic/claude-sonnet-4-6")
    @test m !== nothing
    @test m.provider == "anthropic"
    @test m.api == "anthropic-messages"
    @test m.context_window == 200_000

    m2 = AI.find_model("claude-sonnet")
    @test m2 !== nothing && m2.id == "claude-sonnet-4-6"

    td = mktempdir()
    write(joinpath(td, "models.json"), AI.json_write(Dict(
        "providers" => Dict(
            "custom" => Dict(
                "baseUrl" => "http://x/v1", "api" => "openai-completions",
                "models" => Dict("mine" => Dict("name" => "Mine", "contextWindow" => 4096)))))))
    user = AI.load_user_models(td)
    @test length(user) == 1
    @test user[1].provider == "custom"
    @test user[1].context_window == 4096

    dm = AI.find_model("nope/missing-model")
    @test dm !== nothing
    @test dm.provider == "nope"
    @test dm.context_window == 128_000
end
