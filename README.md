# PiKit.jl

Unofficial Julia port of the [pi](https://github.com/earendil-works/pi) agent
stack (`pi-ai`, `pi-agent-core`, `pi-coding-agent`). The currently verified
upstream baseline, capability matrix, known deviations, and sync procedure are
tracked in [`docs/src/upstream-compat.md`](docs/src/upstream-compat.md).

PiKit is an independent MIT-licensed project. It is not affiliated with the
upstream authors.

## Install

Four packages make up the stack, in dependency order:

| Package | Contents |
|---|---|
| `PiAISDK` | message/content types, SSE streams, providers, model catalog, credentials, retry/overflow |
| `PiAgentCore` | agent loop, hooks, queues, abort, event model |
| `PiCodingAgent` | coding tools, session v3, compaction, system prompt, `AgentSession` runtime |
| `PiKit` | CLI (`print`/`json`/`rpc`/`repl`), config/trust, log sink, `PiKit.main` |

```julia
using Pkg
Pkg.add(["PiAISDK", "PiAgentCore", "PiCodingAgent", "PiKit"])  # once registered
Pkg.develop(path="/path/to/PiKit")   # local development: root project resolves the subpackages
```

`PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit` is the only allowed dependency
direction. Installing `PiAISDK` alone does not pull in the CLI, tools or session
implementation. Requires Julia 1.13+.

`using PiKit` keeps the v0.1 module paths: `PiKit.AI === PiAISDK`,
`PiKit.AgentCore === PiAgentCore`, `PiKit.CodingAgent === PiCodingAgent`.

### Upgrading from 0.1

- `PiKit.AI`, `PiKit.AgentCore` and the library part of `PiKit.CodingAgent`
  keep their exported symbols.
- `PiKit.CodingAgent.main` no longer exists; use `PiKit.main` (or
  `julia -m PiKit`).
- CLI helpers (`parse_cli`, `CLIOptions`, `HELP_TEXT`, `run_*_mode`,
  `build_runtime`, …) are exported by `PiKit`, not `PiCodingAgent`.
- `find` now ships fd via `fd_jll`; the runtime download path, the `--offline`
  flag and `PIKIT_OFFLINE` were removed.
- In scripts, prefer `import PiKit`. Julia runs a package's `@main` entry point
  when the package is `using`-loaded by a script, so `using PiKit` at the end of
  a script would execute the CLI with that script's arguments.

Installed CLI entry point (from an environment containing PiKit):

```sh
julia -m PiKit -p "hi"
julia -m PiKit --mode json -p "hi"
julia -m PiKit --version
```

From a repository checkout, `bin/pikit` is equivalent.

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

Known deviations are recorded in `docs/src/julia-improvements.md`. Failed
assistant messages are not persisted (upstream keeps them and filters them
with `context_edit`); upstream sessions containing `context_edit` are read
with `replacement: null` exclusion semantics.

## Development

```sh
for p in PiAISDK PiAgentCore PiCodingAgent .; do
  julia --project=$p -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
done
julia --project=scripts scripts/check-package-boundaries.jl
julia --project=scripts scripts/snapshot-regression.jl --check
julia scripts/check-julia-improvements.jl --phase 1 --strict --upstream .upstream
```

`scripts/snapshot-regression.jl --write-baseline` is only for a deliberate
behavior change; the diff must be explained in the commit.

Log tags are namespaced by package (`ai_*`, `agent_core_*`, `coding_*`,
`pikit_*`), so `PIKIT_LOG=ai_json=debug,coding_tools_read=debug` keeps working
across the split.

See `docs/src/cli.md`, `docs/src/json.md` and `docs/src/sessions.md`.
