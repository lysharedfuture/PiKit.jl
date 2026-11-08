@testset "CLI parsing" begin
    opts = CA.parse_cli(["-p", "--model", "faux/faux-1", "--thinking", "low", "hello", "world"])
    @test opts.print
    @test opts.mode == "text"
    @test opts.model == "faux/faux-1"
    @test CA.initial_prompt(opts) == "hello world"

    opts2 = CA.parse_cli(["--", "--not-an-option", "x"])
    @test CA.initial_prompt(opts2) == "--not-an-option x"

    td = mktempdir()
    f = joinpath(td, "prompt.txt")
    write(f, "from file")
    opts3 = CA.parse_cli(["@$(f)"])
    @test CA.initial_prompt(opts3) == "from file"

    @test_throws CA.CLIError CA.parse_cli(["--thinking", "nope"])
    @test_throws CA.CLIError CA.parse_cli(["--session-id", "bad id"])
    @test_throws CA.CLIError CA.parse_cli(["--mode", "nope"])
    @test_throws CA.CLIError CA.parse_cli(["--unknown"])
    @test_throws CA.CLIError CA.parse_cli(["--mode", "rpc", "@$(f)"])

    @test CA.resolve_tool_names(CA.parse_cli(String[])) == ["read", "bash", "edit", "write"]
    @test CA.resolve_tool_names(CA.parse_cli(["--tools", "+grep,-bash"])) == ["read", "edit", "write", "grep"]
    @test CA.resolve_tool_names(CA.parse_cli(["--tools", "read,ls"])) == ["read", "ls"]
    @test CA.resolve_tool_names(CA.parse_cli(["--no-tools"])) == String[]
    @test CA.resolve_tool_names(CA.parse_cli(["--exclude-tools", "*"])) == String[]
    @test occursin("faux/faux-1", CA.list_models_text("faux"))
end
