const LOG_TAG = "ai_abort"

"""
    abort_on!(token, io)

Register a callback that closes `io`, unblocking a pending `readline`.
Returns the token for chaining.
"""
function abort_on!(token::AbortToken, io::IO)
    on_abort(token) do
        try
            isopen(io) && close(io)
        catch err
            @debug "closing aborted IO failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
    end
    return token
end

"""
    sleep_abortable(seconds, signal; poll=0.02)

Sleep while polling an abort token. Returns `true` if aborted.
"""
function sleep_abortable(seconds::Real, signal::Union{Nothing,AbortToken}; poll=0.02)
    signal === nothing && (sleep(seconds); return false)
    deadline = time() + seconds
    while time() < deadline
        is_aborted(signal) && return true
        sleep(min(poll, max(0.0, deadline - time())))
    end
    return is_aborted(signal)
end
