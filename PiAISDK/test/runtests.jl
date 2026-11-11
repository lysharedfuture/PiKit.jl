using Test
using Logging

const TEST_AGENT_DIR = mktempdir()
ENV["PIKIT_AGENT_DIR"] = TEST_AGENT_DIR
ENV["PIKIT_OFFLINE"] = "1"

using PiAISDK

const AI = PiAISDK

include("mock/server.jl")
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
include("logging_boundary.jl")
