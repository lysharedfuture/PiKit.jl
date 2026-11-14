using Documenter
import PiKit
import PiAISDK
import PiAgentCore
import PiCodingAgent

makedocs(
    sitename = "PiKit.jl",
    authors = "PiKit contributors",
    modules = [PiKit, PiAISDK, PiAgentCore, PiCodingAgent],
    pages = [
        "Home" => "index.md",
        "CLI" => "cli.md",
        "PiKit (CLI API)" => "pikit.md",
        "PiAISDK" => "sdk.md",
        "PiAgentCore" => "agent-core.md",
        "PiCodingAgent" => "coding-agent.md",
        "JSON events" => "json.md",
        "Sessions" => "sessions.md",
        "Upstream compatibility" => "upstream-compat.md",
        "Julia improvements" => "julia-improvements.md",
    ],
    checkdocs = :exports,
)

if get(ENV, "DOCUMENTER_KEY", "") != ""
    deploydocs(
        repo = "github.com/lysharedfuture/PiKit.jl.git",
        devbranch = "main",
        push_preview = false,
    )
end
