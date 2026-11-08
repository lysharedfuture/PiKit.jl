@testset "tool registry" begin
    td = mktempdir()
    tools = CA.create_tools(td)
    @test [t.name for t in tools] == ["read", "bash", "edit", "write"]
    @test CA.create_tool("edit", td).execution_mode == :sequential
    @test CA.create_tool("write", td).execution_mode == :sequential
    @test CA.create_tool("grep", td).name == "grep"
    @test CA.create_tool("find", td).name == "find"
    @test CA.create_tool("ls", td).name == "ls"
    @test CA.create_tool("powershell", td).name == "powershell"
    @test_throws ArgumentError CA.create_tool("nope", td)
    @test_throws ArgumentError CA.create_tools(td; names=["nope"])

    all = CA.create_tools(td; names=["read", "bash", "edit", "write", "grep", "find", "ls"])
    @test length(all) == 7
    @test CA.TOOL_SNIPPETS["read"] == "Read file contents"
end
