@testset "session v3" begin
    td = mktempdir()
    sm = CA.create_session(td; dir=td)
    @test sm.header.version == 3
    CA.append_message!(sm, AI.UserMessage("hello"))
    a = AI.AssistantMessage(AI.AbstractContent[AI.TextContent("hi")];
        api="faux", provider="faux", model="faux-1", stop_reason="stop")
    CA.append_message!(sm, a)
    CA.append_message!(sm, AI.ToolResultMessage("c1", "read", AI.AbstractContent[AI.TextContent("data")]))
    path = sm.path
    CA.close!(sm)
    sm2 = CA.load_session(path)
    @test length(sm2.entries) == 3
    ctx = CA.build_context(sm2)
    @test length(ctx) == 3
    @test ctx[1] isa AI.UserMessage
    @test ctx[2] isa AI.AssistantMessage
    @test ctx[3] isa AI.ToolResultMessage

    # pending assistant is rejected
    @test_throws ArgumentError CA.append_message!(sm2, AI.AssistantMessage(AI.AbstractContent[]; stop_reason="pending"))

    # unknown entries stay on the tree without breaking the branch
    last_id = sm2.leaf_id
    open(path, "a") do io
        println(io, "{\"type\":\"custom\",\"id\":\"zzzzzzzz\",\"parentId\":\"$(last_id)\",\"timestamp\":\"2026-01-01T00:00:00.000Z\",\"customType\":\"x\",\"data\":1}")
    end
    sm3 = CA.load_session(path)
    @test sm3.entries[end] isa CA.UnknownEntry
    @test length(CA.build_context(sm3)) == 3

    # fork copies the active branch and remaps ids
    fork = CA.fork_session(sm2, sm2.entries[2].id, td; dir=td)
    @test length(fork.entries) == 2
    @test fork.header.parent_session == path
    @test length(CA.build_context(fork)) == 2
    @test fork.entries[2].id != sm2.entries[2].id

    # context_edit with replacement=null omits the target and its tool result
    sm4 = CA.create_session(td; dir=td)
    CA.append_message!(sm4, AI.UserMessage("q"))
    ast = AI.AssistantMessage(AI.AbstractContent[AI.ToolCall("call-1", "read", Dict{String,Any}())];
        stop_reason="toolUse", api="faux", provider="faux", model="faux-1")
    CA.append_message!(sm4, ast)
    CA.append_message!(sm4, AI.ToolResultMessage("call-1", "read", AI.AbstractContent[AI.TextContent("r")]))
    target_id = sm4.entries[2].id
    CA.append_entry!(sm4, CA.ContextEditEntry("", sm4.leaf_id, CA.now_iso(), target_id, nothing, Dict{String,Any}()))
    ctx4 = CA.build_context(sm4)
    @test length(ctx4) == 1
    @test ctx4[1] isa AI.UserMessage

    # compaction rebuild keeps summary + kept messages
    sm5 = CA.create_session(td; dir=td)
    CA.append_message!(sm5, AI.UserMessage("old"))
    CA.append_message!(sm5, AI.UserMessage("keep"))
    first_kept = sm5.entries[end].id
    CA.append_entry!(sm5, CA.CompactionEntry("", sm5.leaf_id, CA.now_iso(), "summary text",
        first_kept, 100, nothing, nothing, nothing, nothing, Dict{String,Any}()))
    ctx5 = CA.build_context(sm5)
    @test any(m -> m isa CA.CompactionSummaryMessage, ctx5)
    @test any(m -> m isa AI.UserMessage && m.content == "keep", ctx5)
    @test !any(m -> m isa AI.UserMessage && m.content == "old", ctx5)

    CA.close!(sm2); CA.close!(sm3); CA.close!(fork); CA.close!(sm4); CA.close!(sm5)
end
