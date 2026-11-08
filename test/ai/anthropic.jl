@testset "anthropic-messages provider" begin
    sse = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":10,"output_tokens":0}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """
    mock = start_mock_server(body=sse, headers=Pair{String,String}["content-type" => "text/event-stream"])
    try
        model = AI.Model("claude-test", "Claude Test", "anthropic-messages", "anthropic",
                         "http://127.0.0.1:$(mock.port)"; context_window=200_000, max_tokens=4096,
                         cost=AI.ModelCost(3.0, 15.0, 0.3, 3.75), reasoning=true,
                         compat=Dict{String,Any}("supportsLongCacheRetention" => true))
        ctx = AI.LLMContext(AI.AbstractMessage[
            AI.SystemMessage("rules", sections=Pair{String,Union{String,Nothing}}["docs" => "<docs>d</docs>"]),
            AI.UserMessage("hello"),
            AI.ToolResultMessage("c1", "read", AI.AbstractContent[AI.TextContent("data")]),
        ])
        opts = AI.StreamOptions(api_key="ak", max_retries=0, reasoning="low", cache_retention="long")
        s = AI.stream(model, ctx, opts)
        events = collect(s)
        @test events[1] isa AI.StartEvent
        @test any(e -> e isa AI.TextDeltaEvent, events)
        @test events[end] isa AI.DoneEvent
        @test events[end].reason == "stop"
        @test events[end].message.usage.input == 10
        @test events[end].message.usage.output == 2
        @test events[end].message.usage.cost.total > 0

        body = AI.json_parse(mock.requests[1].payload)
        @test body["stream"] === true
        @test body["model"] == "claude-test"
        @test body["system"][1]["cache_control"]["type"] == "ephemeral"
        @test body["system"][1]["cache_control"]["ttl"] == "1h"
        @test body["thinking"]["type"] == "enabled"
        @test body["thinking"]["budget_tokens"] == 2048
        @test body["messages"][1]["role"] == "user"
        @test any(c -> c["type"] == "tool_result", body["messages"][1]["content"])
        hs = Dict(String(k) => String(v) for (k, v) in mock.requests[1].headers)
        @test lowercase(get(hs, "x-api-key", get(hs, "X-Api-Key", ""))) == "ak"
    finally
        stop_mock_server!(mock)
    end

    # non-2xx becomes an ErrorEvent, not an exception
    mock2 = start_mock_server(status=500, body="boom")
    try
        model = AI.Model("claude-test", "m", "anthropic-messages", "anthropic",
                         "http://127.0.0.1:$(mock2.port)")
        s = AI.stream(model, AI.LLMContext(AI.AbstractMessage[AI.SystemMessage("")]),
                      AI.StreamOptions(api_key="ak", max_retries=0))
        evs = collect(s)
        @test evs[end] isa AI.ErrorEvent
        @test occursin("HTTP 500", evs[end].error.error_message)
    finally
        stop_mock_server!(mock2)
    end
end
