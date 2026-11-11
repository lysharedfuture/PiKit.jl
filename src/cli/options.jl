const LOG_TAG = "pikit_cli_options"

struct CLIError <: Exception
    message::String
    code::Int
end
CLIError(message; code=2) = CLIError(String(message), code)

Base.@kwdef mutable struct CLIOptions
    print::Bool = false
    mode::Union{Nothing,String} = nothing
    provider::Union{Nothing,String} = nothing
    model::Union{Nothing,String} = nothing
    api_key::Union{Nothing,String} = nothing
    thinking::Union{Nothing,String} = nothing
    tools::Union{Nothing,String} = nothing
    exclude_tools::Union{Nothing,String} = nothing
    no_builtin_tools::Bool = false
    no_tools::Bool = false
    continue_session::Bool = false
    resume::Bool = false
    session::Union{Nothing,String} = nothing
    session_id::Union{Nothing,String} = nothing
    fork::Union{Nothing,String} = nothing
    session_dir::Union{Nothing,String} = nothing
    no_session::Bool = false
    name::Union{Nothing,String} = nothing
    system_prompt::Union{Nothing,String} = nothing
    append_system_prompt::Vector{String} = String[]
    no_context_files::Bool = false
    approve::Union{Nothing,Bool} = nothing
    offline::Bool = false
    list_models::Union{Nothing,String} = nothing
    version::Bool = false
    help::Bool = false
    prompt_parts::Vector{String} = String[]
    images::Vector{PiAI.ImageContent} = PiAI.ImageContent[]
end

function _need_value(args, i, opt)
    i < length(args) || throw(CLIError("Missing value for $(opt)"))
    return args[i + 1], i + 1
end

