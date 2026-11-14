const LOG_TAG = "coding_tools_write"

const WRITE_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "path" => Dict{String,Any}("type" => "string", "description" => "Path to the file to write (relative or absolute)"),
        "content" => Dict{String,Any}("type" => "string", "description" => "Content to write to the file"),
    ),
    "required" => ["path", "content"],
    "additionalProperties" => false,
)

"""
    write_tool(cwd::String)

Create the `write` tool, which creates or overwrites a file and any missing
parent directories. Writes run sequentially under the file-mutation lock.

# Arguments
- `cwd::String`: working directory used to resolve relative paths.

# Returns
A `PiAgentCore.Tool`.
"""
function write_tool(cwd::String)
    execute = function (id, args, signal, on_update)
        resolved = resolve_to_cwd(String(args["path"]), cwd)
        content = String(args["content"])
        return with_file_lock(resolved) do
            parent = dirname(resolved)
            isdir(parent) || mkpath(parent)
            write(resolved, content)
            return PiAgentCore.ToolResult(AbstractContent[TextContent("Successfully wrote to $(String(args["path"]))")])
        end
    end
    description = "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
    return PiAgentCore.Tool("write", description, WRITE_SCHEMA, execute;
                          label="write", execution_mode=:sequential)
end
