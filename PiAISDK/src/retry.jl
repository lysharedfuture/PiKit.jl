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

"""
    is_non_retryable_error(text::AbstractString) -> Bool

Return `true` when `text` matches a known permanent failure (quota, billing,
or usage-limit messages) that must not be retried.
"""
function is_non_retryable_error(text::AbstractString)
    return any(p -> occursin(p, text), NON_RETRYABLE_PATTERNS)
end

"""
    is_retryable_error_text(text::AbstractString) -> Bool

Return `true` when `text` describes a transient failure (rate limit,
overloaded service, or gateway errors) worth retrying. Non-retryable matches
take precedence.
"""
function is_retryable_error_text(text::AbstractString)
    is_non_retryable_error(text) && return false
    return any(p -> occursin(p, text), RETRYABLE_PATTERNS)
end

"""
    is_retryable_assistant_error(msg::AssistantMessage) -> Bool

Return `true` when `msg` has `stop_reason == "error"` and its error text or
text blocks match a retryable failure pattern.
"""
function is_retryable_assistant_error(msg::AssistantMessage)
    msg.stop_reason == "error" || return false
    text = string(msg.error_message === nothing ? "" : msg.error_message)
    for c in msg.content
        c isa TextContent && (text *= " " * c.text)
    end
    return is_retryable_error_text(text)
end

"""
    retry_delay_ms(base_delay_ms, max_delay_ms, attempt) -> Int
    retry_delay_ms(policy, attempt) -> Int

Exponential backoff delay for retry number `attempt` (1-based), capped at
`max_delay_ms`. The two-argument form reads `base_delay_ms` and
`max_delay_ms` fields from `policy`.
"""
retry_delay_ms(base_delay_ms::Int, max_delay_ms::Int, attempt::Int) =
    min(base_delay_ms * 2^max(0, attempt - 1), max_delay_ms)

retry_delay_ms(policy, attempt::Int) =
    retry_delay_ms(Int(getproperty(policy, :base_delay_ms)), Int(getproperty(policy, :max_delay_ms)), attempt)
