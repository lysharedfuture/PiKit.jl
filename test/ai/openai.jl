@testset "openai-completions provider" begin
    sse = """
    data: {"id":"r1","model":"gpt-test","choices":[{"delta":{"content":"Hi"}}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}

    data: [DONE]

    """
    mock = start_mock_server(body=sse, headers=Pair{String,String}["content-type" => "text/event-stream"])
    try
        model = AI.Model("gpt-test", "GPT Test", "openai-completions", "openai",
                         "http://127.0.0.1:$(mock.port)"; context_window=128_000,
                         max_tokens=1024, cost=AI.ModelCost(1.0, 2.0, 0.5, 0.0),
                         compat=Dict{String,Any}("supportsUsageInStreaming" => true))
        ctx = AI.LLMContext(AI.AbstractMessage[
            AI.SystemMessage("be brief"),
            AI.UserMessage("hello"),
            AI.AssistantMessage(AI.AbstractContent[AI.ToolCall("c1", "bash", Dict{String,Any}("command" => "ls"))];
                stop_reason="toolUse", api="openai-completions", provider="openai", model="gpt-test"),
            AI.ToolResultMessage("c1", "bash", AI.AbstractContent[AI.TextContent("out")]),
        ])
        opts = AI.StreamOptions(api_key="sk-test", max_retries=0, session_id="sess-1")
        s = AI.stream(model, ctx, opts)
        events = collect(s)
        types = [typeof(e) for e in events]
        @test types[1] == AI.StartEvent
        @test AI.TextStartEvent in types
        @test AI.TextDeltaEvent in types
        @test AI.TextEndEvent in types
        @test events[end] isa AI.DoneEvent
        @test events[end].reason == "stop"
        @test events[end].message.usage.input == 3
        @test events[end].message.usage.total_tokens == 5
        @test events[end].message.usage.cost.total > 0

        @test length(mock.requests) == 1
        body = AI.json_parse(mock.requests[1].payload)
        @test body["model"] == "gpt-test"
        @test body["stream"] === true
        @test body["prompt_cache_key"] == "sess-1"
        @test body["stream_options"]["include_usage"] === true
        @test body["tools"] isa Vector          # tool history forces an empty/!empty tools array
        @test body["messages"][1]["role"] == "system"
        tool_msg = [m for m in body["messages"] if m["role"] == "tool"][1]
        @test tool_msg["tool_call_id"] == "c1"
        hs = Dict(String(k) => String(v) for (k, v) in mock.requests[1].headers)
        auth = lowercase(get(hs, "authorization", get(hs, "Authorization", "")))
        @test occursin("sk-test", auth)
    finally
        stop_mock_server!(mock)
    end
end
