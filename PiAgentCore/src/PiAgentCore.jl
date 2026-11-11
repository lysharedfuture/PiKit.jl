module PiAgentCore

using Logging
using PiAI

include("types.jl")
include("loop.jl")
include("agent.jl")

export Tool, ToolResult, to_tool_declaration, AgentContext, AgentLoopConfig,
       AbstractAgentEvent, AgentStartEvent, AgentEndEvent, TurnStartEvent, TurnEndEvent,
       MessageStartEvent, MessageUpdateEvent, MessageEndEvent,
       ToolExecutionStartEvent, ToolExecutionUpdateEvent, ToolExecutionEndEvent,
       event_type, event_to_json, assistant_event_to_json, default_convert_to_llm,
       run_loop, run_agent_loop, run_agent_loop_continue, declare_tool_changes,
       PendingQueue, AgentState, Agent, system_prompt, subscribe, process_event!,
       prompt!, continue!, steer!, follow_up!, clear_queues!, peek_queued,
       abort!, wait_idle, reset!

end # module PiAgentCore
