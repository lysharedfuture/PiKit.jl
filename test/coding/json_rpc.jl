function capture_output(f; input=nothing)
    out_path = tempname()
    open(out_path, "w") do out
        redirect_stdout(out) do
            if input === nothing
                f()
            else
                in_path = tempname()
                open(in_path, "w") do fio
                    write(fio, input)
                end
                open(in_path, "r") do inp
                    redirect_stdin(inp) do
                        f()
                    end
                end
            end
        end
    end
    return read(out_path, String)
end

@testset "JSON and RPC modes" begin
    td = mktempdir()
    model = AI.Model("faux-1", "faux", "faux", "faux", "http://x")
    settings = Dict{String,Any}("autoCompaction" => false, "autoRetry" => false)
    AI.set_responses!([AI.faux_text("Hello from faux")])
    sm = CA.create_session(td; dir=td, in_memory=true)
    s = CA.create_agent_session(cwd=td, model=model, session_manager=sm, settings=settings,
                                tools_names=String[])
    text = capture_output(() -> PiKit.run_json_mode(s, "hi"))
    lines = [line for line in split(text, '\n') if !isempty(line)]
    @test !isempty(lines)
    first = AI.json_parse(lines[1])
    @test first["type"] == "session"
    parsed = [AI.json_parse(line) for line in lines[2:end]]
    types = [d["type"] for d in parsed]
    for expected in ("agent_start", "turn_start", "message_start", "message_end",
                     "turn_end", "agent_end", "agent_settled")
        @test expected in types
    end
    updates = [d for d in parsed if d["type"] == "message_update"]
    @test !isempty(updates)
    @test all(d -> !haskey(d["assistantMessageEvent"], "partial"), updates)
    @test all(d -> haskey(d, "usage"), updates)
    CA.close!(s)

    # RPC get_state
    AI.set_responses!([AI.faux_text("rpc")])
    sm2 = CA.create_session(td; dir=td, in_memory=true)
    s2 = CA.create_agent_session(cwd=td, model=model, session_manager=sm2, settings=settings,
                                 tools_names=String[])
    rpc_text = capture_output(() -> PiKit.run_rpc_mode(s2);
                              input="{\"id\":\"1\",\"type\":\"get_state\"}\n")
    resp = AI.json_parse(strip(rpc_text))
    @test resp["type"] == "response"
    @test resp["command"] == "get_state"
    @test resp["success"] === true
    @test haskey(resp["data"], "sessionId")
    CA.close!(s2)

    # RPC unsupported command
    sm3 = CA.create_session(td; dir=td, in_memory=true)
    s3 = CA.create_agent_session(cwd=td, model=model, session_manager=sm3, settings=settings,
                                 tools_names=String[])
    rpc_text2 = capture_output(() -> PiKit.run_rpc_mode(s3);
                               input="{\"id\":\"2\",\"type\":\"nope\"}\n")
    resp2 = AI.json_parse(strip(rpc_text2))
    @test resp2["success"] === false
    @test occursin("unsupported command", resp2["error"])
    CA.close!(s3)
end
