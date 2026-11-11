@testset "grep/find/ls" begin
    td = mktempdir()
    agent_dir = mktempdir()
    bindir = joinpath(agent_dir, "bin")
    mkpath(bindir)
    target = joinpath(td, "a.txt")
    write(target, "hello\nworld\nhello again\n")
    rg = joinpath(bindir, "rg")
    json_lines = [
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"$(target)\"},\"line_number\":1,\"lines\":{\"text\":\"hello\\n\"}}}",
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"$(target)\"},\"line_number\":3,\"lines\":{\"text\":\"hello again\\n\"}}}",
    ]
    write(rg, "#!/bin/sh\nprintf '%s\\n' " * join(["'" * replace(l, "'" => "'\\''") * "'" for l in json_lines], " ") * "\n")
    chmod(rg, 0o755)
    gt = CA.grep_tool(td; agent_dir=agent_dir)
    r = gt.execute("id", Dict{String,Any}("pattern" => "hello"), nothing, nothing)
    @test !r.is_error
    @test occursin("a.txt:1: hello", r.content[1].text)
    @test occursin("a.txt:3: hello again", r.content[1].text)

    r2 = gt.execute("id", Dict{String,Any}("pattern" => "hello", "limit" => 1), nothing, nothing)
    @test occursin("1 matches limit reached", r2.content[1].text)
    @test r2.details["matchLimitReached"] == 1

    fd = joinpath(bindir, "fd")
    write(fd, "#!/bin/sh\nprintf '%s\\n' '$(joinpath(td, "a.txt"))' '$(joinpath(td, "b.txt"))'\n")
    chmod(fd, 0o755)
    ft = CA.find_tool(td; agent_dir=agent_dir)
    fr = ft.execute("id", Dict{String,Any}("pattern" => "*.txt", "limit" => 1), nothing, nothing)
    @test !fr.is_error
    @test occursin("a.txt", fr.content[1].text)
    @test occursin("1 results limit reached", fr.content[1].text)
    @test fr.details["resultLimitReached"] == 1

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
