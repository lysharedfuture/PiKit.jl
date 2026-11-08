const LOG_TAG = "coding_tools_registry"

const DEFAULT_TOOL_NAMES = ["read", "bash", "edit", "write"]
const OPTIONAL_TOOL_NAMES = ["grep", "find", "ls", "powershell"]

const TOOL_SNIPPETS = Dict{String,String}(
    "read" => "Read file contents",
    "bash" => "Execute bash commands (ls, grep, find, etc.)",
    "edit" => "Make precise file edits with exact text replacement, including multiple disjoint edits in one call",
    "write" => "Create or overwrite files",
    "grep" => "Search file contents for patterns (respects .gitignore)",
    "find" => "Find files by glob pattern (respects .gitignore)",
    "ls" => "List directory contents",
    "powershell" => "Execute PowerShell commands",
)

const TOOL_GUIDELINES = Dict{String,Vector{String}}(
    "read" => ["Use read to examine files instead of cat or sed."],
    "bash" => ["You can inspect PI_* environment variables for current model and session details."],
    "edit" => ["Use edit for targeted changes. Batch changes to one file in a single call.",
               "Each edits[].oldText must exactly and uniquely match the original file. Keep matches short and non-overlapping; merge nearby changes without including large unchanged regions."],
    "write" => ["Use write only for new files or complete rewrites."],
    "grep" => String[],
    "find" => String[],
    "ls" => String[],
    "powershell" => ["You can inspect PI_* environment variables for current model and session details."],
)

function create_tool(name::AbstractString, cwd::AbstractString; model=nothing,
                     agent_dir=default_agent_dir(), shell_path=nothing,
                     env::Union{Nothing,Dict{String,String}}=nothing)
    supports_images = model === nothing || ("image" in model.input)
    n = String(name)
    if n == "read"
        return read_tool(String(cwd); supports_images=supports_images)
    elseif n == "bash"
        return bash_tool(String(cwd); env=env, shell_path=shell_path)
    elseif n == "edit"
        return edit_tool(String(cwd))
    elseif n == "write"
        return write_tool(String(cwd))
    elseif n == "grep"
        return grep_tool(String(cwd); agent_dir=agent_dir)
    elseif n == "find"
        return find_tool(String(cwd); agent_dir=agent_dir)
    elseif n == "ls"
        return ls_tool(String(cwd))
    elseif n == "powershell"
        return powershell_tool(String(cwd); env=env)
    end
    throw(ArgumentError("Unknown tool: $(name)"))
end

function create_tools(cwd::AbstractString; names=DEFAULT_TOOL_NAMES, model=nothing,
                      agent_dir=default_agent_dir(), shell_path=nothing,
                      env::Union{Nothing,Dict{String,String}}=nothing)
    return AgentCore.Tool[create_tool(n, cwd; model=model, agent_dir=agent_dir,
                                      shell_path=shell_path, env=env) for n in names]
end
