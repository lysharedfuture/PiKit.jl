@testset "package boundary checker" begin
    script = joinpath(dirname(@__DIR__), "scripts", "check-package-boundaries.jl")

    manifest(name, deps=String[]) = """
    name = "$(name)"
    uuid = "$(name == "PiAISDK" ? "9de19040-de4d-4d6c-8f46-3781ce430fcc" :
             name == "PiAgentCore" ? "d1542b5d-b113-412f-adf4-78ec6fbb7806" :
             name == "PiCodingAgent" ? "0b8fd38c-6e68-41ee-b4d7-56f7890dc08d" :
             "31a94650-92d9-47a7-b751-fcb2edf0c25a")"
    version = "0.2.0"
    $(isempty(deps) ? "" : "[deps]\n" * join(["$(d) = \"$(d)\"" for d in deps], "\n"))
    """

    function make_tree(dir)
        for (name, deps, source) in [
            ("PiAISDK", ["Logging"], "module PiAISDK\nusing Logging\nexport f\nf() = 1\nend\n"),
            ("PiAgentCore", ["PiAISDK", "Logging"],
             "module PiAgentCore\nusing PiAISDK\nusing Logging\nexport g\ng() = PiAISDK.f()\nend\n"),
            ("PiCodingAgent", ["PiAISDK", "PiAgentCore"],
             "module PiCodingAgent\nusing PiAISDK\nusing PiAgentCore\nexport h\nh() = PiAgentCore.g()\nend\n"),
            ("PiKit", ["PiAISDK", "PiAgentCore", "PiCodingAgent"],
             "module PiKit\nimport PiAISDK\nimport PiAgentCore\nimport PiCodingAgent\nexport main\nmain() = 0\nend\n"),
        ]
            root = name == "PiKit" ? dir : joinpath(dir, name)
            mkpath(joinpath(root, "src"))
            write(joinpath(root, "Project.toml"), manifest(name, deps))
            write(joinpath(root, "src", name * ".jl"), source)
        end
    end

    function run_check(dir)
        out = IOBuffer()
        err = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(dirname(script)) $(script) --root $(dir)`
        proc = run(pipeline(ignorestatus(cmd); stdout=out, stderr=err); wait=true)
        return proc.exitcode, String(take!(out)), String(take!(err))
    end

    dir = mktempdir()
    make_tree(dir)
    code, _, _ = run_check(dir)
    @test code == 0

    # reverse dependency is rejected
    write(joinpath(dir, "PiAISDK", "src", "bad.jl"), "using PiKit\n")
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("PiAISDK/src/bad.jl", err)
    @test occursin("PiKit", err)
    rm(joinpath(dir, "PiAISDK", "src", "bad.jl"))

    # relative module import is rejected
    write(joinpath(dir, "PiAISDK", "src", "rel.jl"), "using ..PiAgentCore\n")
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("relative module import", err)
    rm(joinpath(dir, "PiAISDK", "src", "rel.jl"))

    # cross-package include is rejected
    write(joinpath(dir, "PiCodingAgent", "src", "inc.jl"), "include(\"../../PiAISDK/src/PiAISDK.jl\")\n")
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("include escapes package src", err)
    rm(joinpath(dir, "PiCodingAgent", "src", "inc.jl"))

    # library packages must not carry CLI markers or export main
    write(joinpath(dir, "PiCodingAgent", "src", "cli_leak.jl"), "leak(args) = ARGS\n")
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("CLI argument access", err)
    write(joinpath(dir, "PiCodingAgent", "src", "cli_leak.jl"),
          "export main\nleak(args) = length(args)\n")
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("must not export main", err) || occursin("exports CLI symbols", err)
    rm(joinpath(dir, "PiCodingAgent", "src", "cli_leak.jl"))

    # absolute [sources] paths are rejected
    write(joinpath(dir, "PiAgentCore", "Project.toml"), """
    name = "PiAgentCore"
    uuid = "d1542b5d-b113-412f-adf4-78ec6fbb7806"
    version = "0.2.0"

    [deps]
    PiAISDK = "9de19040-de4d-4d6c-8f46-3781ce430fcc"
    Logging = "56ddb016-857b-54e1-b83d-db4d58db5568"

    [sources]
    PiAISDK = {path = "/abs/PiAISDK"}
    """)
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("absolute [sources] path", err)
end
