@testset "faux provider" begin
    AI.register_faux_provider!(responses=[AI.faux_text("Hello from faux")])
    model = AI.find_model("faux/faux-1")
    @test model !== nothing
    s = AI.stream(model, AI.LLMContext(AI.AbstractMessage[AI.SystemMessage(""), AI.UserMessage("hi")]))
    events = collect(s)
    @test events[1] isa AI.StartEvent
    @test events[2] isa AI.TextStartEvent
    @test any(e -> e isa AI.TextDeltaEvent, events)
    @test events[end-1] isa AI.TextEndEvent
    @test events[end] isa AI.DoneEvent
    @test events[end].reason == "stop"
    @test AI.faux_call_count() == 1

    AI.set_responses!(Any[])
    s2 = AI.stream(model, AI.LLMContext(AI.AbstractMessage[AI.SystemMessage("")]))
    events2 = collect(s2)
    @test events2[end] isa AI.ErrorEvent
    @test occursin("No faux response queued", events2[end].error.error_message)

    AI.set_responses!([AI.faux_tool_call("bash", Dict{String,Any}("command" => "echo hi"))])
    s3 = AI.stream(model, AI.LLMContext(AI.AbstractMessage[AI.SystemMessage("")]))
    events3 = collect(s3)
    @test any(e -> e isa AI.ToolCallStartEvent, events3)
    @test any(e -> e isa AI.ToolCallEndEvent, events3)
    @test events3[end].reason == "toolUse"
end
