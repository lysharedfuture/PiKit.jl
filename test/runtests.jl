using Test
using Logging

const TEST_AGENT_DIR = mktempdir()
ENV["PIKIT_AGENT_DIR"] = TEST_AGENT_DIR

import PiKit

const AI = PiKit.AI
const AC = PiKit.AgentCore
const CA = PiKit.CodingAgent

include("logging.jl")
include("coding/cli.jl")
include("coding/json_rpc.jl")
include("coding/json_mode.jl")
include("logging_audit.jl")
include("boundary_checker.jl")
