# PiKit (CLI API)

`PiKit` is the CLI and aggregate layer. It re-exports the v0.1 module paths as
`const` aliases and owns argument parsing, the four output modes and the log
sink.

```julia
using PiKit

PiKit.AI === PiAISDK            # true
PiKit.AgentCore === PiAgentCore # true
PiKit.CodingAgent === PiCodingAgent # true

opts = PiKit.parse_cli(["-p", "--model", "faux/faux-1", "hello"])
PiKit.initial_prompt(opts)      # "hello"
```

Programmatic entry points:

```julia
PiKit.main()          # uses ARGS, returns the exit code
```

Note: Julia runs a package's `@main` entry point when the package is
`using`-loaded by a script, so scripts should `import PiKit` instead of
`using PiKit`.

## API reference

```@autodocs
Modules = [PiKit]
```
