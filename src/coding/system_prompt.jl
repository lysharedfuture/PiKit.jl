const LOG_TAG = "coding_system_prompt"

const CONTEXT_FILE_NAMES = ["AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"]
const SECTION_NAME_RE = r"^[A-Za-z0-9][A-Za-z0-9 _.-]*$"

function wrap_section(name::String, content::String)
    name == "preamble" && throw(ArgumentError("the preamble section cannot be wrapped"))
    occursin(SECTION_NAME_RE, name) || throw(ArgumentError("invalid system prompt section name: $(name)"))
    return "<$(name)>\n$(content)\n</$(name)>"
end

function _read_first_context_file(dir::String)
    for name in CONTEXT_FILE_NAMES
        path = joinpath(dir, name)
        isfile(path) && return (path=path, content=read(path, String))
    end
    return nothing
end

function discover_context_files(cwd::String; agent_dir=default_agent_dir())
    found = Tuple{String,String}[]
    global_hit = _read_first_context_file(agent_dir)
    global_hit === nothing || push!(found, (global_hit.path, global_hit.content))
    dirs = String[]
    current = abspath(cwd)
    while true
        pushfirst!(dirs, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    for dir in dirs
        hit = _read_first_context_file(dir)
        hit === nothing || push!(found, (hit.path, hit.content))
    end
    return found
end

function _read_system_override(cwd::String; trusted::Bool, agent_dir=default_agent_dir())
    candidates = String[]
    push!(candidates, joinpath(agent_dir, "SYSTEM.md"))
    push!(candidates, joinpath(cwd, ".pikit", "SYSTEM.md"))
    system_text = nothing
    append_text = nothing
    for path in candidates
        isfile(path) || continue
        if endswith(path, "SYSTEM.md") && basename(path) == "SYSTEM.md"
            system_text = read(path, String)
        end
    end
    trusted || (system_text = isfile(joinpath(agent_dir, "SYSTEM.md")) ? read(joinpath(agent_dir, "SYSTEM.md"), String) : nothing)
    for path in (joinpath(agent_dir, "APPEND_SYSTEM.md"), joinpath(cwd, ".pikit", "APPEND_SYSTEM.md"))
        isfile(path) || continue
        append_text = read(path, String)
    end
    return (system=system_text, append=append_text)
end

function default_preamble()
    return "You are pikit, a coding agent working with the user in their repository. Use the available tools to inspect and modify files. Be careful, verify your work, and keep the user informed with concise progress updates."
end

function build_system_sections(cwd::String; tools=AgentCore.Tool[], model=nothing,
                               append_system_prompt=nothing, system_prompt=nothing,
                               no_context_files::Bool=false, trusted::Bool=false,
                               agent_dir=default_agent_dir())
    overrides = _read_system_override(cwd; trusted=trusted, agent_dir=agent_dir)
    preamble = system_prompt !== nothing ? String(system_prompt) :
               overrides.system !== nothing ? overrides.system : default_preamble()
    sections = Pair{String,Union{String,Nothing}}[]
    push!(sections, "preamble" => preamble)

    if !isempty(tools)
        lines = String[]
        for tool in tools
            snippet = get(TOOL_SNIPPETS, tool.name, tool.description)
            push!(lines, "- $(tool.name): $(snippet)")
        end
        push!(sections, "tools" => join(lines, "\n") * "\n\nAdditional tools may be available.")
    end

    rules = String[]
    seen = Set{String}()
    for tool in tools
        for guideline in get(TOOL_GUIDELINES, tool.name, String[])
            guideline in seen && continue
            push!(seen, guideline)
            push!(rules, "- " * guideline)
        end
    end
    for r in ("- Be concise in your responses", "- Show file paths clearly when working with files")
        r in seen || push!(rules, r)
    end
    push!(sections, "rules" => join(rules, "\n"))

    push!(sections, "docs" => "PiKit documentation is available in docs/: CLI options (docs/cli.md), JSON events (docs/json.md), and session format (docs/sessions.md).")

    addendum_parts = String[]
    append_system_prompt !== nothing && push!(addendum_parts, String(append_system_prompt))
    overrides.append !== nothing && push!(addendum_parts, overrides.append)
    isempty(addendum_parts) || push!(sections, "addendum" => join(addendum_parts, "\n\n"))

    if !no_context_files
        files = discover_context_files(cwd; agent_dir=agent_dir)
        if !isempty(files)
            parts = String[]
            for (path, content) in files
                push!(parts, "<project_instructions path=\"$(path)\">\n$(content)\n</project_instructions>")
            end
            push!(sections, "project_context" => join(parts, "\n\n"))
        end
    end

    push!(sections, "cwd" => replace(abspath(cwd), '\\' => '/'))
    wrapped = Pair{String,Union{String,Nothing}}[]
    for (name, value) in sections
        if name == "preamble"
            push!(wrapped, name => value)
        else
            push!(wrapped, name => wrap_section(name, something(value, "")))
        end
    end
    return wrapped
end

function build_system_message(cwd::String; kwargs...)
    sections = build_system_sections(cwd; kwargs...)
    cleaned = Pair{String,Union{String,Nothing}}[p for p in sections if p.first != "preamble"]
    return AI.SystemMessage(""; sections=cleaned)
end
