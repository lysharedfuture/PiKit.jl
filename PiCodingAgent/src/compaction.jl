const LOG_TAG = "coding_compaction"

const ESTIMATED_IMAGE_CHARS = 4800

const SUMMARIZATION_PROMPT = """The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.

Use this EXACT format:

## Goal
[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned by user]
- [Or "(none)" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Current work]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Any data, examples, or references needed to continue]
- [Or "(none)" if not applicable]

Keep each section concise. Preserve exact file paths, function names, and error messages."""

const UPDATE_SUMMARIZATION_PROMPT = """The messages above are NEW conversation messages to incorporate into the existing summary provided in <previous-summary> tags.

Update the existing structured summary with new information. RULES:
- PRESERVE all existing information from the previous summary
- ADD new progress, decisions, and context from the new messages
- UPDATE the Progress section: move items from "In Progress" to "Done" when completed
- UPDATE "Next Steps" based on what was accomplished
- PRESERVE exact file paths, function names, and error messages
- If something is no longer relevant, you may remove it

Use this EXACT format:

## Goal
[Preserve existing goals, add new ones if the task expanded]

## Constraints & Preferences
- [Preserve existing, add new ones discovered]

## Progress
### Done
- [x] [Include previously done items AND newly completed items]

### In Progress
- [ ] [Current work - update based on progress]

### Blocked
- [Current blockers - remove if resolved]

## Key Decisions
- **[Decision]**: [Brief rationale] (preserve all previous, add new)

## Next Steps
1. [Update based on current state]

## Critical Context
- [Preserve important context, add new if needed]

Keep each section concise. Preserve exact file paths, function names, and error messages."""

function _content_chars(content)
    content isa AbstractString && return length(content)
    chars = 0
    for c in content
        if c isa PiAI.TextContent
            chars += length(c.text)
        elseif c isa PiAI.ImageContent
            chars += ESTIMATED_IMAGE_CHARS
        end
    end
    return chars
end

function estimate_tokens(m::PiAI.SystemMessage)
    chars = _content_chars(m.content)
    if m.sections !== nothing
        for (_, v) in m.sections
            v === nothing || (chars += length(v))
        end
    end
    isempty(m.tools_added) || (chars += length(json_write(m.tools_added)))
    return ceil(Int, chars / 4)
end
estimate_tokens(m::PiAI.UserMessage) = ceil(Int, _content_chars(m.content) / 4)
function estimate_tokens(m::PiAI.AssistantMessage)
    chars = 0
    for c in m.content
        if c isa PiAI.TextContent
            chars += length(c.text)
        elseif c isa PiAI.ThinkingContent
            chars += length(c.thinking)
        elseif c isa PiAI.ToolCall
            chars += length(c.name) + length(json_write(c.arguments))
        end
    end
    return ceil(Int, chars / 4)
end
estimate_tokens(m::PiAI.ToolResultMessage) = ceil(Int, _content_chars(m.content) / 4)
estimate_tokens(m::BashExecutionMessage) = ceil(Int, (length(m.command) + length(m.output)) / 4)
estimate_tokens(m::CompactionSummaryMessage) = ceil(Int, length(m.summary) / 4)
estimate_tokens(::PiAI.AbstractMessage) = 0

function last_usage_info(messages)
    for i in length(messages):-1:1
        m = messages[i]
        m isa PiAI.AssistantMessage || continue
        m.stop_reason in ("error", "aborted") && continue
        total = PiAI.token_total(m.usage)
        total > 0 || continue
        return (index=i, tokens=total)
    end
    return nothing
end

function estimate_context_tokens(messages)
    info = last_usage_info(messages)
    if info === nothing
        return sum(estimate_tokens(m) for m in messages; init=0)
    end
    trailing = sum(estimate_tokens(messages[i]) for i in (info.index + 1):length(messages); init=0)
    return info.tokens + trailing
end

function should_compact(context_tokens::Int, context_window::Int, reserve_tokens::Int)
    return context_tokens > context_window - reserve_tokens
end

function _is_cut_point(m)
    return m isa PiAI.UserMessage || m isa PiAI.AssistantMessage || m isa BashExecutionMessage ||
           m isa CompactionSummaryMessage
end

function _is_turn_start(m)
    return m isa PiAI.UserMessage || m isa BashExecutionMessage || m isa CompactionSummaryMessage
end

function find_cut_point(messages; keep_recent_tokens=20_000)
    total = 0
    cut = 1
    for i in length(messages):-1:1
        total += estimate_tokens(messages[i])
        if total >= keep_recent_tokens
            cut = i
            break
        end
    end
    while cut <= length(messages) && !_is_cut_point(messages[cut])
        cut += 1
    end
    cut > length(messages) && (cut = max(1, length(messages)))
    if cut <= length(messages) && messages[cut] isa PiAI.AssistantMessage
        j = cut - 1
        while j >= 1 && !_is_turn_start(messages[j])
            j -= 1
        end
        j >= 1 && (cut = j)
    end
    return cut
end

