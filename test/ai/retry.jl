@testset "retry and overflow classification" begin
    errmsg(text) = AI.AssistantMessage(AI.AbstractContent[]; stop_reason="error", error_message=text)
    @test !AI.is_retryable_assistant_error(errmsg("429 insufficient_quota"))
    @test AI.is_retryable_assistant_error(errmsg("HTTP 429 rate limit"))
    @test AI.is_retryable_assistant_error(errmsg("overloaded"))
    @test AI.is_retryable_assistant_error(errmsg("stream disconnected"))
    @test !AI.is_retryable_assistant_error(errmsg("invalid request"))
    @test AI.retry_delay_ms(2000, 60_000, 1) == 2000
    @test AI.retry_delay_ms(2000, 60_000, 3) == 8000

    @test AI.is_context_overflow(errmsg("prompt is too long: 300000 tokens"))
    @test !AI.is_context_overflow(errmsg("429 rate limit"))
    ok = AI.AssistantMessage(AI.AbstractContent[]; stop_reason="stop", usage=AI.Usage(input=200_000, cache_read=0))
    @test AI.is_context_overflow(ok; context_window=100_000)
    len = AI.AssistantMessage(AI.AbstractContent[]; stop_reason="length", usage=AI.Usage(input=99_500, output=0))
    @test AI.is_context_overflow(len; context_window=100_000)
end
