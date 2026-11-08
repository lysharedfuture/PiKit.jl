@testset "path utils" begin
    cwd = mktempdir()
    @test CA.resolve_to_cwd("a/b", cwd) == normpath(joinpath(cwd, "a", "b"))
    @test CA.resolve_to_cwd("@a", cwd) == normpath(joinpath(cwd, "a"))
    @test CA.resolve_to_cwd("~", cwd) == homedir()
    @test CA.resolve_to_cwd("a\u00a0b", cwd) == normpath(joinpath(cwd, "a b"))
    @test isabspath(CA.resolve_to_cwd("/tmp/x", cwd))

    f = joinpath(cwd, "exists.txt")
    write(f, "x")
    @test CA.resolve_read_path("exists.txt", cwd) == f
    @test CA.resolve_read_path("missing.txt", cwd) == joinpath(cwd, "missing.txt")
    @test CA.path_exists(f)
    @test !CA.path_exists(joinpath(cwd, "nope"))
end
