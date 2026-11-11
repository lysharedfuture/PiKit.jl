module PiKit

using Dates
using Logging

include("logging.jl")

using PiCodingAgent
using PiAISDK: all_models, find_model, json_parse, json_write, load_faux_responses,
            register_faux_provider!
import PiAISDK
import PiAgentCore

# v0.1 module paths. The bindings are the packages themselves, so type identity
# is shared with `using PiAISDK` / `using PiAgentCore` / `using PiCodingAgent`.
const AI = PiAISDK
const AgentCore = PiAgentCore
const CodingAgent = PiCodingAgent

include("cli/options.jl")
include("cli/modes/print.jl")
include("cli/modes/json.jl")
include("cli/modes/rpc.jl")
include("cli/modes/repl.jl")
include("cli/main.jl")

export main, parse_cli, CLIOptions, CLIError, HELP_TEXT, list_models_text,
       resolve_tool_names, initial_prompt, run_print_mode, run_json_mode,
       run_rpc_mode, run_repl_mode, json_mode_event, session_json_event, build_runtime

"""`julia -m PiKit ...` entry point. Returns a process exit code."""
function (@main)(args)
    return cli_main(args)
end

"""Programmatic entry point using the process arguments."""
main() = cli_main(ARGS)

function __init__()
    install_logging!()
    return nothing
end

end # module PiKit
