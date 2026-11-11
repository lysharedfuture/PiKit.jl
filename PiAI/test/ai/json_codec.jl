@testset "AI JSON codec" begin
    sys = AI.SystemMessage("base";
        sections=Pair{String,Union{String,Nothing}}["rules" => "<rules>r</rules>", "gone" => nothing],
        tools_added=[Dict{String,Any}("name" => "read")],
        extra=Dict{String,Any}("rawStopReason" => "x"))
    j = AI.message_to_json(sys)
    @test j["role"] == "system"
    @test j["rawStopReason"] == "x"
    parsed = AI.json_parse(AI.json_write(j))
    @test first.(parsed["sections"]) == ["rules", "gone"]
    @test parsed["sections"][2][2] === nothing
    sys2 = AI.message_from_json(parsed)
    @test sys2 isa AI.SystemMessage
    @test sys2.sections[1] == ("rules" => "<rules>r</rules>")
    @test sys2.tools_added[1]["name"] == "read"

    user = AI.UserMessage("hello")
    @test AI.message_from_json(AI.json_parse(AI.json_write(AI.message_to_json(user)))).content == "hello"

    call = AI.ToolCall("c1", "read", Dict{String,Any}("path" => "a"); thought_signature="s")
    assistant = AI.AssistantMessage(AI.AbstractContent[AI.TextContent("hi"), call];
        api="faux", provider="faux", model="m", stop_reason="toolUse",
        usage=AI.Usage(input=10, output=2, total_tokens=12), thinking_level="low")
    aj = AI.message_to_json(assistant)
    @test aj["stopReason"] == "toolUse"
    @test aj["content"][2]["thoughtSignature"] == "s"
    @test !haskey(AI.to_json(AI.TextContent("x")), "textSignature")
    round = AI.message_from_json(AI.json_parse(AI.json_write(aj)))
    @test round.stop_reason == "toolUse"
    @test round.content[2] isa AI.ToolCall

    tr = AI.ToolResultMessage("c1", "read", AI.AbstractContent[AI.TextContent("data")];
        usage=AI.Usage(input=1, output=1, total_tokens=2), is_error=true)
    trj = AI.message_to_json(tr)
    @test trj["isError"] === true
    @test trj["usage"]["totalTokens"] == 2
    tr2 = AI.message_from_json(AI.json_parse(AI.json_write(trj)))
    @test tr2.is_error
    @test tr2.usage !== nothing

    @test_throws ArgumentError AI.message_from_json(Dict{String,Any}("role" => "nope"))
end
