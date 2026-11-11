const LOG_TAG = "coding_types"

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

struct CompactionSummaryMessage <: PiAISDK.AbstractMessage
    summary::String
    tokens_before::Int
    timestamp::Int64
end
CompactionSummaryMessage(summary; tokens_before=0, timestamp=PiAISDK.time_millis()) =
    CompactionSummaryMessage(String(summary), Int(tokens_before), Int64(timestamp))

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
