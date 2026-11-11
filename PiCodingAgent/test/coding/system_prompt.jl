@testset "system prompt" begin
    td = mktempdir()
    agent_dir = joinpath(td, "agent")
    mkpath(agent_dir)
    write(joinpath(td, "AGENTS.md"), "project rules")
    tools = [CA.create_tool("read", td), CA.create_tool("bash", td)]
    sections = CA.build_system_sections(td; tools=tools, agent_dir=agent_dir)
    names = [p.first for p in sections]
    @test names == ["preamble", "tools", "rules", "docs", "project_context", "cwd"]
    @test sections[2].second isa String && startswith(sections[2].second, "<tools>")
    @test occursin("- read: Read file contents", sections[2].second)
    @test occursin("Additional tools may be available.", sections[2].second)
    @test startswith(sections[3].second, "<rules>")
    @test occursin("Be concise in your responses", sections[3].second)
    @test occursin("project rules", sections[5].second)
    @test endswith(sections[5].second, "</project_context>")
    @test sections[6].second == "<cwd>\n$(replace(abspath(td), '\\' => '/'))\n</cwd>"

    # append/system overrides and no-context option
    mkpath(joinpath(td, ".pikit"))
    write(joinpath(td, ".pikit", "SYSTEM.md"), "custom preamble")
    write(joinpath(td, ".pikit", "APPEND_SYSTEM.md"), "extra")
    s2 = CA.build_system_sections(td; tools=tools, agent_dir=agent_dir, trusted=true,
                                  append_system_prompt="flag", no_context_files=true)
    @test s2[1].second == "custom preamble"
    @test occursin("flag", s2[5].second) && occursin("extra", s2[5].second)
    @test !("project_context" in [p.first for p in s2])

    @test_throws ArgumentError CA.wrap_section("preamble", "x")
    @test_throws ArgumentError CA.wrap_section("bad name!", "x")
end
