using Test
using Logging

const TEST_AGENT_DIR = mktempdir()
ENV["PIKIT_AGENT_DIR"] = TEST_AGENT_DIR
ENV["PIKIT_OFFLINE"] = "1"

using PiKit

const AI = PiKit.AI
const AC = PiKit.AgentCore
const CA = PiKit.CodingAgent

include("mock/server.jl")
include("logging.jl")
include("ai/json_codec.jl")
include("ai/sse.jl")
include("ai/schema.jl")
include("ai/retry.jl")
include("ai/overflow.jl")
include("ai/models.jl")
include("ai/credentials.jl")
include("ai/event_stream.jl")
include("ai/faux.jl")
include("ai/openai.jl")
include("ai/anthropic.jl")
include("agent_core/loop.jl")
include("agent_core/tools.jl")
include("agent_core/agent.jl")
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
include("coding/cli.jl")
include("coding/runtime.jl")
include("coding/json_rpc.jl")
include("coding/json_mode.jl")
include("logging_audit.jl")
