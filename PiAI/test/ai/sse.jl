@testset "SSE parser" begin
    raw = "event: message\r\ndata: {\"a\":1}\r\n\r\n: comment\r\ndata: line1\ndata: line2\n\ndata: tail"
    events = AI.SSEEvent[]
    AI.foreach_sse(ev -> push!(events, ev), IOBuffer(raw))
    @test length(events) == 3
    @test events[1].event == "message"
    @test events[1].data == "{\"a\":1}"
    @test events[2].data == "line1\nline2"
    @test events[3].data == "tail"

    token = AI.AbortToken()
    AI.abort!(token)
    seen = AI.SSEEvent[]
    AI.foreach_sse(ev -> push!(seen, ev), IOBuffer(raw); signal=token)
    @test isempty(seen)
end
