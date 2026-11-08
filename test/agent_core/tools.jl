function _call(name, id)
    return AI.ToolCall(id, name, Dict{String,Any}("x" => 1))
end

@testset "agent loop tools" begin
    calls = [AI.ToolCall("slow", "slow", Dict{String,Any}("x" => 1)),
             AI.ToolCall("fast", "fast", Dict{String,Any}("x" => 1))]
    AI.set_responses!([
        AI.faux_assistant_message(AI.AbstractContent[calls...]; stop_reason="toolUse"),
        AI.faux_text("done"),
    ])
    model = AI.find_model("faux/faux-1")
    made = String[]
    tools = [
        AC.Tool("slow", "slow", Dict{String,Any}("type" => "object"),
                (id, args, sig, upd) -> (sleep(0.15); push!(made, "slow"); AC.ToolResult([AI.TextContent("slow")])),
                execution_mode=:parallel),
        AC.Tool("fast", "fast", Dict{String,Any}("type" => "object"),
                (id, args, sig, upd) -> (push!(made, "fast"); AC.ToolResult([AI.TextContent("fast")])),
                execution_mode=:parallel),
    ]
    ctx = AC.AgentContext(AI.AbstractMessage[AI.SystemMessage("sys")], tools)
    config = AC.AgentLoopConfig(model=model, stream_fn=AI.stream)
    events = Any[]
    produced = AC.run_agent_loop(AI.AbstractMessage[AI.UserMessage("go")], ctx,
                                 config, nothing, ev -> push!(events, ev))
    ends = [ev for ev in events if ev isa AC.ToolExecutionEndEvent]
    @test [e.tool_name for e in ends] == ["fast", "slow"]
    turns = [ev for ev in events if ev isa AC.TurnEndEvent]
    @test [r.tool_name for r in turns[1].tool_results] == ["slow", "fast"]
    @test produced[end] isa AI.AssistantMessage

    # length stop: tools are reported as failed and never executed
    executed = Ref(false)
    AI.set_responses!([AI.faux_assistant_message(AI.AbstractContent[_call("t", "c")]; stop_reason="length")])
    t = AC.Tool("t", "", Dict{String,Any}("type" => "object"),
                (id, args, sig, upd) -> (executed[] = true; AC.ToolResult([AI.TextContent("x")])))
    ctx2 = AC.AgentContext(AI.AbstractMessage[AI.SystemMessage("")], [t])
    evs2 = Any[]
    AC.run_agent_loop(AI.AbstractMessage[AI.UserMessage("go")], ctx2, config, nothing, ev -> push!(evs2, ev))
    @test !executed[]
    result_msgs = [ev for ev in evs2 if ev isa AC.MessageEndEvent && ev.message isa AI.ToolResultMessage]
    @test !isempty(result_msgs)
    @test all(ev -> ev.message.is_error, result_msgs)

    # before_tool_call block prevents execution
    executed[] = false
    AI.set_responses!([AI.faux_assistant_message(AI.AbstractContent[_call("t", "c")]; stop_reason="toolUse"),
                       AI.faux_text("done")])
    config_block = AC.AgentLoopConfig(model=model, stream_fn=AI.stream,
        before_tool_call=(ctx, sig) -> (block=true, reason="nope", terminate=false))
    evs3 = Any[]
    AC.run_agent_loop(AI.AbstractMessage[AI.UserMessage("go")], ctx2, config_block, nothing, ev -> push!(evs3, ev))
    @test !executed[]
    blocked = [ev for ev in evs3 if ev isa AC.MessageEndEvent && ev.message isa AI.ToolResultMessage]
    @test !isempty(blocked) && blocked[1].message.is_error
end
