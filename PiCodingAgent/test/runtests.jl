using Test
using Logging

const TEST_AGENT_DIR = mktempdir()
ENV["PIKIT_AGENT_DIR"] = TEST_AGENT_DIR
ENV["PIKIT_OFFLINE"] = "1"

using PiAI
using PiAgentCore
using PiCodingAgent

const AI = PiAI
const AC = PiAgentCore
const CA = PiCodingAgent

include("coding/truncate.jl")
include("coding/path_utils.jl")
include("coding/read.jl")
include("coding/edit.jl")
include("coding/write.jl")
include("coding/bash.jl")
include("coding/shell_env.jl")
include("coding/tools_manager.jl")
include("coding/search.jl")
include("coding/operations.jl")
include("coding/tool_details.jl")
include("coding/registry.jl")
include("coding/system_prompt.jl")
include("coding/session.jl")
include("coding/compaction.jl")
include("coding/config.jl")
include("coding/runtime.jl")
