const LOG_TAG = "ai_overflow"

const OVERFLOW_PATTERNS = [
    r"prompt too long"i, r"request_too_large"i, r"exceeds the context window"i,
    r"maximum context length"i, r"input token count.*exceeds"i,
    r"context window.*exceed"i, r"context_length_exceeded"i, r"prompt is too long"i,
    r"too many tokens"i, r"\b413\b",
]

const OVERFLOW_EXCLUSIONS = [r"rate.?limit"i, r"too many requests"i, r"Throttling error"i]

function _assistant_text(msg::AssistantMessage)
    io = IOBuffer()
    msg.error_message === nothing || print(io, msg.error_message, ' ')
    for c in msg.content
        c isa TextContent && print(io, c.text, ' ')
    end
    return String(take!(io))
end

"""
    is_context_overflow(msg::AssistantMessage; context_window=nothing) -> Bool

Return `true` when `msg` failed because the prompt exceeded the model's
context window. Checks the error text of `"error"` messages (ignoring
rate-limit wording) and, when `context_window` is given, the reported input
tokens of `"stop"` and `"length"` messages.
"""
function is_context_overflow(msg::AssistantMessage; context_window::Union{Nothing,Int}=nothing)
    text = _assistant_text(msg)
    if msg.stop_reason == "error"
        any(p -> occursin(p, text), OVERFLOW_EXCLUSIONS) && return false
        any(p -> occursin(p, text), OVERFLOW_PATTERNS) && return true
    end
    if context_window !== nothing && context_window > 0
        input_tokens = msg.usage.input + msg.usage.cache_read
        if msg.stop_reason == "stop" && input_tokens > context_window
            return true
        end
        if msg.stop_reason == "length" && msg.usage.output == 0 && input_tokens >= context_window * 0.99
            return true
        end
    end
    return false
end
