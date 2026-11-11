@testset "agent loop text" begin
    AI.set_responses!([AI.faux_text("Hello")])
    model = AI.find_model("faux/faux-1")
    ctx = AC.AgentContext(AI.AbstractMessage[AI.SystemMessage("sys")], AC.Tool[])
    config = AC.AgentLoopConfig(model=model, stream_fn=AI.stream,
                                convert_to_llm=AC.default_convert_to_llm)
    events = Any[]
    produced = AC.run_agent_loop(AI.AbstractMessage[AI.UserMessage("hi")], ctx,
                                 config, nothing, ev -> push!(events, ev))
    types = [AC.event_type(ev) for ev in events]
    @test types[1] == "agent_start"
    @test types[end] == "agent_end"
    @test "turn_start" in types
    @test count(==("message_start"), types) == 2
    @test count(==("message_end"), types) == 2
    @test events[end].messages == produced
    assistant = produced[end]
    @test assistant isa AI.AssistantMessage
    @test assistant.stop_reason == "stop"
    @test any(c -> c isa AI.TextContent && c.text == "Hello", assistant.content)
    @test any(ev -> ev isa AC.MessageUpdateEvent && ev.assistant_message_event isa AI.TextStartEvent, events)
end
