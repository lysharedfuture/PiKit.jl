# JSON mode

`--mode json` writes one JSON object per line. stdout is protocol only; logs go
to the file sink (or stderr when `PIKIT_LOG_STDERR=1`).

The first line is the session header:

```json
{"type":"session","version":3,"id":"...","timestamp":"...","cwd":"..."}
```

## Event types

| `type` | Additional fields |
|---|---|
| `agent_start` | — |
| `agent_end` | `messages`, `willRetry` |
| `turn_start` | — |
| `turn_end` | `message`, `toolResults` |
| `message_start` | `message` |
| `message_update` | `message`, `assistantMessageEvent`, `usage` |
| `message_end` | `message` |
| `tool_execution_start` | `toolCallId`, `toolName`, `args` |
| `tool_execution_update` | `toolCallId`, `toolName`, `args`, `partialResult` |
| `tool_execution_end` | `toolCallId`, `toolName`, `args`, `result`, `isError`, `durationMs` |
| `queue_update` | `steering`, `followUp` |
| `thinking_level_changed` | `level` |
| `session_info_changed` | `name` |
| `entry_appended` | `entry` |
| `compaction_start` | `reason` (`manual\|threshold\|overflow`) |
| `compaction_end` | `reason`, `result`, `aborted`, `willRetry`, `errorMessage` |
| `auto_retry_start` | `attempt`, `maxAttempts`, `delayMs`, `errorMessage` |
| `auto_retry_end` | `success`, `attempt`, `finalError` |
| `summarization_retry_start` | `attempt`, `delayMs`, `errorMessage` |
| `summarization_retry_end` | `success`, `attempt` |
| `agent_settled` | `aborted` |

`message_update.assistantMessageEvent` never contains `partial`; the current
message lives in `message_update.message`, and `usage` is repeated at the top
level for clients that only track that event. `toolcall_start` additionally
carries `id` and `toolName`.

`willRetry` on `agent_end` is `true` only when the run is not aborted, auto
retry is enabled, the retry budget is not exhausted, and the last assistant
message is retryable.

## JSONL framing

Records are split on `\n` only. A leading `\r` is stripped. U+2028/U+2029 are
not record separators.
