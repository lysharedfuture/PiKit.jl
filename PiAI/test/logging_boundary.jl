@testset "standalone logging boundary" begin
    # PiAI must not install a global logger, must not create ~/.pikit, and must
    # leave an existing logger untouched.
    agent_dir = mktempdir()
    script = joinpath(agent_dir, "probe.jl")
    write(script, """
    using Logging

    mutable struct Marker <: AbstractLogger end
    Logging.min_enabled_level(::Marker) = Logging.BelowMinLevel
    Logging.shouldlog(::Marker, level, _module, group, id) = true
    Logging.catch_exceptions(::Marker) = false
    function Logging.handle_message(::Marker, level, message, _module, group, id, file, line; kwargs...)
        return nothing
    end

    marker = Marker()
    Logging.global_logger(marker)
    using PiAI
    @info "probe" _group = "ai_json" answer = 42
    println("hijacked=", Logging.global_logger() !== marker)
    """)
    out = IOBuffer()
    err = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(dirname(@__DIR__)) $(script)`
    env = copy(ENV)
    env["PIKIT_AGENT_DIR"] = agent_dir
    proc = run(pipeline(ignorestatus(setenv(cmd, env)); stdout=out, stderr=err); wait=true)
    text = String(take!(out))
    @test proc.exitcode == 0
    @test occursin("hijacked=false", text)
    @test !ispath(joinpath(agent_dir, "logs", "app.log"))
end
