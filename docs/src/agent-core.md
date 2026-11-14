# Agent core

`PiAgentCore` implements the agent loop on top of `PiAISDK`: it streams
assistant responses, executes tool calls, and turns provider activity into a
uniform event stream. It sits between `PiAISDK` (messages, providers, streams)
and `PiCodingAgent` (tools, sessions, compaction).

Two entry levels are available:

- `run_agent_loop`, `run_agent_loop_continue` and `run_loop` drive an
  `AgentContext` with an `AgentLoopConfig`, an abort signal and an event
  callback.
- `Agent` is a stateful wrapper that owns messages, tools, listeners and
  steering/follow-up queues, and runs the loop in a background task.

## Hooks

`AgentLoopConfig` exposes hooks around each request and tool call:
`convert_to_llm`, `transform_context`, `prepare_request`, `prepare_next_turn`,
`finish_turn`, `before_tool_call`, `after_tool_call`,
`get_steering_messages` and `get_follow_up_messages`. Tool-level hooks are
declared on `Tool` (`prepare_arguments`) and `AgentLoopConfig`
(`before_tool_call`, `after_tool_call`).

## Events

`AbstractAgentEvent` covers agent start/end, turn start/end, message
start/update/end and tool execution start/update/end. Use `event_type` for the
wire name and `event_to_json` for a JSON-ready dictionary.

## API reference

```@autodocs
Modules = [PiAgentCore]
```
