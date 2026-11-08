@testset "AgentSession runtime" begin
    td = mktempdir()
    model = AI.Model("faux-1", "faux", "faux", "faux", "http://x"; context_window=128_000)
    settings = Dict{String,Any}(
        "autoCompaction" => false,
        "autoRetry" => true,
        "retry" => Dict{String,Any}("maxRetries" => 3, "baseDelayMs" => 10, "maxDelayMs" => 20),
        "cacheRetention" => "short",
    )
    AI.set_responses!([AI.faux_text("Hello from faux")])
    sm = CA.create_session(td; dir=td, in_memory=true)
    s = CA.create_agent_session(cwd=td, model=model, session_manager=sm, settings=settings,
                                tools_names=String[])
    events = Any[]
    unsub = CA.subscribe(s, ev -> push!(events, ev))
    CA.prompt!(s, "hi")
    @test s.last_assistant !== nothing
    @test s.last_assistant.stop_reason == "stop"
    @test any(ev -> (ev isa NamedTuple ? get(ev, :type, "") : "") == "agent_settled", events)
    @test any(m -> m isa AI.AssistantMessage, CA.build_context(sm))
    state = CA.get_state(s)
    @test state["messageCount"] >= 2
    @test state["sessionId"] == sm.header.id
    CA.close!(s)
    unsub()

    # retry: one transient error then success
    td2 = mktempdir()
    AI.set_responses!([
        AI.faux_assistant_message(AI.AbstractContent[]; stop_reason="error", error_message="HTTP 429 rate limit"),
        AI.faux_text("recovered"),
    ])
    sm2 = CA.create_session(td2; dir=td2, in_memory=true)
    s2 = CA.create_agent_session(cwd=td2, model=model, session_manager=sm2, settings=settings,
                                 tools_names=String[])
    ev2 = Any[]
    CA.subscribe(s2, ev -> push!(ev2, ev))
    CA.prompt!(s2, "retry please")
    @test s2.last_assistant.stop_reason == "stop"
    @test any(ev -> (ev isa NamedTuple ? get(ev, :type, "") : "") == "auto_retry_start", ev2)
    @test any(ev -> (ev isa NamedTuple ? get(ev, :type, "") : "") == "auto_retry_end" && ev.success, ev2)
    CA.close!(s2)

    # retry exhaustion reports finalError
    td3 = mktempdir()
    AI.set_responses!([AI.faux_assistant_message(AI.AbstractContent[]; stop_reason="error",
        error_message="HTTP 503 service unavailable") for _ in 1:5])
    sm3 = CA.create_session(td3; dir=td3, in_memory=true)
    s3 = CA.create_agent_session(cwd=td3, model=model, session_manager=sm3, settings=settings,
                                 tools_names=String[])
    ev3 = Any[]
    CA.subscribe(s3, ev -> push!(ev3, ev))
    CA.prompt!(s3, "fail")
    @test s3.last_assistant.stop_reason == "error"
    @test any(ev -> (ev isa NamedTuple ? get(ev, :type, "") : "") == "auto_retry_end" && !ev.success &&
                     ev.finalError !== nothing, ev3)
    CA.close!(s3)
end
