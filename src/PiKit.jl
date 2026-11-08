module PiKit

using Dates
using Logging

include("logging.jl")

include("ai/AI.jl")
include("agent_core/AgentCore.jl")
include("coding/CodingAgent.jl")

"""Entry point for the `pikit` CLI. Returns a process exit code."""
main(args=ARGS) = CodingAgent.main(args)

function __init__()
    install_logging!()
    AI.__init__()
    return nothing
end

end # module PiKit
