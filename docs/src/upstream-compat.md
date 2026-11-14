# Upstream compatibility

This file is the single source of truth for the upstream `pi` baseline that
PiKit currently targets. `README.md`, `NOTICE`, and the fetch script must not
carry a permanent "pinned" version; update this file instead when a new
upstream revision is verified.

## Current verified baseline

| PiKit | Upstream source | Upstream packages | Verified |
|---|---|---|---|
| 0.2.x (2A split) | `earendil-works/pi` @ `06aa6563e4d51d6df5de6c9664c3a868f3f5bb2a` | `pi-ai`, `pi-agent-core`, `pi-coding-agent` (reported 1.5.0) | 2026-11-12 |

The baseline is an exact commit, not a floating npm range. Upstream package
versions can differ from the nearest release tag because the snapshot may be
ahead of the tag; the commit is authoritative for reproduction.

## Package layout

Upstream ships one npm package per layer; PiKit mirrors that mapping:

| PiKit package | Upstream package | Notes | Docs |
|---|---|---|---|
| `PiAISDK` | `@earendil-works/pi-ai` | `HTTP`/`JSON` + stdlib only | [sdk.md](sdk.md) |
| `PiAgentCore` | `@earendil-works/pi-agent-core` | depends on `PiAISDK` | [agent-core.md](agent-core.md) |
| `PiCodingAgent` | `@earendil-works/pi-coding-agent` (library part) | tools, session, compaction, runtime | [coding-agent.md](coding-agent.md) |
| `PiKit` | `@earendil-works/pi-coding-agent` (CLI/aggregate part) | `print`/`json`/`rpc`/`repl`, config, log sink | [pikit.md](pikit.md) |

Upstream exports CLI parsing from the `pi-coding-agent` package root
(`packages/coding-agent/src/index.ts:3`); PiKit deliberately keeps the library
package free of CLI symbols and puts them in `PiKit` (D6).

## Compatibility matrix

| Area | Status | Evidence |
|---|---|---|
| AI content/message types, JSON codec, `extra` preservation | ported | `PiAISDK/test/ai/json_codec.jl` |
| SSE parsing, event stream, abort polling | ported | `PiAISDK/test/ai/sse.jl`, `PiAISDK/test/ai/event_stream.jl` |
| JSON Schema subset (`validate_arguments`) | ported | `PiAISDK/test/ai/schema.jl` |
| Model catalog, credentials, retry/overflow classification | ported | `PiAISDK/test/ai/models.jl`, `PiAISDK/test/ai/credentials.jl`, `PiAISDK/test/ai/retry.jl` |
| `openai-completions` provider | ported (HTTP SSE) | `PiAISDK/test/ai/openai.jl` |
| `anthropic-messages` provider | ported (HTTP SSE) | `PiAISDK/test/ai/anthropic.jl` |
| `faux` provider | ported | `PiAISDK/test/ai/faux.jl` |
| Agent loop, hooks, parallel tools, queues, abort, listeners | ported | `PiAgentCore/test/agent_core/*` |
| `read/bash/powershell/edit/write/grep/find/ls` | ported (grep via `ripgrep_jll`, find via `fd_jll`) | `PiCodingAgent/test/coding/*` |
| Session v3 read/write/fork, unknown entries, `context_edit: null` | ported | `PiCodingAgent/test/coding/session.jl` |
| Compaction and overflow recovery | ported subset | `PiCodingAgent/test/coding/compaction.jl` |
| print/JSON/RPC/REPL modes | ported | `test/coding/json_rpc.jl`, `test/coding/json_mode.jl` |
| File-first logging with per-file tags | ported | `test/logging.jl`, `test/logging_audit.jl` |
| Package boundaries and snapshot equality | ported | `scripts/check-package-boundaries.jl`, `scripts/snapshot-regression.jl` |

## Known deviations

- Failed assistant messages are not persisted; upstream keeps them and filters
  them with `context_edit { replacement: null }`. PiKit applies the exclusion
  when reading upstream sessions.
- `context_edit` non-null replacement is preserved but not interpreted.
- Compaction does not implement split-turn prefix summaries; cut points back up
  to the start of the user turn.
- Deferred responses are recognized but not polled.
- Full-screen TUI, extensions, skills, themes, MCP, codemode, OAuth login, HTML
  export, image resizing, branch summarization, telemetry,
  `tool.replay`/`output_schema` are out of phase 1.

## Syncing a new upstream revision

1. Fetch a candidate snapshot:

   ```sh
   PI_UPSTREAM_REF=<commit-or-tag> scripts/fetch-upstream.sh
   ```

   Remove `.upstream/` first if it already contains a snapshot.

2. Diff the protocol surfaces:
   - `packages/ai/src/types.ts` and provider adapters
   - `packages/agent/src/agent-loop.ts`, `agent.ts`
   - `packages/coding-agent/src/core/session-manager.ts`
   - upstream `docs/json.md`, `docs/session-format.md`
3. Add or update tests for changed wire shapes; unknown fields must continue to
   round-trip through `extra`.
4. Run the full gate:

   ```sh
   PIKIT_AGENT_DIR=$(mktemp -d) julia --project=. -e 'using Pkg; Pkg.test()'
   julia scripts/check-julia-improvements.jl --phase 1 --strict --upstream .upstream
   ```

5. Update the table above, `docs/src/julia-improvements.md`, and the PiKit version
   if behavior or compatibility changed.
6. Commit, tag, and release PiKit on its own semantic version; do not rewrite
   historical change records that mention older upstream baselines.

## Policy

- PiKit's version is independent of upstream `pi` versions.
- A new upstream revision is "verified" only after the full test gate passes
  and this matrix is updated.
- Protocol additions should be additive: unknown fields go to `extra`, unknown
  session entries remain `UnknownEntry`, and new events must not change the
  meaning of existing ones.
- `README.md` links here instead of claiming a permanent pin.
