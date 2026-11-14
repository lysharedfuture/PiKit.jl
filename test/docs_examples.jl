@testset "documented examples" begin
    import PiAISDK
    import PiAgentCore
    import PiCodingAgent

    model = PiAISDK.find_model("faux/faux-1")
    @test model !== nothing

    # docs/src/index.md — PiAISDK
    PiAISDK.set_responses!([PiAISDK.faux_text("hello")])
    stream = PiAISDK.stream(model,
        PiAISDK.LLMContext(PiAISDK.AbstractMessage[PiAISDK.UserMessage("hi")]))
    message = PiAISDK.result(stream)
    @test message isa PiAISDK.AssistantMessage
    @test message.content[1].text == "hello"

    # docs/src/index.md — PiAgentCore
    PiAISDK.set_responses!([PiAISDK.faux_text("done")])
    agent = PiAgentCore.Agent(model=model, tools=PiAgentCore.Tool[], system_prompt="be brief")
    events = String[]
    unsubscribe = PiAgentCore.subscribe(agent, ev -> push!(events, PiAgentCore.event_type(ev)))
    PiAgentCore.prompt!(agent, "hello")
    unsubscribe()
    @test first(events) == "agent_start"
    @test last(events) == "agent_end"
    @test agent.state.messages[end] isa PiAISDK.AssistantMessage

    # docs/src/index.md — PiCodingAgent
    cwd = mktempdir()
    PiAISDK.set_responses!([PiAISDK.faux_text("done")])
    manager = PiCodingAgent.create_session(cwd; dir=cwd, in_memory=true)
    session = PiCodingAgent.create_agent_session(cwd=cwd, model=model,
        session_manager=manager,
        settings=Dict{String,Any}("autoCompaction" => false), tools_names=String[])
    PiCodingAgent.prompt!(session, "hi")
    @test session.last_assistant.content[1].text == "done"
    PiCodingAgent.close!(session)

    # docs/src/pikit.md — aliases and parsing
    @test PiKit.AI === PiAISDK
    @test PiKit.AgentCore === PiAgentCore
    @test PiKit.CodingAgent === PiCodingAgent
    opts = PiKit.parse_cli(["-p", "--model", "faux/faux-1", "hello"])
    @test PiKit.initial_prompt(opts) == "hello"
end
