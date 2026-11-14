const LOG_TAG = "coding_tools_truncate"

"""
    DEFAULT_MAX_LINES

Maximum number of output lines retained by the truncation helpers (2000).
"""
const DEFAULT_MAX_LINES = 2000

"""
    DEFAULT_MAX_BYTES

Maximum number of output bytes retained by the truncation helpers (50 KiB).
"""
const DEFAULT_MAX_BYTES = 50 * 1024

"""
    GREP_MAX_LINE_LENGTH

Maximum characters per line before grep results are truncated (500).
"""
const GREP_MAX_LINE_LENGTH = 500

"""
    TruncationResult

Outcome of [`truncate_head`](@ref) or [`truncate_tail`](@ref).

# Fields
- `content::String`: the retained text.
- `truncated::Bool`: whether anything was dropped.
- `truncated_by::Union{Nothing,String}`: `"lines"`, `"bytes"`, or `nothing`.
- `total_lines::Int`, `total_bytes::Int`: size of the input.
- `output_lines::Int`, `output_bytes::Int`: size of `content`.
- `last_line_partial::Bool`: the first retained line was cut mid-line.
- `first_line_exceeds_limit::Bool`: a single line exceeds the byte limit.
- `max_lines::Int`, `max_bytes::Int`: limits that were applied.
"""
struct TruncationResult
    content::String
    truncated::Bool
    truncated_by::Union{Nothing,String}
    total_lines::Int
    total_bytes::Int
    output_lines::Int
    output_bytes::Int
    last_line_partial::Bool
    first_line_exceeds_limit::Bool
    max_lines::Int
    max_bytes::Int
end

function split_lines_for_counting(content::String)
    isempty(content) && return String[]
    lines = split(content, '\n')
    endswith(content, '\n') && !isempty(lines) && pop!(lines)
    return String[String(l) for l in lines]
end

"""
    format_size(bytes::Integer)

Format a byte count as `"512B"`, `"1.5KB"`, or `"2.0MB"`.

# Arguments
- `bytes::Integer`: number of bytes.

# Returns
`String` human-readable size.
"""
function format_size(bytes::Integer)
    if bytes < 1024
        return string(bytes, "B")
    elseif bytes < 1024 * 1024
        return string(round(bytes / 1024; digits=1), "KB")
    end
    return string(round(bytes / (1024 * 1024); digits=1), "MB")
end

"""
    truncate_head(content::String; max_lines=DEFAULT_MAX_LINES, max_bytes=DEFAULT_MAX_BYTES)

Keep the beginning of `content`, dropping trailing lines once either limit is
reached.

# Arguments
- `content::String`: text to truncate.
- `max_lines`: maximum retained lines.
- `max_bytes`: maximum retained bytes.

# Returns
A [`TruncationResult`](@ref). When the first line alone exceeds `max_bytes`,
`content` is empty and `first_line_exceeds_limit` is `true`.
"""
function truncate_head(content::String; max_lines=DEFAULT_MAX_LINES, max_bytes=DEFAULT_MAX_BYTES)
    total_bytes = sizeof(content)
    lines = split_lines_for_counting(content)
    total_lines = length(lines)
    if total_lines <= max_lines && total_bytes <= max_bytes
        return TruncationResult(content, false, nothing, total_lines, total_bytes,
                                total_lines, total_bytes, false, false, max_lines, max_bytes)
    end
    first_line_bytes = isempty(lines) ? 0 : sizeof(lines[1])
    if first_line_bytes > max_bytes
        return TruncationResult("", true, "bytes", total_lines, total_bytes,
                                0, 0, false, true, max_lines, max_bytes)
    end
    out = String[]
    output_bytes = 0
    truncated_by = "lines"
    for (i, line) in enumerate(lines)
        i > max_lines && break
        line_bytes = sizeof(line) + (i > 1 ? 1 : 0)
        if output_bytes + line_bytes > max_bytes
            truncated_by = "bytes"
            break
        end
        push!(out, line)
        output_bytes += line_bytes
    end
    if length(out) >= max_lines && output_bytes <= max_bytes
        truncated_by = "lines"
    end
    output = join(out, "\n")
    return TruncationResult(output, true, truncated_by, total_lines, total_bytes,
                            length(out), sizeof(output), false, false, max_lines, max_bytes)
end

function _truncate_from_end(str::String, max_bytes::Int)
    sizeof(str) <= max_bytes && return str
    i = lastindex(str)
    bytes = 0
    while i >= firstindex(str)
        ch = str[i]
        n = sizeof(string(ch))
        bytes + n > max_bytes && break
        bytes += n
        i = prevind(str, i)
    end
    start = i < firstindex(str) ? firstindex(str) : nextind(str, i)
    return str[start:end]
end

"""
    truncate_tail(content::String; max_lines=DEFAULT_MAX_LINES, max_bytes=DEFAULT_MAX_BYTES)

Keep the end of `content`, dropping leading lines once either limit is
reached. If the final line alone exceeds `max_bytes`, its trailing bytes are
kept and `last_line_partial` is set.

# Arguments
- `content::String`: text to truncate.
- `max_lines`: maximum retained lines.
- `max_bytes`: maximum retained bytes.

# Returns
A [`TruncationResult`](@ref).
"""
function truncate_tail(content::String; max_lines=DEFAULT_MAX_LINES, max_bytes=DEFAULT_MAX_BYTES)
    total_bytes = sizeof(content)
    lines = split_lines_for_counting(content)
    total_lines = length(lines)
    if total_lines <= max_lines && total_bytes <= max_bytes
        return TruncationResult(content, false, nothing, total_lines, total_bytes,
                                total_lines, total_bytes, false, false, max_lines, max_bytes)
    end
    out = String[]
    output_bytes = 0
    truncated_by = "lines"
    last_line_partial = false
    for i in total_lines:-1:1
        length(out) >= max_lines && break
        line = lines[i]
        line_bytes = sizeof(line) + (isempty(out) ? 0 : 1)
        if output_bytes + line_bytes > max_bytes
            truncated_by = "bytes"
            if isempty(out)
                partial = _truncate_from_end(line, max_bytes)
                pushfirst!(out, partial)
                output_bytes = sizeof(partial)
                last_line_partial = true
            end
            break
        end
        pushfirst!(out, line)
        output_bytes += line_bytes
    end
    if length(out) >= max_lines && output_bytes <= max_bytes
        truncated_by = "lines"
    end
    output = join(out, "\n")
    return TruncationResult(output, true, truncated_by, total_lines, total_bytes,
                            length(out), sizeof(output), last_line_partial, false, max_lines, max_bytes)
end

"""
    truncate_line(line::String; max_chars=GREP_MAX_LINE_LENGTH)

Truncate a single line to `max_chars` characters, appending
`"... [truncated]"` when shortened.

# Arguments
- `line::String`: input line.
- `max_chars::Int`: maximum character count.

# Returns
`NamedTuple` `(text, was_truncated)`.
"""
function truncate_line(line::String; max_chars=GREP_MAX_LINE_LENGTH)
    if length(line) <= max_chars
        return (text=line, was_truncated=false)
    end
    return (text=first(line, max_chars) * "... [truncated]", was_truncated=true)
end
