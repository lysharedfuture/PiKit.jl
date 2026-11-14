# PiCodingAgent

`PiCodingAgent` is the coding-agent library layer of PiKit: the file and shell
tools, the session v3 JSONL format, compaction, the system-prompt builder, and
the `AgentSession` runtime. It sits between `PiAgentCore` and the `PiKit` CLI in
the dependency chain `PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit`, and
corresponds to the library part of upstream `@earendil-works/pi-coding-agent`.

A minimal session:

```julia
using PiAISDK, PiCodingAgent

cwd = mktempdir()
PiAISDK.set_responses!([PiAISDK.faux_text("done")])

manager = create_session(cwd; dir=cwd, in_memory=true)
session = create_agent_session(
    cwd=cwd,
    model=PiAISDK.find_model("faux/faux-1"),
    session_manager=manager,
    settings=Dict{String,Any}("autoCompaction" => false),
    tools_names=String[],
)
prompt!(session, "hi")
close!(session)
```

Tools are created with [`create_tools`](@ref PiCodingAgent.create_tools) (or [`create_tool`](@ref PiCodingAgent.create_tool));
`grep` is backed by `ripgrep_jll` and `find` by `fd_jll`, so no binaries are
downloaded at runtime. Sessions are JSONL files managed by
[`create_session`](@ref PiCodingAgent.create_session), [`load_session`](@ref PiCodingAgent.load_session), [`fork_session`](@ref PiCodingAgent.fork_session), and
[`build_context`](@ref PiCodingAgent.build_context); [`compact!`](@ref PiCodingAgent.compact!) summarizes older context when the
window fills up.

## API reference

```@autodocs
Modules = [PiCodingAgent]
```
