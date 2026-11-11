@testset "tool operations seams" begin
    @test CA.PowerShellOperations === CA.BashOperations
    td = mktempdir()
    @test CA.DEFAULT_READ_OPERATIONS.access(joinpath(td, "nope")) === false

    custom_bash = CA.BashOperations((command, cwd; on_data=nothing, signal=nothing,
                                     timeout=nothing, env=nothing, shell_path=nothing) ->
        (exit_code=0, output="custom: $(command)", timed_out=false, aborted=false,
         full_output_path=""))
    tool = CA.bash_tool(td; operations=custom_bash)
    r = tool.execute("id", Dict{String,Any}("command" => "hello"), nothing, nothing)
    @test !r.is_error
    @test r.content[1].text == "custom: hello"

    custom_grep = CA.GrepOperations(path -> true,
        (rg, args) -> (stdout="", stderr="", exit_code=1))
    g = CA.grep_tool(td; operations=custom_grep)
    gr = g.execute("id", Dict{String,Any}("pattern" => "x"), nothing, nothing)
    @test !gr.is_error
    @test gr.content[1].text == "No matches found"
end
