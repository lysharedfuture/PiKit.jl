# PiKit.jl

Unofficial Julia port of the [pi](https://github.com/earendil-works/pi) agent
stack (`pi-ai`, `pi-agent-core`, `pi-coding-agent`), pinned to upstream commit
`06aa6563e4d51d6df5de6c9664c3a868f3f5bb2a` (v1.5.0).

PiKit is an independent MIT-licensed project. It is not affiliated with the
upstream authors.

## Install

```julia
using Pkg
Pkg.add("PiKit")          # once registered
Pkg.develop(path="/path/to/PiKit")  # local development
```

Requires Julia 1.13+. Runtime dependencies: `HTTP`, `JSON3`, stdlib only.

## Quick start (offline faux provider)

```sh
PIKIT_FAUX_RESPONSES=test/fixtures/faux_hello.json bin/pikit -p "hi"
# Hello from faux
```

Real providers:

```sh
export ANTHROPIC_API_KEY=...
bin/pikit --model anthropic/claude-sonnet-4-6 -p "hello"
```

Authentication order: `--api-key`, `~/.pikit/auth.json`,
`apiKey` in `~/.pikit/models.json`, then provider environment variables
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`,
`<PROVIDER>_API_KEY`).

## Modes

- `-p/--print`: one-shot text output, last assistant message.
- `--mode json`: JSONL event stream (stdout is protocol only).
- `--mode rpc`: line-delimited JSON commands/responses.
- default on a TTY: line-oriented REPL with slash commands.

## Compatibility scope (v0.1)

Implemented: AI message/content types, SSE streams, three providers
(`openai-completions`, `anthropic-messages`, `faux`), agent loop with hooks,
steering/follow-up queues and abort, eight coding tools, session format v3
subset, compaction, print/JSON/RPC/REPL entry points.

Not implemented: full-screen TUI, extensions, skills, themes, MCP, codemode,
OAuth login, HTML export, image resizing, branch summarization, telemetry,
`tool.replay`/`output_schema`, deferred polling, `context_edit` replacement
semantics, split-turn compaction summaries.

Known deviations are recorded in `docs/julia-improvements.md`. Failed
assistant messages are not persisted (upstream keeps them and filters them
with `context_edit`); upstream sessions containing `context_edit` are read
with `replacement: null` exclusion semantics.

## Development

```sh
PIKIT_AGENT_DIR=$(mktemp -d) julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia scripts/check-julia-improvements.jl --phase 1 --strict --upstream .upstream
```

See `docs/cli.md`, `docs/json.md` and `docs/sessions.md`.
