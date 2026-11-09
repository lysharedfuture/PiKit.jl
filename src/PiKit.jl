module PiKit

using Dates
using Logging

include("logging.jl")

include("ai/AI.jl")
include("agent_core/AgentCore.jl")
include("coding/CodingAgent.jl")

"""`julia -m PiKit ...` entry point. Returns a process exit code."""
function (@main)(args)
    return CodingAgent.main(args)
end

"""Programmatic entry point using the process arguments."""
main() = CodingAgent.main(ARGS)

function __init__()
    install_logging!()
    AI.__init__()
    return nothing
end

end # module PiKit
