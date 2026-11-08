@testset "compaction" begin
    AI.set_responses!([AI.faux_text("## Goal\nsummary")])
    model = AI.Model("faux-1", "faux", "faux", "faux", "http://x"; context_window=2000)
    td = mktempdir()
    sm = CA.create_session(td; dir=td)
    CA.append_message!(sm, AI.SystemMessage("system"))
    for i in 1:4
        CA.append_message!(sm, AI.UserMessage(repeat("message $i ", 100)))
    end
    CA.append_message!(sm, AI.AssistantMessage(AI.AbstractContent[AI.TextContent("last")];
        stop_reason="stop", api="faux", provider="faux", model="faux-1"))

    @test CA.estimate_context_tokens(CA.build_context(sm)) > 0
    @test CA.should_compact(2000, 2000, 100)
    @test !CA.should_compact(100, 2000, 100)

    events = Any[]
    entry = CA.compact!(sm, model, AI.StreamOptions(api_key="x", max_retries=0),
                        CA.RetryPolicy(enabled=false), reason="threshold",
                        keep_recent_tokens=100, emit=ev -> push!(events, ev))
    @test entry !== nothing
    @test any(ev -> ev.type == "compaction_start", events)
    @test any(ev -> ev.type == "compaction_end", events)
    @test any(e -> e isa CA.CompactionEntry, sm.entries)
    ctx = CA.build_context(sm)
    @test any(m -> m isa CA.CompactionSummaryMessage, ctx)
    @test occursin("summary", [m.summary for m in ctx if m isa CA.CompactionSummaryMessage][1])
    CA.close!(sm)

    # failed summarization writes no entry
    AI.set_responses!([AI.faux_assistant_message(AI.AbstractContent[]; stop_reason="error", error_message="nope")])
    sm2 = CA.create_session(td; dir=td)
    CA.append_message!(sm2, AI.UserMessage(repeat("x", 5000)))
    events2 = Any[]
    CA.compact!(sm2, model, AI.StreamOptions(api_key="x", max_retries=0),
                CA.RetryPolicy(enabled=false), keep_recent_tokens=10,
                emit=ev -> push!(events2, ev))
    @test !any(e -> e isa CA.CompactionEntry, sm2.entries)
    @test any(ev -> ev.type == "compaction_end" && ev.errorMessage !== nothing, events2)
    CA.close!(sm2)
end
