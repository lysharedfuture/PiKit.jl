# Sessions

Sessions are append-only JSONL files under
`<agent>/sessions/--<cwd-slug>--/<timestamp>_<uuid>.jsonl`.

## Header

```json
{"type":"session","version":3,"id":"<uuid>","timestamp":"<ISO8601>","cwd":"...","parentSession":"..."}
```

`parentSession` appears on forks.

## Entries

Every entry has `type`, `id` (8 lowercase hex, falling back to UUID), `parentId`
(`null` at a root), and `timestamp` (ISO8601 UTC milliseconds).

Written by PiKit: `message`, `model_change`, `thinking_level_change`,
`compaction`, `session_info`.

Read-only: `context_edit` (`replacement: null` excludes its target from model
context; if the target is an assistant message its `toolResult` messages are
excluded too). Non-null replacements are preserved but not interpreted in v0.1.
Unknown entry types are kept as `UnknownEntry` (raw JSON preserved) and are
never rewritten.

Known entries retain unrecognized fields in an `extra` map; serialization starts
from that map and overwrites known fields, so fork/rewrite does not drop
upstream fields such as compaction `usage`, `details` or `fromHook`.

## Context reconstruction

`build_context` walks from the leaf to the root. With a compaction on the
branch, the latest compaction's `systemMessage` becomes the first system
message, the summary is added as a compaction summary message, messages from
`firstKeptEntryId` up to the compaction are kept (system messages in that range
are dropped when a `systemMessage` exists), and messages after the compaction
follow. Missing `firstKeptEntryId` falls back to keeping all messages. Then
`context_edit` exclusions are applied.

## Compaction

Triggers when estimated context tokens exceed
`contextWindow - reserveTokens` (default reserve 16384). Estimation anchors on
the last valid assistant `usage` and estimates only trailing messages with
`chars / 4` (images count 4800 chars). A cut point never lands on a tool result
and never splits an assistant turn: it backs up to the turn's user message.

The summary call uses the same provider, `max_tokens = min(model.maxTokens, 8192)`,
no tools, and retries with the session retry policy. Successful summaries append
a `compaction` entry (`tokensBefore`, `systemMessage`, `usage`). Failed, aborted
or length-truncated summaries append nothing.

## Persistence rules

`message_end` persists user, tool result and bash execution messages, plus
assistant messages whose stop reason is not `error`, `aborted` or `pending`.
`context_edit` replacement is not generated in v0.1.
