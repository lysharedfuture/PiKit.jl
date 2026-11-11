using Test
using Logging

ENV["PIKIT_OFFLINE"] = "1"
ENV["PIKIT_AGENT_DIR"] = mktempdir()

using PiAISDK
using PiAgentCore

const AI = PiAISDK
const AC = PiAgentCore

include("agent_core/loop.jl")
include("agent_core/tools.jl")
include("agent_core/agent.jl")
