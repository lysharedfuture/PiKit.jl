@testset "edit tool" begin
    td = mktempdir()
    tool = CA.edit_tool(td)
    file = joinpath(td, "e.txt")
    write(file, "\ufeffa\r\nb\r\nc\r\n")
    r = tool.execute("id", Dict{String,Any}("path" => "e.txt",
        "edits" => Any[Dict{String,Any}("oldText" => "b", "newText" => "B")]), nothing, nothing)
    @test !r.is_error
    @test r.content[1].text == "Successfully replaced 1 block(s) in e.txt."
    raw = read(file)
    @test raw[1:3] == UInt8[0xef, 0xbb, 0xbf]
    @test String(raw) == "\ufeffa\r\nB\r\nc\r\n"
    @test haskey(r.details, "diff") && haskey(r.details, "patch")

    # multiple disjoint edits
    write(file, "one two three")
    r2 = tool.execute("id", Dict{String,Any}("path" => "e.txt", "edits" => Any[
        Dict{String,Any}("oldText" => "one", "newText" => "1"),
        Dict{String,Any}("oldText" => "three", "newText" => "3")]), nothing, nothing)
    @test !r2.is_error
    @test read(file, String) == "1 two 3"

    # duplicate match
    write(file, "a\na")
    r3 = tool.execute("id", Dict{String,Any}("path" => "e.txt",
        "edits" => Any[Dict{String,Any}("oldText" => "a", "newText" => "b")]), nothing, nothing)
    @test r3.is_error
    @test occursin("multiple matches", lowercase(r3.content[1].text))

    # legacy shape and JSON-string edits
    write(file, "hello")
    r4 = tool.execute("id", Dict{String,Any}("path" => "e.txt", "oldText" => "hello", "newText" => "bye"), nothing, nothing)
    @test !r4.is_error
    @test read(file, String) == "bye"
    r5 = tool.execute("id", Dict{String,Any}("path" => "e.txt",
        "edits" => "[{\"oldText\":\"bye\",\"newText\":\"ok\"}]"), nothing, nothing)
    @test !r5.is_error
    @test read(file, String) == "ok"

    # overlapping edits
    write(file, "abcdef")
    r6 = tool.execute("id", Dict{String,Any}("path" => "e.txt", "edits" => Any[
        Dict{String,Any}("oldText" => "abc", "newText" => "x"),
        Dict{String,Any}("oldText" => "bcd", "newText" => "y")]), nothing, nothing)
    @test r6.is_error
end
