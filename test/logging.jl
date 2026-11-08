@testset "logging" begin
    td = mktempdir()
    path = joinpath(td, "app.log")
    logger = PiKit.TagFilterLogger(file=path, spec="info,ai_json=debug")
    Logging.with_logger(logger) do
        @info "visible info" _group="ai_json" key=1
        @debug "visible debug" _group="ai_json"
        @debug "hidden debug" _group="coding_tools_read"
        @warn "warn" _group="coding_tools_read"
    end
    text = read(path, String)
    @test occursin("visible info", text)
    @test occursin("visible debug", text)
    @test !occursin("hidden debug", text)
    @test occursin("warn", text)
    @test occursin("ai_json", text)
    close(logger.sink)

    # stderr-only logger never writes files and respects levels
    stderr_logger = PiKit.TagFilterLogger(stderr=true, spec="info")
    @test Logging.shouldlog(stderr_logger, Logging.Info, PiKit, "x", :id)
    @test !Logging.shouldlog(stderr_logger, Logging.Debug, PiKit, "x", :id)

    red = PiKit.redact(Dict("api_key" => "secret", "nested" => Dict("authorization" => "Bearer x", "ok" => 1)))
    @test red["api_key"] == "[REDACTED]"
    @test red["nested"]["authorization"] == "[REDACTED]"
    @test red["nested"]["ok"] == 1
end
