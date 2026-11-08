using HTTP

mutable struct MockServer
    server::Any
    port::Int
    requests::Vector{Any}
    status::Int
    headers::Vector{Pair{String,String}}
    body::String
end

function start_mock_server(; status=200, headers=Pair{String,String}[
        "content-type" => "text/event-stream"], body="")
    port = 28_000 + rand(0:2_000)
    mock = MockServer(nothing, port, Any[], status, headers, body)
    handler = function (req)
        payload = try
            raw = req.body
            raw isa AbstractVector{UInt8} ? String(copy(raw)) : String(read(raw))
        catch err
            ""
        end
        push!(mock.requests, (payload=payload, headers=req.headers, target=req.target))
        return HTTP.Response(mock.status, mock.headers, mock.body)
    end
    mock.server = HTTP.serve!(handler, "127.0.0.1", port)
    sleep(0.2)
    return mock
end

function stop_mock_server!(mock)
    try
        close(mock.server)
    catch
    end
    return nothing
end
