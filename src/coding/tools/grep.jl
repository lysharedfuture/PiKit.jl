const LOG_TAG = "coding_tools_grep"

const GREP_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "pattern" => Dict{String,Any}("type" => "string", "description" => "Search pattern (regex or literal string)"),
        "path" => Dict{String,Any}("type" => "string", "description" => "Directory or file to search (default: current directory)"),
        "glob" => Dict{String,Any}("type" => "string", "description" => "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"),
        "ignoreCase" => Dict{String,Any}("type" => "boolean", "description" => "Case-insensitive search (default: false)"),
        "literal" => Dict{String,Any}("type" => "boolean", "description" => "Treat pattern as literal string instead of regex (default: false)"),
        "context" => Dict{String,Any}("type" => "number", "description" => "Number of lines to show before and after each match (default: 0)"),
        "limit" => Dict{String,Any}("type" => "number", "description" => "Maximum number of matches to return (default: 100)"),
    ),
    "required" => ["pattern"],
    "additionalProperties" => false,
)

struct GrepOperations
    is_directory::Function
    run::Function
end

function run_capture(cmd::Cmd)
    out = IOBuffer()
    err = IOBuffer()
    process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err); wait=false)
    wait(process)
    return (stdout=String(take!(out)), stderr=String(take!(err)), exit_code=process.exitcode)
end

function default_grep_run(rg_path, args)
    return run_capture(Cmd(vcat([rg_path], args)))
end

const DEFAULT_GREP_OPERATIONS = GrepOperations(
    path -> isdir(path),
    default_grep_run,
)

function grep_tool(cwd::String; operations::GrepOperations=DEFAULT_GREP_OPERATIONS,
                   agent_dir=default_agent_dir())
    execute = function (id, args, signal, on_update)
        pattern = String(args["pattern"])
        search_dir = get(args, "path", nothing)
        search_path = resolve_to_cwd(search_dir === nothing ? "." : String(search_dir), cwd)
        isdir(search_path) || isfile(search_path) ||
            return AgentCore.ToolResult(AbstractContent[TextContent("Path not found: $(search_path)")]; is_error=true)
        is_directory = operations.is_directory(search_path)
        glob = get(args, "glob", nothing)
        ignore_case = Bool(get(args, "ignoreCase", false))
        literal = Bool(get(args, "literal", false))
        context_value = max(0, Int(floor(Float64(get(args, "context", 0)))))
        effective_limit = max(1, Int(floor(Float64(get(args, "limit", 100)))))
        rg = try
            ensure_tool("rg"; agent_dir=agent_dir)
        catch err
            return AgentCore.ToolResult(AbstractContent[TextContent(
                "ripgrep (rg) is not available and could not be downloaded: $(sprint(showerror, err))")]; is_error=true)
        end
        rg_args = String["--no-config", "--json", "--line-number", "--color=never", "--hidden"]
        ignore_case && push!(rg_args, "--ignore-case")
        literal && push!(rg_args, "--fixed-strings")
        glob === nothing || append!(rg_args, ["--glob", String(glob)])
        context_value > 0 && append!(rg_args, ["--context", string(context_value)])
        append!(rg_args, ["--", pattern, search_path])
        captured = try
            operations.run(rg, rg_args)
        catch err
            return AgentCore.ToolResult(AbstractContent[TextContent("Failed to run ripgrep: $(sprint(showerror, err))")]; is_error=true)
        end
        if captured.exit_code != 0 && captured.exit_code != 1
            msg = isempty(strip(captured.stderr)) ? "ripgrep exited with code $(captured.exit_code)" : strip(captured.stderr)
            return AgentCore.ToolResult(AbstractContent[TextContent(msg)]; is_error=true)
        end
        lines_out = String[]
        match_count = 0
        lines_truncated = false
        match_limit_reached = false
        output_bytes = 0
        output_line_count = 0
        last_file = nothing
        limit_hit = false
        trailing_context_end = 0
        for raw in split(captured.stdout, '\n')
            isempty(strip(raw)) && continue
            event = try
                json_parse(raw)
            catch err
                @debug "skipping malformed rg JSON line" _group=LOG_TAG exception=(err, catch_backtrace())
                continue
            end
            typ = get(event, "type", "")
            typ in ("match", "context") || continue
            data = get(event, "data", Dict{String,Any}())
            path_entry = get(data, "path", nothing)
            file_path = path_entry isa AbstractDict ? String(get(path_entry, "text", "")) : ""
            isempty(file_path) && continue
            line_number = get(data, "line_number", nothing)
            line_number isa Number || continue
            line_entry = get(data, "lines", nothing)
            line_text = line_entry isa AbstractDict ? String(get(line_entry, "text", "")) : ""
            line_text = replace(line_text, r"\r?\n?$" => "")
            is_match = typ == "match"
            relative = if is_directory
                rel = relpath(file_path, search_path)
                startswith(rel, "..") ? basename(file_path) : replace(rel, '\\' => '/')
            else
                basename(file_path)
            end
            tl = truncate_line(line_text)
            tl.was_truncated && (lines_truncated = true)
            line = is_match ? "$(relative):$(Int(line_number)): $(tl.text)" : "$(relative)-$(Int(line_number))- $(tl.text)"
            if !limit_hit
                push!(lines_out, line)
                output_bytes += sizeof(line) + 1
                output_line_count += 1
                if is_match
                    match_count += 1
                    if match_count >= effective_limit
                        limit_hit = true
                        trailing_context_end = Int(line_number) + context_value
                    end
                end
            else
                in_window = last_file == file_path && Int(line_number) <= trailing_context_end
                if in_window
                    push!(lines_out, is_match ? "$(relative)-$(Int(line_number))- $(tl.text)" : line)
                    output_bytes += sizeof(line) + 1
                    output_line_count += 1
                end
                is_match && (match_limit_reached = true)
            end
            last_file = file_path
        end
        if match_count == 0
            return AgentCore.ToolResult(AbstractContent[TextContent("No matches found")])
        end
        trunc = truncate_head(join(lines_out, "\n"); max_lines=typemax(Int))
        notices = String[]
        details = Dict{String,Any}()
        if match_limit_reached
            push!(notices, "$(effective_limit) matches limit reached. Use limit=$(effective_limit * 2) for more, or refine pattern")
            details["matchLimitReached"] = effective_limit
        end
        if trunc.truncated
            push!(notices, "$(format_size(DEFAULT_MAX_BYTES)) limit reached")
            details["truncation"] = _trunc_json(trunc)
        end
        if lines_truncated
            push!(notices, "Some lines truncated to $(GREP_MAX_LINE_LENGTH) chars. Use read tool to see full lines")
            details["linesTruncated"] = true
        end
        output = trunc.content
        isempty(notices) || (output *= "\n\n[" * join(notices, ". ") * "]")
        return AgentCore.ToolResult(AbstractContent[TextContent(output)];
            details=isempty(details) ? nothing : details)
    end
    description = "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first). Long lines are truncated to $(GREP_MAX_LINE_LENGTH) chars."
    return AgentCore.Tool("grep", description, GREP_SCHEMA, execute; label="grep")
end