function _read_prompt_file(path::String)
    isfile(path) || throw(CLIError("File not found: $(path)"))
    ext = lowercase(splitext(path)[2])
    if ext in (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
        data = Base64.base64encode(read(path))
        mime = ext == ".png" ? "image/png" : ext in (".jpg", ".jpeg") ? "image/jpeg" :
               ext == ".gif" ? "image/gif" : ext == ".webp" ? "image/webp" : "image/bmp"
        return (text=nothing, image=PiAI.ImageContent(data, mime))
    end
    return (text=read(path, String), image=nothing)
end

function _assign_option!(opts::CLIOptions, arg::String, args, i)
    if arg == "-p" || arg == "--print"
        opts.print = true
    elseif arg == "--mode"
        v, i = _need_value(args, i, arg); opts.mode = v
    elseif arg == "--provider"
        v, i = _need_value(args, i, arg); opts.provider = v
    elseif arg == "--model"
        v, i = _need_value(args, i, arg); opts.model = v
    elseif arg == "--api-key"
        v, i = _need_value(args, i, arg); opts.api_key = v
    elseif arg == "--thinking"
        v, i = _need_value(args, i, arg); opts.thinking = v
    elseif arg == "-t" || arg == "--tools"
        v, i = _need_value(args, i, arg); opts.tools = v
    elseif arg == "-xt" || arg == "--exclude-tools"
        v, i = _need_value(args, i, arg); opts.exclude_tools = v
    elseif arg == "-nbt" || arg == "--no-builtin-tools"
        opts.no_builtin_tools = true
    elseif arg == "-nt" || arg == "--no-tools"
        opts.no_tools = true
    elseif arg == "-c" || arg == "--continue"
        opts.continue_session = true
    elseif arg == "-r" || arg == "--resume"
        opts.resume = true
    elseif arg == "--session"
        v, i = _need_value(args, i, arg); opts.session = v
    elseif arg == "--session-id"
        v, i = _need_value(args, i, arg); opts.session_id = v
    elseif arg == "--fork"
        v, i = _need_value(args, i, arg); opts.fork = v
    elseif arg == "--session-dir"
        v, i = _need_value(args, i, arg); opts.session_dir = v
    elseif arg == "--no-session"
        opts.no_session = true
    elseif arg == "-n" || arg == "--name"
        v, i = _need_value(args, i, arg); opts.name = v
    elseif arg == "--system-prompt"
        v, i = _need_value(args, i, arg)
        opts.system_prompt = isfile(v) ? read(v, String) : v
    elseif arg == "--append-system-prompt"
        v, i = _need_value(args, i, arg)
        push!(opts.append_system_prompt, isfile(v) ? read(v, String) : v)
    elseif arg == "--no-context-files"
        opts.no_context_files = true
    elseif arg == "-a" || arg == "--approve"
        opts.approve = true
    elseif arg == "-na" || arg == "--no-approve"
        opts.approve = false
    elseif arg == "--offline"
        opts.offline = true
    elseif arg == "--list-models"
        if i < length(args) && !startswith(args[i + 1], "-")
            opts.list_models = args[i + 1]
            i += 1
        else
            opts.list_models = ""
        end
    elseif arg == "-v" || arg == "--version"
        opts.version = true
    elseif arg == "-h" || arg == "--help"
        opts.help = true
    else
        throw(CLIError("Unknown option: $(arg)"))
    end
    return i
end

function parse_cli(args)
    opts = CLIOptions()
    i = 1
    prompt_args = String[]
    while i <= length(args)
        arg = args[i]
        if arg == "--"
            append!(prompt_args, args[i+1:end])
            break
        elseif startswith(arg, "-") && arg != "-"
            i = _assign_option!(opts, arg, args, i)
        else
            push!(prompt_args, arg)
        end
        i += 1
    end
    for part in prompt_args
        if startswith(part, '@') && length(part) > 1
            opts.mode == "rpc" && throw(CLIError("@file is not supported in RPC mode"))
            path = part[2:end]
            file = _read_prompt_file(path)
            file.text === nothing || push!(opts.prompt_parts, file.text)
            file.image === nothing || push!(opts.images, file.image)
        else
            push!(opts.prompt_parts, part)
        end
    end
    opts.mode === nothing && (opts.mode = (is_tty(stdin) && is_tty(stdout)) ? "repl" : "text")
    opts.mode in ("text", "json", "rpc") || throw(CLIError("Invalid mode: $(opts.mode)"))
    opts.print && (opts.mode = "text")
    if opts.thinking !== nothing
        opts.thinking in PiAI.THINKING_LEVELS || throw(CLIError("Invalid thinking level: $(opts.thinking)"))
    end
    opts.session_id === nothing ||
        occursin(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$", opts.session_id) ||
        throw(CLIError("Invalid session id: $(opts.session_id)"))
    return opts
end

function initial_prompt(opts::CLIOptions)
    return join(opts.prompt_parts, " ")
end

function resolve_tool_names(opts::CLIOptions, defaults=DEFAULT_TOOL_NAMES)
    names = String[defaults...]
    if opts.no_tools
        return String[]
    end
    opts.no_builtin_tools && empty!(names)
    if opts.tools !== nothing
        requested = String[strip(x) for x in split(opts.tools, ',') if !isempty(strip(x))]
        if !isempty(requested) && all(x -> startswith(x, '+') || startswith(x, '-'), requested)
            for item in requested
                name = item[2:end]
                if startswith(item, '+')
                    name in names || push!(names, name)
                else
                    filter!(x -> x != name, names)
                end
            end
        else
            names = requested
        end
    end
    if opts.exclude_tools !== nothing
        patterns = [strip(x) for x in split(opts.exclude_tools, ',') if !isempty(strip(x))]
        filter!(names) do name
            !any(p -> p == "*" || occursin(Regex("^" * replace(p, "*" => ".*") * "\$"), name), patterns)
        end
    end
    return names
end

const HELP_TEXT = """
Usage: pikit [options] [prompt]

Options:
  -p, --print                 Print the final response and exit
  --mode <text|json|rpc>      Output mode (default: TTY -> repl, otherwise text)
  --provider <name>           Provider name
  --model <provider/id>       Model selector or plain model id
  --api-key <key>             API key override
  --thinking <level>          off|minimal|low|medium|high|xhigh|max
  -t, --tools <list>          Comma-separated tools; +/- form modifies defaults
  -xt, --exclude-tools <list> Remove tools; supports *
  -nbt, --no-builtin-tools    Start from an empty tool set
  -nt, --no-tools             Disable all tools
  -c, --continue              Continue the latest session
  -r, --resume                Resume a session by index
  --session <path|id>         Session file or id
  --session-id <id>           Use a specific session id
  --fork <entry-id>           Fork the active branch at an entry
  --session-dir <dir>         Session storage directory
  --no-session                Do not persist the session
  -n, --name <name>           Session name
  --system-prompt <text|file> Replace the default preamble
  --append-system-prompt <text|file>  Append to the system prompt (repeatable)
  --no-context-files          Do not load AGENTS.md/CLAUDE.md
  -a, --approve               Trust project settings
  -na, --no-approve           Ignore project settings
  --offline                   Disable tool downloads
  --list-models [search]      List available models
  -v, --version               Print version
  -h, --help                  Show this help
"""

function list_models_text(search=nothing)
    models = all_models()
    if search !== nothing && !isempty(search)
        models = [m for m in models if occursin(lowercase(search), lowercase(m.provider * "/" * m.id)) ||
                                        occursin(lowercase(search), lowercase(m.name))]
    end
    sort!(models; by=m -> (m.provider, m.id))
    return join(["$(m.provider)/$(m.id)\t$(m.name)" for m in models], "\n") * (isempty(models) ? "" : "\n")
end
