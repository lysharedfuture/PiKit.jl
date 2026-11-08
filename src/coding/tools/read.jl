const LOG_TAG = "coding_tools_read"

const READ_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "path" => Dict{String,Any}("type" => "string", "description" => "Path to the file to read (relative or absolute)"),
        "offset" => Dict{String,Any}("type" => "number", "description" => "Line number to start reading from (1-indexed)"),
        "limit" => Dict{String,Any}("type" => "number", "description" => "Maximum number of lines to read"),
    ),
    "required" => ["path"],
    "additionalProperties" => false,
)

function _image_mime(data::Vector{UInt8})
    length(data) >= 4 || return nothing
    if data[1] == 0x89 && data[2] == 0x50 && data[3] == 0x4e && data[4] == 0x47
        return "image/png"
    elseif data[1] == 0xff && data[2] == 0xd8
        return "image/jpeg"
    elseif data[1] == 0x47 && data[2] == 0x49 && data[3] == 0x46
        return "image/gif"
    elseif length(data) >= 12 && String(data[1:4]) == "RIFF" && String(data[9:12]) == "WEBP"
        return "image/webp"
    elseif data[1] == 0x42 && data[2] == 0x4d
        return "image/bmp"
    end
    return nothing
end

function _detect_image_mime(path::String)
    ext = lowercase(splitext(path)[2])
    ext in (".png",) && return "image/png"
    ext in (".jpg", ".jpeg") && return "image/jpeg"
    ext in (".gif",) && return "image/gif"
    ext in (".webp",) && return "image/webp"
    ext in (".bmp",) && return "image/bmp"
    try
        return _image_mime(read(path))
    catch err
        @debug "image mime detection failed" _group=LOG_TAG path=path exception=(err, catch_backtrace())
        return nothing
    end
end

struct ReadOperations
    access::Function
    read_file::Function
    detect_image_mime::Function
end

const DEFAULT_READ_OPERATIONS = ReadOperations(path -> isfile(path), path -> read(path),
                                               path -> _detect_image_mime(path))

function read_tool(cwd::String; supports_images::Bool=true,
                   operations::ReadOperations=DEFAULT_READ_OPERATIONS)
    execute = function (id, args, signal, on_update)
        path = String(args["path"])
        offset = haskey(args, "offset") ? Int(args["offset"]) : nothing
        limit = haskey(args, "limit") ? Int(args["limit"]) : nothing
        resolved = resolve_read_path(path, cwd)
        operations.access(resolved) || return AgentCore.ToolResult(
            AbstractContent[TextContent("File not found: $(resolved)")]; is_error=true)
        mime = operations.detect_image_mime(resolved)
        if mime !== nothing
            if !supports_images
                return AgentCore.ToolResult(AbstractContent[TextContent(
                    "[Current model does not support images. The image will be omitted from this request.]")])
            end
            data = operations.read_file(resolved)
            encoded = Base64.base64encode(data)
            note = "Read image file [$(mime)]"
            return AgentCore.ToolResult(AbstractContent[TextContent(note), ImageContent(encoded, mime)])
        end
        content = read(resolved, String)
        all_lines = split(content, '\n')
        endswith(content, '\n') && !isempty(all_lines) && pop!(all_lines)
        total_file_lines = length(all_lines)
        start_line = offset === nothing ? 0 : max(0, offset - 1)
        start_display = start_line + 1
        if start_line >= total_file_lines
            return AgentCore.ToolResult(AbstractContent[TextContent(
                "Offset $(offset) is beyond end of file ($(total_file_lines) lines total)")]; is_error=true)
        end
        end_line = limit === nothing ? total_file_lines : min(start_line + limit, total_file_lines)
        selected = join(all_lines[(start_line+1):end_line], "\n")
        trunc = truncate_head(selected)
        first_line_bytes = trunc.first_line_exceeds_limit ? sizeof(all_lines[start_line + 1]) : 0
        user_limited = limit === nothing ? nothing : min(start_line + limit, total_file_lines) - start_line
        output_text = ""
        details = nothing
        if trunc.first_line_exceeds_limit
            output_text = "[Line $(start_display) is $(format_size(first_line_bytes)), exceeds $(format_size(DEFAULT_MAX_BYTES)) limit. Use bash: sed -n '$(start_display)p' $(path) | head -c $(DEFAULT_MAX_BYTES)]"
            details = Dict{String,Any}("truncation" => _trunc_json(trunc))
        elseif trunc.truncated
            end_display = start_display + trunc.output_lines - 1
            next_offset = end_display + 1
            output_text = trunc.content
            if trunc.truncated_by == "lines"
                output_text *= "\n\n[Showing lines $(start_display)-$(end_display) of $(total_file_lines). Use offset=$(next_offset) to continue.]"
            else
                output_text *= "\n\n[Showing lines $(start_display)-$(end_display) of $(total_file_lines) ($(format_size(DEFAULT_MAX_BYTES)) limit). Use offset=$(next_offset) to continue.]"
            end
            details = Dict{String,Any}("truncation" => _trunc_json(trunc))
        elseif user_limited !== nothing && start_line + user_limited < total_file_lines
            remaining = total_file_lines - (start_line + user_limited)
            next_offset = start_line + user_limited + 1
            output_text = trunc.content * "\n\n[$(remaining) more lines in file. Use offset=$(next_offset) to continue.]"
        else
            output_text = trunc.content
        end
        return AgentCore.ToolResult(AbstractContent[TextContent(output_text)]; details=details)
    end
    description = "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to $(DEFAULT_MAX_LINES) lines or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
    return AgentCore.Tool("read", description, READ_SCHEMA, execute; label="read")
end

function _trunc_json(t::TruncationResult)
    return Dict{String,Any}(
        "content" => t.content, "truncated" => t.truncated, "truncatedBy" => t.truncated_by,
        "totalLines" => t.total_lines, "totalBytes" => t.total_bytes,
        "outputLines" => t.output_lines, "outputBytes" => t.output_bytes,
        "lastLinePartial" => t.last_line_partial,
        "firstLineExceedsLimit" => t.first_line_exceeds_limit,
        "maxLines" => t.max_lines, "maxBytes" => t.max_bytes,
    )
end
