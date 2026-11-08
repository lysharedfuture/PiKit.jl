@testset "read tool" begin
    td = mktempdir()
    tool = CA.read_tool(td)
    file = joinpath(td, "big.txt")
    open(file, "w") do io
        for i in 1:2500
            println(io, "line$i")
        end
    end
    r = tool.execute("id", Dict{String,Any}("path" => "big.txt"), nothing, nothing)
    @test !r.is_error
    @test occursin("line2000", r.content[1].text)
    @test !occursin("line2001", r.content[1].text)
    @test occursin("of 2500", r.content[1].text)
    @test occursin("Use offset=2001", r.content[1].text)
    @test r.details["truncation"]["outputLines"] == 2000

    r2 = tool.execute("id", Dict{String,Any}("path" => "big.txt", "offset" => 2501), nothing, nothing)
    @test r2.is_error
    @test r2.content[1].text == "Offset 2501 is beyond end of file (2500 lines total)"

    r3 = tool.execute("id", Dict{String,Any}("path" => "big.txt", "offset" => 2495, "limit" => 3), nothing, nothing)
    @test occursin("line2495", r3.content[1].text)
    @test occursin("3 more lines in file", r3.content[1].text)

    longline = joinpath(td, "long.txt")
    write(longline, repeat("x", 60 * 1024) * "\nnext")
    r4 = tool.execute("id", Dict{String,Any}("path" => "long.txt"), nothing, nothing)
    @test occursin("exceeds 50.0KB limit", r4.content[1].text)

    # images
    png = joinpath(td, "x.png")
    write(png, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    r5 = tool.execute("id", Dict{String,Any}("path" => "x.png"), nothing, nothing)
    @test r5.content[2] isa AI.ImageContent
    @test r5.content[2].mime_type == "image/png"
    noimg = CA.read_tool(td; supports_images=false)
    r6 = noimg.execute("id", Dict{String,Any}("path" => "x.png"), nothing, nothing)
    @test length(r6.content) == 1
    @test occursin("does not support images", r6.content[1].text)
end
