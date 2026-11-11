@testset "CLI parsing" begin
    opts = PiKit.parse_cli(["-p", "--model", "faux/faux-1", "--thinking", "low", "hello", "world"])
    @test opts.print
    @test opts.mode == "text"
    @test opts.model == "faux/faux-1"
    @test PiKit.initial_prompt(opts) == "hello world"

    opts2 = PiKit.parse_cli(["--", "--not-an-option", "x"])
    @test PiKit.initial_prompt(opts2) == "--not-an-option x"

    td = mktempdir()
    f = joinpath(td, "prompt.txt")
    write(f, "from file")
    opts3 = PiKit.parse_cli(["@$(f)"])
    @test PiKit.initial_prompt(opts3) == "from file"

    @test_throws PiKit.CLIError PiKit.parse_cli(["--thinking", "nope"])
    @test_throws PiKit.CLIError PiKit.parse_cli(["--session-id", "bad id"])
    @test_throws PiKit.CLIError PiKit.parse_cli(["--mode", "nope"])
    @test_throws PiKit.CLIError PiKit.parse_cli(["--unknown"])
    @test_throws PiKit.CLIError PiKit.parse_cli(["--mode", "rpc", "@$(f)"])

    @test PiKit.resolve_tool_names(PiKit.parse_cli(String[])) == ["read", "bash", "edit", "write"]
    @test PiKit.resolve_tool_names(PiKit.parse_cli(["--tools", "+grep,-bash"])) == ["read", "edit", "write", "grep"]
    @test PiKit.resolve_tool_names(PiKit.parse_cli(["--tools", "read,ls"])) == ["read", "ls"]
    @test PiKit.resolve_tool_names(PiKit.parse_cli(["--no-tools"])) == String[]
    @test PiKit.resolve_tool_names(PiKit.parse_cli(["--exclude-tools", "*"])) == String[]
    @test occursin("faux/faux-1", PiKit.list_models_text("faux"))
end
