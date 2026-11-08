@testset "write tool" begin
    td = mktempdir()
    tool = CA.write_tool(td)
    r = tool.execute("id", Dict{String,Any}("path" => "a/b/c.txt", "content" => "hello"), nothing, nothing)
    @test !r.is_error
    @test read(joinpath(td, "a", "b", "c.txt"), String) == "hello"
    @test r.content[1].text == "Successfully wrote to a/b/c.txt"

    r2 = tool.execute("id", Dict{String,Any}("path" => "a/b/c.txt", "content" => "bye"), nothing, nothing)
    @test !r2.is_error
    @test read(joinpath(td, "a", "b", "c.txt"), String) == "bye"

    # same-path writes are serialized
    t1 = @async tool.execute("1", Dict{String,Any}("path" => "same.txt", "content" => "one"), nothing, nothing)
    t2 = @async tool.execute("2", Dict{String,Any}("path" => "same.txt", "content" => "two"), nothing, nothing)
    wait(t1); wait(t2)
    @test read(joinpath(td, "same.txt"), String) in ("one", "two")
end
