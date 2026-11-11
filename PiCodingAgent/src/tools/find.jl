const LOG_TAG = "coding_tools_find"

const FIND_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "pattern" => Dict{String,Any}("type" => "string", "description" => "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"),
        "path" => Dict{String,Any}("type" => "string", "description" => "Directory to search in (default: current directory)"),
        "limit" => Dict{String,Any}("type" => "number", "description" => "Maximum number of results (default: 1000)"),
    ),
    "required" => ["pattern"],
    "additionalProperties" => false,
)

struct FindOperations
    exists::Function
    glob::Function
end

function _inside_git_repo(path::String)
    current = abspath(path)
    while true
        ispath(joinpath(current, ".git")) && return true
        parent = dirname(current)
        parent == current && return false
        current = parent
    end
end

function fd_glob(pattern::String, search_path::String, limit::Int)
    args = String["--glob", "--color=never", "--hidden"]
    _inside_git_repo(search_path) || push!(args, "--no-require-git")
    append!(args, ["--max-results", string(max(limit, 1))])
    effective_pattern = pattern
    if occursin('/', pattern)
        push!(args, "--full-path")
        if !startswith(pattern, "/") && !startswith(pattern, "**/") && pattern != "**"
            effective_pattern = "**/" * pattern
        end
        Sys.iswindows() && (effective_pattern = replace(effective_pattern, "/" => "[/\\\\]"))
    end
    append!(args, ["--", effective_pattern, search_path])
    captured = run_capture(`$(fd_jll.fd_executable()) $(args)`)
    if captured.exit_code != 0
        isempty(strip(captured.stderr)) && return String[]
        throw(ErrorException(strip(captured.stderr)))
    end
    return String[strip(replace(line, '\r' => "")) for line in split(captured.stdout, '\n') if !isempty(strip(line))]
end

const DEFAULT_FIND_OPERATIONS = FindOperations(path -> ispath(path),
                                               (pattern, path, limit) -> fd_glob(pattern, path, limit))

function relativize_find_result(result_path::String, search_path::String)
    had_trailing = endswith(result_path, '/') || endswith(result_path, '\\')
    relative = isabspath(result_path) ? relpath(result_path, search_path) : result_path
    posix = replace(relative, '\\' => '/')
    return had_trailing && !endswith(posix, "/") ? posix * "/" : posix
end

function find_tool(cwd::String; operations::FindOperations=DEFAULT_FIND_OPERATIONS)
    execute = function (id, args, signal, on_update)
        pattern = String(args["pattern"])
        search_dir = get(args, "path", nothing)
        search_path = resolve_to_cwd(search_dir === nothing ? "." : String(search_dir), cwd)
        operations.exists(search_path) ||
            return PiAgentCore.ToolResult(AbstractContent[TextContent("Path not found: $(search_path)")]; is_error=true)
        effective_limit = max(1, Int(floor(Float64(get(args, "limit", 1000)))))
        results = try
            if operations.glob === DEFAULT_FIND_OPERATIONS.glob
                fd_glob(pattern, search_path, effective_limit + 1)
            else
                operations.glob(pattern, search_path, effective_limit + 1)
            end
        catch err
            return PiAgentCore.ToolResult(AbstractContent[TextContent(sprint(showerror, err))]; is_error=true)
        end
        isempty(results) && return PiAgentCore.ToolResult(AbstractContent[TextContent("No files found matching pattern")])
        result_limit_reached = length(results) > effective_limit
        relativized = [relativize_find_result(p, search_path) for p in results[1:min(length(results), effective_limit)]]
        raw = join(relativized, "\n")
        trunc = truncate_head(raw; max_lines=typemax(Int))
        notices = String[]
        details = Dict{String,Any}()
        if trunc.truncated
            push!(notices, "$(format_size(DEFAULT_MAX_BYTES)) limit reached")
            details["truncation"] = _trunc_json(trunc)
        end
        if result_limit_reached
            push!(notices, "$(effective_limit) results limit reached. Use limit=$(effective_limit * 2) for more, or refine pattern")
            details["resultLimitReached"] = effective_limit
        end
        output = trunc.content
        isempty(notices) || (output *= "\n\n[" * join(notices, ". ") * "]")
        return PiAgentCore.ToolResult(AbstractContent[TextContent(output)];
            details=isempty(details) ? nothing : details)
    end
    description = "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or $(DEFAULT_MAX_BYTES ÷ 1024)KB (whichever is hit first)."
    return PiAgentCore.Tool("find", description, FIND_SCHEMA, execute; label="find")
end
