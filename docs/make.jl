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
        "JSON events" => "json.md",
        "Sessions" => "sessions.md",
        "Upstream compatibility" => "upstream-compat.md",
        "Julia improvements" => "julia-improvements.md",
    ],
    checkdocs = :none,
)

if get(ENV, "DOCUMENTER_KEY", "") != ""
    deploydocs(
        repo = "github.com/lysharedfuture/PiKit.jl.git",
        devbranch = "main",
        push_preview = false,
    )
end
