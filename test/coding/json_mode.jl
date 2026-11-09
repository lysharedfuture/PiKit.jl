@testset "documented JSON events" begin
    docs = read(joinpath(dirname(@__DIR__), "..", "docs", "src", "json.md"), String)
    documented = String[]
    for line in split(docs, '\n')
        m = match(r"^\|\s*`([a-z_]+)`\s*\|", line)
        m === nothing && continue
        m.captures[1] == "type" && continue
        push!(documented, m.captures[1])
    end
    @test !isempty(documented)

    model = AI.Model("m", "m", "faux", "faux", "http://x")
    user = AI.UserMessage("hi")
    assistant = AI.AssistantMessage(AI.AbstractContent[AI.TextContent("x")];
        stop_reason="stop", api="faux", provider="faux", model="m")
    tool_result = AI.ToolResultMessage("c1", "read", AI.AbstractContent[AI.TextContent("r")])
    assistant_event = AI.TextDeltaEvent(1, "x", assistant)
    events = Any[
        AC.AgentStartEvent(),
        AC.AgentEndEvent(AI.AbstractMessage[user, assistant]),
        AC.TurnStartEvent(),
        AC.TurnEndEvent(assistant, AI.ToolResultMessage[tool_result]),
        AC.MessageStartEvent(user),
        AC.MessageUpdateEvent(assistant, assistant_event),
        AC.MessageEndEvent(assistant),
        AC.ToolExecutionStartEvent("c1", "read", Dict{String,Any}()),
        AC.ToolExecutionUpdateEvent("c1", "read", Dict{String,Any}(), Dict{String,Any}()),
        AC.ToolExecutionEndEvent("c1", "read", Dict{String,Any}(), Dict{String,Any}(), false, 1),
        (type="queue_update", steering=String[], followUp=String[]),
        (type="thinking_level_changed", level="low"),
        (type="session_info_changed", name="n"),
        (type="entry_appended", entry=Dict{String,Any}()),
        (type="compaction_start", reason="manual"),
        (type="compaction_end", reason="manual", result=nothing, aborted=false, willRetry=false,
         errorMessage=nothing),
        (type="auto_retry_start", attempt=1, maxAttempts=3, delayMs=1, errorMessage="e"),
        (type="auto_retry_end", success=true, attempt=1, finalError=nothing),
        (type="summarization_retry_start", attempt=1, delayMs=1, errorMessage="e"),
        (type="summarization_retry_end", success=false, attempt=1),
        (type="agent_settled", aborted=false),
    ]
    produced = Set{String}(CA.json_mode_event(ev)["type"] for ev in events)
    missing = setdiff(Set(documented), produced)
    @test isempty(missing)
end
