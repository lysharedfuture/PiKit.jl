@testset "config" begin
    td = mktempdir()
    agent_dir = joinpath(td, "agent")
    mkpath(agent_dir)
    write(joinpath(agent_dir, "settings.json"), AI.json_write(Dict("model" => "m", "autoCompaction" => false)))
    us = CA.user_settings(agent_dir)
    @test us["model"] == "m"

    project = joinpath(td, "proj")
    mkpath(joinpath(project, ".pikit"))
    write(joinpath(project, ".pikit", "settings.json"), AI.json_write(Dict("thinking" => "high")))
    @test isempty(CA.project_settings(project, false))
    @test CA.project_settings(project, true)["thinking"] == "high"

    merged = CA.load_settings(project; trusted=true, agent_dir=agent_dir)
    @test merged["thinking"] == "high"
    @test merged["autoCompaction"] === false
    @test merged["reserveTokens"] == 16384

    policy = CA.retry_policy(Dict("retry" => Dict("maxRetries" => 5, "baseDelayMs" => 10)))
    @test policy.enabled && policy.max_attempts == 5 && policy.base_delay_ms == 10
    @test !CA.retry_policy(Dict("autoRetry" => false)).enabled
end
