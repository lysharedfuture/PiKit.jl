@testset "event stream" begin
    model = AI.Model("m", "m", "faux", "faux", "http://x")
    s = AI.AssistantMessageEventStream() do stream
        msg = AI.empty_assistant(model)
        AI.push_event!(stream, AI.StartEvent(msg))
        msg.stop_reason = "stop"
        AI.push_event!(stream, AI.DoneEvent("stop", msg))
    end
    events = collect(s)
    @test length(events) == 2
    @test events[1] isa AI.StartEvent
    @test events[2] isa AI.DoneEvent
    final = AI.result(s)
    @test final.stop_reason == "stop"
    @test eltype(AI.AssistantMessageEventStream) == AI.AbstractAssistantMessageEvent
end
