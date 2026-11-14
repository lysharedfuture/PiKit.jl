const LOG_TAG = "coding_types"

"""
    BashExecutionMessage(command, output; exit_code=nothing, cancelled=false,
                         truncated=false, full_output_path=nothing,
                         exclude_from_context=false, timestamp=time_millis())

Conversation message recording a shell command execution. It is converted to a
user message by [`coding_convert_to_llm`](@ref) unless `exclude_from_context`
is set.

# Arguments
- `command::String`: the shell command that was executed.
- `output::String`: combined stdout/stderr captured from the command.
- `exit_code::Union{Nothing,Int}`: process exit code, or `nothing` if unavailable.
- `cancelled::Bool`: whether execution was aborted.
- `truncated::Bool`: whether the captured output was truncated.
- `full_output_path::Union{Nothing,String}`: path to the untruncated output file.
- `exclude_from_context::Bool`: omit this message from model context.
- `timestamp::Int64`: creation time in milliseconds since the epoch.
"""
struct BashExecutionMessage <: PiAISDK.AbstractMessage
    command::String
    output::String
    exit_code::Union{Nothing,Int}
    cancelled::Bool
    truncated::Bool
    full_output_path::Union{Nothing,String}
    exclude_from_context::Bool
    timestamp::Int64
end
BashExecutionMessage(command, output; exit_code=nothing, cancelled=false, truncated=false,
                     full_output_path=nothing, exclude_from_context=false,
                     timestamp=PiAISDK.time_millis()) =
    BashExecutionMessage(String(command), String(output), exit_code, cancelled, truncated,
                         full_output_path, exclude_from_context, Int64(timestamp))

"""
    CompactionSummaryMessage(summary; tokens_before=0, timestamp=time_millis())

Conversation message holding the summary produced by compaction.
[`coding_convert_to_llm`](@ref) turns it into a user message.

# Arguments
- `summary::String`: structured summary of the compacted conversation.
- `tokens_before::Int`: estimated token count of the context before compaction.
- `timestamp::Int64`: creation time in milliseconds since the epoch.
"""
struct CompactionSummaryMessage <: PiAISDK.AbstractMessage
    summary::String
    tokens_before::Int
    timestamp::Int64
end
CompactionSummaryMessage(summary; tokens_before=0, timestamp=PiAISDK.time_millis()) =
    CompactionSummaryMessage(String(summary), Int(tokens_before), Int64(timestamp))

"""
    coding_convert_to_llm(messages)

Convert PiCodingAgent conversation messages into model-facing messages. Core
`PiAISDK` messages pass through unchanged, [`BashExecutionMessage`](@ref)
becomes a `UserMessage` with the command and output (unless
`exclude_from_context`), and [`CompactionSummaryMessage`](@ref) becomes a
`UserMessage` holding the summary.

# Arguments
- `messages`: iterable of `PiAISDK.AbstractMessage` values.

# Returns
`Vector{PiAISDK.AbstractMessage}` suitable for an `LLMContext`.
"""
function coding_convert_to_llm(messages)
    out = PiAISDK.AbstractMessage[]
    for m in messages
        if m isa PiAISDK.SystemMessage || m isa PiAISDK.UserMessage || m isa PiAISDK.AssistantMessage || m isa PiAISDK.ToolResultMessage
            push!(out, m)
        elseif m isa BashExecutionMessage
            m.exclude_from_context && continue
            exit_text = m.exit_code === nothing ? "" : "\n\nCommand exited with code $(m.exit_code)"
            push!(out, PiAISDK.UserMessage("Command: $(m.command)\n\nOutput:\n$(m.output)$(exit_text)"))
        elseif m isa CompactionSummaryMessage
            push!(out, PiAISDK.UserMessage(m.summary))
        end
    end
    return out
end
