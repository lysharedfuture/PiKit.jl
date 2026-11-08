@testset "tools manager" begin
    td = mktempdir()
    bindir = joinpath(td, "bin")
    mkpath(bindir)
    rg = joinpath(bindir, "rg")
    write(rg, "#!/bin/sh\nexit 0\n")
    chmod(rg, 0o755)
    @test CA.ensure_tool("rg"; agent_dir=td) == rg
    @test CA.ensure_tool("rg"; agent_dir=td, offline=true) == rg

    empty = mktempdir()
    @test_throws ErrorException CA.ensure_tool("rg"; agent_dir=empty, offline=true)

    # PATH is used when the tool is not in the agent bin dir.
    path_td = mktempdir()
    fake = joinpath(path_td, "fd")
    write(fake, "#!/bin/sh\nexit 0\n")
    chmod(fake, 0o755)
    oldpath = ENV["PATH"]
    try
        ENV["PATH"] = path_td * ":" * oldpath
        @test CA.ensure_tool("fd"; agent_dir=mktempdir(), offline=true) == fake
    finally
        ENV["PATH"] = oldpath
    end
end
