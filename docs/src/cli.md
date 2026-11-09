# CLI

`bin/pikit [options] [prompt]`

Exit codes: `0` success, `1` request/tool failure or unhandled error, `2` invalid
arguments, `130` interrupted.

## Modes

| Mode | Trigger | stdout |
|---|---|---|
| text | `-p`, `--print`, or non-TTY default | final assistant text |
| json | `--mode json` | one JSON event per line (protocol only) |
| rpc | `--mode rpc` | one JSON response/event per line (protocol only) |
| repl | TTY default | streamed text + prompts |

`--` terminates option parsing; every following token is prompt text. `@path`
reads a text file into the prompt or attaches an image (png/jpeg/gif/webp/bmp)
as base64. `@path` is rejected in RPC mode.

Non-TTY stdin is read to EOF and prepended to the prompt. Empty prompt with a
TTY starts the REPL; empty prompt without a TTY exits `0`.

## Options

| Option | Value | Notes |
|---|---|---|
| `-p`, `--print` | flag | force text mode |
| `--mode` | `text\|json\|rpc` | default: TTY → repl, else text |
| `--provider` | name | provider override |
| `--model` | `provider/id` or id | model selector |
| `--api-key` | key | overrides auth.json/catalog/env |
| `--thinking` | `off\|minimal\|low\|medium\|high\|xhigh\|max` | non-reasoning models fall back to `off` |
| `-t`, `--tools` | comma list | all `+`/`-` items modify defaults; otherwise replace |
| `-xt`, `--exclude-tools` | comma list | applied last; `*` wildcard |
| `-nbt`, `--no-builtin-tools` | flag | start with an empty default set |
| `-nt`, `--no-tools` | flag | disable every tool |
| `-c`, `--continue` | flag | latest session in the current cwd |
| `-r`, `--resume` | flag | choose a session (TTY) or use latest |
| `--session` | path or id | load a specific session |
| `--session-id` | id | new session id; `[A-Za-z0-9._-]`, alnum ends |
| `--fork` | entry id | fork the active branch at an entry |
| `--session-dir` | dir | default `$PIKIT_SESSION_DIR` or `<agent>/sessions` |
| `--no-session` | flag | in-memory session |
| `-n`, `--name` | name | `session_info` entry |
| `--system-prompt` | text or file | replaces the default preamble |
| `--append-system-prompt` | text or file | repeatable; appended to addendum |
| `--no-context-files` | flag | skip AGENTS/CLAUDE context files |
| `-a`, `--approve` | flag | trust project `.pikit` settings |
| `-na`, `--no-approve` | flag | ignore project settings (default) |
| `--offline` | flag | disable the remaining fd download (temporary until fd_jll) |
| `--list-models` | optional search | `<provider>/<id>\t<name>` per line |
| `-v`, `--version` | flag | print version |
| `-h`, `--help` | flag | print help |

## Configuration precedence

CLI > trusted project `.pikit/settings.json` > user settings > defaults.
Context files (`AGENTS.md`, `CLAUDE.md`, overrides) are not affected by trust.
Authentication order: `--api-key`, `~/.pikit/auth.json`,
`~/.pikit/models.json` `apiKey`, provider environment variable.

## Environment

| Variable | Meaning |
|---|---|
| `PIKIT_AGENT_DIR` | agent state root (default `~/.pikit/agent`) |
| `PIKIT_SESSION_DIR` | session root |
| `PIKIT_LOG` | `info` (default), `debug`, or `tag=level,...` |
| `PIKIT_LOG_FILE` | log file path |
| `PIKIT_LOG_STDERR` | `1` mirrors logs to stderr |
| `PIKIT_OFFLINE` | `1` forbids the remaining fd download (temporary until fd_jll) |
| `PIKIT_FAUX_RESPONSES` | JSON array of scripted faux responses |
