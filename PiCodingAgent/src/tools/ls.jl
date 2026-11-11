const LOG_TAG = "coding_tools_ls"

const LS_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "path" => Dict{String,Any}("type" => "string", "description" => "Directory to list (default: current directory)"),
        "limit" => Dict{String,Any}("type" => "number", "description" => "Maximum number of entries to return (default: 500)"),
    ),
    "additionalProperties" => false,
)

struct LsOperations
    exists::Function
    isdir::Function
    readdir::Function
end

const DEFAULT_LS_OPERATIONS = LsOperations(path -> ispath(path), path -> isdir(path), path -> readdir(path))

function ls_tool(cwd::String; operations::LsOperations=DEFAULT_LS_OPERATIONS)
    execute = function (id, args, signal, on_update)
        dir_path = resolve_to_cwd(get(args, "path", "."), cwd)
        effective_limit = max(1, Int(floor(Float64(get(args, "limit", 500)))))
        operations.exists(dir_path) ||
            return PiAgentCore.ToolResult(AbstractContent[TextContent("Path not found: $(dir_path)")]; is_error=true)
        operations.isdir(dir_path) ||
            return PiAgentCore.ToolResult(AbstractContent[TextContent("Not a directory: $(dir_path)")]; is_error=true)
        entries = try
            operations.readdir(dir_path)
        catch err
            return PiAgentCore.ToolResult(AbstractContent[TextContent("Cannot read directory: $(sprint(showerror, err))")]; is_error=true)
        end
        sort!(entries; by=lowercase)
        results = String[]
        entry_limit_reached = false
        for entry in entries
            if length(results) >= effective_limit
                entry_limit_reached = true
                break
            end
            full = joinpath(dir_path, entry)
            suffix = try
                isdir(full) ? "/" : ""
            catch err
                @debug "skipping unstattable directory entry" _group=LOG_TAG path=full exception=(err, catch_backtrace())
                continue
            end
            push!(results, entry * suffix)
        end
        isempty(results) && return PiAgentCore.ToolResult(AbstractContent[TextContent("(empty directory)")])
        raw = join(results, "\n")
        trunc = truncate_head(raw; max_lines=typemax(Int))
        notices = String[]
        details = Dict{String,Any}()
        if entry_limit_reached
            push!(notices, "$(effective_limit) entries limit reached. Use limit=$(effective_limit * 2) for more")
            details["entryLimitReached"] = effective_limit
        end
        if trunc.truncated
            push!(notices, "$(format_size(DEFAULT_MAX_BYTES)) limit reached")
            details["truncation"] = _trunc_json(trunc)
        end
        output = trunc.content
        isempty(notices) || (output *= "\n\n[" * join(notices, ". ") * "]")
        return PiAgentCore.ToolResult(AbstractContent[TextContent(output)];
            details=isempty(details) ? nothing : details)
    end
    description = "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first)."
    return PiAgentCore.Tool("ls", description, LS_SCHEMA, execute; label="ls")
end
