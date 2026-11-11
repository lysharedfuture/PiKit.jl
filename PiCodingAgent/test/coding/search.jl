@testset "grep/find/ls" begin
    td = mktempdir()
    target = joinpath(td, "a.txt")
    write(target, "hello\nworld\nhello again\n")
    write(joinpath(td, "b.txt"), "beta\n")

    # both external tools come from JLL artifacts, not from the host PATH
    @test isfile(first(fd_jll.fd_executable().exec))
    @test success(`$(fd_jll.fd_executable()) --version`)
    @test success(`$(ripgrep_jll.rg()) --version`)

    gt = CA.grep_tool(td)
    r = gt.execute("id", Dict{String,Any}("pattern" => "hello"), nothing, nothing)
    @test !r.is_error
    @test occursin("a.txt:1: hello", r.content[1].text)
    @test occursin("a.txt:3: hello again", r.content[1].text)

    r2 = gt.execute("id", Dict{String,Any}("pattern" => "hello", "limit" => 1), nothing, nothing)
    @test occursin("1 matches limit reached", r2.content[1].text)
    @test r2.details["matchLimitReached"] == 1

    ft = CA.find_tool(td)
    fr = ft.execute("id", Dict{String,Any}("pattern" => "*.txt", "limit" => 1), nothing, nothing)
    @test !fr.is_error
    @test occursin("1 results limit reached", fr.content[1].text)
    @test fr.details["resultLimitReached"] == 1

    full = ft.execute("id", Dict{String,Any}("pattern" => "*.txt"), nothing, nothing)
    @test !full.is_error
    @test occursin("a.txt", full.content[1].text)
    @test occursin("b.txt", full.content[1].text)

    withenv("PATH" => mktempdir()) do
        jll = ft.execute("id", Dict{String,Any}("pattern" => "*.txt"), nothing, nothing)
        @test !jll.is_error
        @test occursin("a.txt", jll.content[1].text)
    end

    mkdir(joinpath(td, "dir"))
    write(joinpath(td, "z.txt"), "z")
    lt = CA.ls_tool(td)
    lr = lt.execute("id", Dict{String,Any}(), nothing, nothing)
    @test occursin("a.txt", lr.content[1].text)
    @test occursin("dir/", lr.content[1].text)
    @test occursin("z.txt", lr.content[1].text)

    lr2 = lt.execute("id", Dict{String,Any}("limit" => 1), nothing, nothing)
    @test occursin("entries limit reached", lr2.content[1].text)
end
