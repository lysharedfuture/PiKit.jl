@testset "tool details" begin
    td = mktempdir()
    f = joinpath(td, "a.txt")
    open(f, "w") do io
        for i in 1:2500
            println(io, "line$i")
        end
    end
    rr = CA.read_tool(td).execute("id", Dict{String,Any}("path" => "a.txt"), nothing, nothing)
    @test rr.details["truncation"]["truncated"] === true
    @test rr.details["truncation"]["totalLines"] == 2500

    br = CA.bash_tool(td).execute("id", Dict{String,Any}("command" => "seq 1 3000"), nothing, nothing)
    @test br.details["truncation"]["truncated"] === true
    @test haskey(br.details, "fullOutputPath")
    @test br.structured_content["exit_code"] == 0
    @test br.structured_content["truncated"] === true

    er = CA.edit_tool(td).execute("id", Dict{String,Any}("path" => "a.txt",
        "edits" => Any[Dict{String,Any}("oldText" => "line1\n", "newText" => "LINE1\n")]), nothing, nothing)
    @test haskey(er.details, "diff")
    @test occursin("--- a/a.txt", er.details["patch"])
end
