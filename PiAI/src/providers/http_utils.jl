const LOG_TAG = "ai_http"

function header_dict(headers)
    d = Dict{String,String}()
    for (k, v) in headers
        d[String(k)] = String(v)
    end
    return d
end

function merged_headers(defaults::Dict{String,String}, overrides)::Dict{String,String}
    out = copy(defaults)
    for (k, v) in overrides
        if v === nothing
            delete!(out, String(k))
        else
            out[String(k)] = String(v)
        end
    end
    return out
end

"""
    open_http_stream(f, method, url, headers, body; timeout_ms, signal)

Open a streaming HTTP response and call `f(io, status, response_headers)`.
The body stream is closed when `f` returns.
"""
function open_http_stream(f::Function, method, url, headers, body; timeout_ms=nothing,
                          signal::Union{Nothing,AbortToken}=nothing)
    timeout = timeout_ms === nothing ? 600_000 : timeout_ms
    response = HTTP.request(method, url; headers=headers, body=body, retry=false,
                            status_exception=false, readtimeout=timeout,
                            connect_timeout=min(30_000, timeout), stream=true)
    raw = response.body
    io = raw isa AbstractVector{UInt8} ? IOBuffer(raw) : raw
    signal !== nothing && abort_on!(signal, io)
    try
        return f(io, response.status, header_dict(response.headers))
    finally
        if io !== raw
            try
                isopen(io) && close(io)
            catch err
                @debug "closing response stream failed" _group=LOG_TAG exception=(err, catch_backtrace())
            end
        end
    end
end

function read_error_body(io, limit=64 * 1024)
    buf = IOBuffer()
    try
        while !eof(io) && position(buf) < limit
            write(buf, readavailable(io))
        end
    catch err
        @debug "error body read failed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    return String(take!(buf))
end

function retry_after_ms(headers; cap_ms=60_000)
    v = get(headers, "retry-after", get(headers, "Retry-After", nothing))
    v === nothing && return nothing
    if occursin(r"^\d+$", v)
        return min(parse(Int, v) * 1000, cap_ms)
    end
    return nothing
end

function backoff_ms(attempt::Int; cap_ms=60_000)
    base = 1000 * 2^(attempt - 1)
    jitter = 0.8 + rand() * 0.4
    return Int(min(base * jitter, cap_ms))
end

function should_provider_retry(status)
    return status == 429 || status == 500 || status == 502 || status == 503 || status == 504 ||
           status == 520 || status == 524
end

function sse_json(data)
    data == "[DONE]" && return nothing
    return json_parse(data)
end
