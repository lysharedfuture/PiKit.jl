@testset "bash tool" begin
    td = mktempdir()
    tool = CA.bash_tool(td)
    r = tool.execute("id", Dict{String,Any}("command" => "echo hi"), nothing, nothing)
    @test !r.is_error
    @test r.content[1].text == "hi"

    r2 = tool.execute("id", Dict{String,Any}("command" => "exit 3"), nothing, nothing)
    @test r2.is_error
    @test occursin("Command exited with code 3", r2.content[1].text)

    started = time()
    r3 = tool.execute("id", Dict{String,Any}("command" => "sleep 5", "timeout" => 0.1), nothing, nothing)
    @test r3.is_error
    @test occursin("Command timed out after 0.1 seconds", r3.content[1].text)
    @test time() - started < 3.0

    r4 = tool.execute("id", Dict{String,Any}("command" => "echo out; echo err 1>&2"), nothing, nothing)
    @test occursin("out", r4.content[1].text) && occursin("err", r4.content[1].text)

    r5 = tool.execute("id", Dict{String,Any}("command" => "x", "timeout" => -1), nothing, nothing)
    @test r5.is_error
    @test occursin("finite number", r5.content[1].text)

    # output truncation + full output path
    r6 = tool.execute("id", Dict{String,Any}("command" => "seq 1 3000"), nothing, nothing)
    @test occursin("Full output:", r6.content[1].text)
    @test r6.details !== nothing
    @test isfile(r6.details["fullOutputPath"])

    # abort kills the process tree
    token = AI.AbortToken()
    task = @async tool.execute("id", Dict{String,Any}("command" => "sleep 5"), token, nothing)
    sleep(0.2)
    AI.abort!(token)
    r7 = fetch(task)
    @test r7.is_error
    @test occursin("Command aborted", r7.content[1].text)
end
