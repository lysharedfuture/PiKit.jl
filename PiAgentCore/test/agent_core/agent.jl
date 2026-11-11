@testset "Agent lifecycle" begin
    AI.set_responses!([AI.faux_text("a"), AI.faux_text("b")])
    model = AI.find_model("faux/faux-1")
    agent = AC.Agent(model=model, tools=AC.Tool[], system_prompt="sys")
    events = Any[]
    unsub = AC.subscribe(agent, ev -> push!(events, ev))
    AC.prompt!(agent, "hello")
    @test !agent.state.is_streaming
    @test agent.state.messages[end] isa AI.AssistantMessage
    @test events[1] isa AC.AgentStartEvent
    @test events[end] isa AC.AgentEndEvent
    @test AC.system_prompt(agent) == "sys"
    unsub()

    # second prompt works and status is idle
    AC.prompt!(agent, "again")
    @test length([m for m in agent.state.messages if m isa AI.UserMessage]) == 2

    # reset keeps system baseline
    AC.reset!(agent)
    @test length(agent.state.messages) == 1
    @test agent.state.messages[1] isa AI.SystemMessage

    # abort token semantics
    token = AI.AbortToken()
    fired = Ref(0)
    AI.on_abort(token) do
        fired[] += 1
    end
    AI.on_abort(token) do
        fired[] += 1
    end
    AI.abort!(token)
    AI.abort!(token)
    @test fired[] == 2
    @test AI.is_aborted(token)
    late = Ref(false)
    AI.on_abort(token) do
        late[] = true
    end
    @test late[]

    # subscribe removal
    called = Ref(0)
    unsub2 = AC.subscribe(agent, ev -> (called[] += 1))
    unsub2()
    unsub2()
    AI.set_responses!([AI.faux_text("c")])
    AC.prompt!(agent, "third")
    @test called[] == 0
end
