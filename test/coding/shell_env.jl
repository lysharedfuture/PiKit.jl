@testset "shell environment" begin
    cfg = CA.get_shell_config()
    @test cfg.command_transport in (:argv, :stdin)
    @test !isempty(cfg.shell)
    if !Sys.iswindows()
        @test cfg.shell in ("/bin/bash", "sh") || occursin("bash", cfg.shell)
    end
    @test_throws ErrorException CA.get_shell_config("/definitely/not/a/shell")

    td = mktempdir()
    env = CA.get_shell_env(model="m1", session_id="s1", session_file="/tmp/s.jsonl",
                           provider="p", reasoning="high", agent_dir=td)
    @test env["PI_MODEL"] == "m1"
    @test env["PI_SESSION_ID"] == "s1"
    @test env["PI_PROVIDER"] == "p"
    @test startswith(env["PATH"], joinpath(td, "bin"))
    @test !haskey(env, "PI_REASONING_LEVEL") || env["PI_REASONING_LEVEL"] == "high"

    s = CA.sanitize_binary_output("a\x00b\x01c\td\ne")
    @test s == "abc\td\ne"

    if !Sys.iswindows()
        @test_throws ErrorException CA.get_powershell_config()
    end
end
