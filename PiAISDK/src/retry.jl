const LOG_TAG = "ai_retry"

const NON_RETRYABLE_PATTERNS = [
    r"insufficient_quota"i, r"billing"i, r"out of budget"i, r"quota exceeded"i,
    r"GoUsageLimitError", r"FreeUsageLimitError", r"Monthly usage limit reached"i,
    r"available balance"i, r"code\s*:\s*1308", r"subscription_sharing_.*_limit_exceeded"i,
]

const RETRYABLE_PATTERNS = [
    r"overloaded"i, r"server_busy"i, r"rate.?limit"i, r"too many requests"i,
    r"(?<!\d)(?:429|500|502|503|504|520|524)(?!\d)",
    r"service.?unavailable"i, r"provider.?returned.?error"i,
    r"stream disconnected"i, r"ended without"i, r"you can retry your request"i,
    r"ResourceExhausted", r"socket connection was closed"i,
]

function is_non_retryable_error(text::AbstractString)
    return any(p -> occursin(p, text), NON_RETRYABLE_PATTERNS)
end

function is_retryable_error_text(text::AbstractString)
    is_non_retryable_error(text) && return false
    return any(p -> occursin(p, text), RETRYABLE_PATTERNS)
end

function is_retryable_assistant_error(msg::AssistantMessage)
    msg.stop_reason == "error" || return false
    text = string(msg.error_message === nothing ? "" : msg.error_message)
    for c in msg.content
        c isa TextContent && (text *= " " * c.text)
    end
    return is_retryable_error_text(text)
end

retry_delay_ms(base_delay_ms::Int, max_delay_ms::Int, attempt::Int) =
    min(base_delay_ms * 2^max(0, attempt - 1), max_delay_ms)

retry_delay_ms(policy, attempt::Int) =
    retry_delay_ms(Int(getproperty(policy, :base_delay_ms)), Int(getproperty(policy, :max_delay_ms)), attempt)
