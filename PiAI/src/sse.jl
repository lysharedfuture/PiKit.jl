const LOG_TAG = "ai_sse"

struct SSEEvent
    data::String
    event::Union{Nothing,String}
    id::Union{Nothing,String}
end

"""
    foreach_sse(io, f; signal=nothing)

Parse a Server-Sent Events stream line by line. Comments (`:`) are ignored,
multiple `data:` lines are joined with `\n`, and a blank line dispatches the
accumulated event. EOF flushes a pending event.
"""
function foreach_sse(f::Function, io::IO; signal::Union{Nothing,AbortToken}=nothing)
    data = String[]
    event = nothing
    id = nothing
    while true
        signal !== nothing && is_aborted(signal) && return nothing
        line = try
            eof(io) && break
            readline(io)
        catch err
            if signal !== nothing && is_aborted(signal)
                return nothing
            end
            rethrow()
        end
        endswith(line, '\r') && (line = line[1:end-1])
        if isempty(line)
            if !isempty(data) || event !== nothing
                f(SSEEvent(join(data, "\n"), event, id))
                empty!(data)
                event = nothing
                id = nothing
            end
            continue
        end
        startswith(line, ':') && continue
        colon = findfirst(':', line)
        if colon === nothing
            field = line
            value = ""
        else
            field = line[1:colon-1]
            value = colon < lastindex(line) ? line[colon+1:end] : ""
        end
        startswith(value, ' ') && (value = value[2:end])
        if field == "data"
            push!(data, value)
        elseif field == "event"
            event = value
        elseif field == "id"
            id = value
        end
    end
    signal !== nothing && is_aborted(signal) && return nothing
    if !isempty(data) || event !== nothing
        f(SSEEvent(join(data, "\n"), event, id))
    end
    return nothing
end