function _render_for_summary(m)
    if m isa PiAI.SystemMessage
        parts = String[]
        m.content isa AbstractString ? push!(parts, m.content) :
            append!(parts, [c.text for c in m.content if c isa PiAI.TextContent])
        m.sections === nothing || append!(parts, [v for (_, v) in m.sections if v !== nothing])
        return "System: " * join(parts, "\n")
    elseif m isa PiAI.UserMessage
        return "User: " * (m.content isa AbstractString ? m.content : join([c.text for c in m.content if c isa PiAI.TextContent], "\n"))
    elseif m isa PiAI.AssistantMessage
        parts = String[]
        for c in m.content
            c isa PiAI.TextContent && push!(parts, c.text)
            c isa PiAI.ThinkingContent && push!(parts, "[thinking] " * c.thinking)
            c isa PiAI.ToolCall && push!(parts, "[tool $(c.name)] " * json_write(c.arguments))
        end
        return "Assistant: " * join(parts, "\n")
    elseif m isa PiAI.ToolResultMessage
        return "Tool result ($(m.tool_name)): " * join([c.text for c in m.content if c isa PiAI.TextContent], "\n")
    elseif m isa BashExecutionMessage
        return "Bash: " * m.command * "\n" * m.output
    elseif m isa CompactionSummaryMessage
        return "Previous summary: " * m.summary
    end
    return ""
end

function summarize(model::PiAI.Model, messages, opts::PiAI.StreamOptions, retry::RetryPolicy,
                    emit; signal=nothing, previous_summary=nothing)
    conversation = join((_render_for_summary(m) for m in messages), "\n\n")
    prompt = conversation * "\n\n# Instructions\n" *
             (previous_summary === nothing ? SUMMARIZATION_PROMPT :
              "<previous-summary>\n$(previous_summary)\n</previous-summary>\n\n" * UPDATE_SUMMARIZATION_PROMPT)
    attempt = 0
    max_attempts = retry.enabled ? retry.max_attempts + 1 : 1
    while true
        attempt += 1
        ctx = PiAI.LLMContext(PiAI.AbstractMessage[PiAI.SystemMessage(""), PiAI.UserMessage(prompt)])
        stream_opts = PiAI.StreamOptions(
            api_key=opts.api_key, signal=signal, headers=opts.headers,
            max_tokens=min(model.max_tokens, 8192), reasoning="off",
            session_id=opts.session_id, timeout_ms=opts.timeout_ms)
        response = PiAI.result(PiAI.stream(model, ctx, stream_opts))
        if response.stop_reason == "stop"
            text = join([c.text for c in response.content if c isa PiAI.TextContent], "")
            return (ok=true, summary=text, usage=response.usage, error=nothing)
        end
        err = response.stop_reason == "error" ? something(response.error_message, "Unknown error") :
              response.stop_reason == "length" ? "generation hit the token cap and the summary is incomplete" :
              "summarization aborted"
        if attempt < max_attempts && response.stop_reason == "error" &&
           PiAI.is_retryable_error_text(err)
            delay = retry_delay_ms(retry, attempt)
            emit((type="summarization_retry_start", attempt=attempt, delayMs=delay, errorMessage=err))
            PiAI.sleep_abortable(delay / 1000, signal)
            emit((type="summarization_retry_end", success=false, attempt=attempt))
            continue
        end
        return (ok=false, summary="", usage=response.usage, error=err)
    end
end

function compact!(sm::SessionManager, model::PiAI.Model, opts::PiAI.StreamOptions,
                  retry::RetryPolicy; reason::String="manual", keep_recent_tokens=20_000,
                  reserve_tokens=16_384, signal=nothing, emit=(ev)->nothing)
    messages = build_context(sm)
    tokens_before = estimate_context_tokens(messages)
    emit((type="compaction_start", reason=reason))
    if length(messages) <= 1
        emit((type="compaction_end", reason=reason, result=nothing, aborted=false,
              willRetry=false, errorMessage="Not enough context to compact"))
        return nothing
    end
    cut = find_cut_point(messages; keep_recent_tokens=keep_recent_tokens)
    to_summarize = messages[1:max(0, cut - 1)]
    keep = messages[cut:end]
    if isempty(to_summarize)
        emit((type="compaction_end", reason=reason, result=nothing, aborted=false,
              willRetry=false, errorMessage="Not enough context to compact"))
        return nothing
    end
    previous = nothing
    for e in sm.entries
        e isa CompactionEntry && (previous = e.summary)
    end
    result = summarize(model, to_summarize, opts, retry, emit; signal=signal, previous_summary=previous)
    if !result.ok
        aborted = signal !== nothing && PiAI.is_aborted(signal)
        emit((type="compaction_end", reason=reason, result=nothing, aborted=aborted,
              willRetry=false, errorMessage=result.error))
        return nothing
    end
    system_message = nothing
    for m in messages
        m isa PiAI.SystemMessage && (system_message = m)
    end
    first_kept_id = nothing
    for entry in sm.entries
        entry isa MessageEntry || continue
        if !isempty(keep) && entry.message === keep[1]
            first_kept_id = entry.id
            break
        end
    end
    entry_id = new_entry_id(Set{String}(e.id for e in sm.entries if e.id !== nothing))
    if first_kept_id === nothing
        first_kept_id = entry_id
    end
    entry = append_entry!(sm, CompactionEntry(entry_id, sm.leaf_id, now_iso(), result.summary,
        first_kept_id, tokens_before, system_message, result.usage,
        nothing, nothing, Dict{String,Any}()))
    emit((type="compaction_end", reason=reason,
          result=(summary=result.summary, firstKeptEntryId=entry.first_kept_entry_id,
                  tokensBefore=tokens_before),
          aborted=false, willRetry=false, errorMessage=nothing))
    return entry
end
