@testset "overflow details" begin
    msg = AI.AssistantMessage(AI.AbstractContent[]; stop_reason="error", error_message="input token count exceeds the maximum")
    @test AI.is_context_overflow(msg)
    msg2 = AI.AssistantMessage(AI.AbstractContent[]; stop_reason="error", error_message="Throttling error rate limit")
    @test !AI.is_context_overflow(msg2)
end
