@testset "project rules checker" begin
    script = joinpath(dirname(@__DIR__), "scripts", "check-project-rules.jl")
    source = dirname(@__DIR__)

    function make_tree(dir)
        for name in ("PiKit", "PiAISDK", "PiAgentCore", "PiCodingAgent")
            pkg = name == "PiKit" ? dir : joinpath(dir, name)
            mkpath(pkg)
            write(joinpath(pkg, "Project.toml"), """
            name = "$(name)"
            uuid = "00000000-0000-0000-0000-00000000000$(length(name))"
            version = "0.2.0"

            [compat]
            julia = "1.13"
            """)
            write(joinpath(pkg, "LICENSE"), "MIT License\n")
            write(joinpath(pkg, "README.md"), """
            # $(name)

            Package purpose and its place in `PiAISDK ← PiAgentCore ← PiCodingAgent ← PiKit`.
            Install with `Pkg.add("$(name)")`; documentation at
            <https://lysharedfuture.github.io/PiKit.jl/dev/>.

            [![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://lysharedfuture.github.io/PiKit.jl/dev/)
            """)
        end
        mkpath(joinpath(dir, "docs", "src"))
        write(joinpath(dir, "docs", "make.jl"), """
        modules = [PiKit, PiAISDK, PiAgentCore, PiCodingAgent]
        pages = ["sdk.md", "agent-core.md", "coding-agent.md", "pikit.md"]
        checkdocs = :exports
        """)
        for (page, name) in [("sdk.md", "PiAISDK"), ("agent-core.md", "PiAgentCore"),
                             ("coding-agent.md", "PiCodingAgent"), ("pikit.md", "PiKit")]
            write(joinpath(dir, "docs", "src", page),
                  "# $(name)\n\n```@autodocs\nModules = [$(name)]\n```\n")
        end
        mkpath(joinpath(dir, ".github", "workflows"))
        write(joinpath(dir, ".github", "workflows", "TagBot.yml"), """
        steps:
          - uses: JuliaRegistries/TagBot@v1
          - uses: JuliaRegistries/TagBot@v1
            with:
              subdir: PiAISDK
          - uses: JuliaRegistries/TagBot@v1
            with:
              subdir: PiAgentCore
          - uses: JuliaRegistries/TagBot@v1
            with:
              subdir: PiCodingAgent
        """)
    end

    function run_check(dir)
        out = IOBuffer()
        err = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(source, "scripts")) $(script) --root $(dir)`
        proc = run(pipeline(ignorestatus(cmd); stdout=out, stderr=err); wait=true)
        return proc.exitcode, String(take!(out)), String(take!(err))
    end

    dir = mktempdir()
    make_tree(dir)
    code, _, _ = run_check(dir)
    @test code == 0

    # a subpackage without README is rejected
    mv(joinpath(dir, "PiCodingAgent", "README.md"), joinpath(dir, "README.bak"))
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("PiCodingAgent/README.md", err)
    mv(joinpath(dir, "README.bak"), joinpath(dir, "PiCodingAgent", "README.md"))

    # a subpackage without its own LICENSE is rejected
    mv(joinpath(dir, "PiAgentCore", "LICENSE"), joinpath(dir, "LICENSE.bak"))
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("PiAgentCore/LICENSE", err)
    mv(joinpath(dir, "LICENSE.bak"), joinpath(dir, "PiAgentCore", "LICENSE"))

    # TagBot must have one subdir step per subpackage
    text = read(joinpath(dir, ".github", "workflows", "TagBot.yml"), String)
    write(joinpath(dir, ".github", "workflows", "TagBot.yml"),
          replace(text, "subdir: PiCodingAgent\n" => ""))
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("subdir: PiCodingAgent", err)
    write(joinpath(dir, ".github", "workflows", "TagBot.yml"), text)

    # declared name must match the package directory
    write(joinpath(dir, "PiAISDK", "Project.toml"), """
    name = "PiAISDKCore"
    uuid = "9de19040-de4d-4d6c-8f46-3781ce430fcc"
    version = "0.2.0"

    [compat]
    julia = "1.13"
    """)
    code, _, err = run_check(dir)
    @test code != 0
    @test occursin("expected \"PiAISDK\"", err)

    # naming rules are checked independently (AutoMerge: >= 5 chars, no reserved forms)
    function run_name(name)
        out = IOBuffer()
        err = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(source, "scripts")) $(script) --check-name $(name)`
        proc = run(pipeline(ignorestatus(cmd); stdout=out, stderr=err); wait=true)
        return proc.exitcode, String(take!(err))
    end
    @test run_name("PiAISDK")[1] == 0
    code, err = run_name("PiAI")
    @test code != 0
    @test occursin("shorter than 5 characters", err)
    code, err = run_name("JuliaThing")
    @test code != 0
    @test occursin("must not start with Ju", err)
    code, err = run_name("Somethingjl")
    @test code != 0
    @test occursin("must not end with jl", err)
end
