#!/usr/bin/env julia
# Behavioral snapshot of the CLI/library contract. Run with --write-baseline
# on the pre-split tree, then --check on every later tree.
#
#   julia --project=. scripts/snapshot-regression.jl --write-baseline
#   julia --project=. scripts/snapshot-regression.jl --check
#
# Artifacts live in test/fixtures/snapshots-v0.1/ and are canonicalized:
# volatile identifiers (uuids, entry ids, timestamps, temp paths) are replaced
# with placeholders and JSON objects are serialized with sorted keys.

using JSON

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SNAP_DIR = joinpath(ROOT, "test", "fixtures", "snapshots-v0.1")
const FIXTURE_DIR = joinpath(ROOT, "test", "fixtures")
const TEXT_FIXTURE = joinpath(FIXTURE_DIR, "faux_hello.json")
const TOOL_FIXTURE = joinpath(FIXTURE_DIR, "faux_toolcall.json")
const SEED = 20_261_111

const UUID_RE = r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
const ENTRY_ID_RE = r"^[0-9a-f]{8}$"
const ISO_RE = r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$"
const TS_PREFIX_RE = r"^\[[^\]]*\] "

struct RunResult
    stdout::String
    stderr::String
    code::Int
end

function run_child(workdir::String, args::Vector{String}; input::Union{Nothing,String}=nothing,
                   fixture::String=TEXT_FIXTURE, tmp::String=workdir)
    dir = mktempdir()
    out = joinpath(dir, "stdout")
    err = joinpath(dir, "stderr")
    inpath = joinpath(dir, "stdin")
    write(inpath, something(input, ""))
    wrapper = "using PiKit; using Random; Random.seed!($(SEED)); exit(PiKit.main())"
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(ROOT) -e $(wrapper) -- $(args)`
    env = copy(ENV)
    env["PIKIT_AGENT_DIR"] = tmp
    env["PIKIT_FAUX_RESPONSES"] = fixture
    env["JULIA_PKG_OFFLINE"] = "true"
    delete!(env, "PIKIT_LOG")
    delete!(env, "PIKIT_LOG_FILE")
    delete!(env, "PIKIT_LOG_STDERR")
    cmd = setenv(cmd, env; dir=workdir)
    proc = run(pipeline(ignorestatus(cmd); stdin=inpath, stdout=out, stderr=err); wait=true)
    return RunResult(read(out, String), read(err, String), proc.exitcode)
end

function scrub(s::AbstractString, tmp::String)
    isempty(tmp) || (s = replace(s, tmp => "<tmp>"))
    occursin(ISO_RE, s) && return "<ts>"
    occursin(UUID_RE, s) && return "<uuid>"
    occursin(ENTRY_ID_RE, s) && return "<id>"
    return String(s)
end

function canonical_json_line(line::AbstractString, tmp::String)
    parsed = try
        JSON.parse(line)
    catch
        return scrub(strip(line), tmp)
    end
    io = IOBuffer()
    write_json_sorted(io, parsed, tmp)
    return String(take!(io))
end

const VOLATILE_KEYS = Dict(
    "timestamp" => "\"<ts>\"",
    "createdAt" => "\"<ts>\"",
    "durationMs" => "0",
)

function write_json_sorted(io::IO, x::AbstractDict, tmp::String)
    pairs_sorted = sort(collect(x); by=p -> String(p.first))
    print(io, '{')
    for (i, (k, v)) in enumerate(pairs_sorted)
        i > 1 && print(io, ',')
        key = String(k)
        print(io, JSON.json(key), ':')
        placeholder = get(VOLATILE_KEYS, key, nothing)
        if placeholder === nothing
            write_json_sorted(io, v, tmp)
        else
            print(io, placeholder)
        end
    end
    print(io, '}')
    return nothing
end

function write_json_sorted(io::IO, x::AbstractVector, tmp::String)
    print(io, '[')
    for (i, v) in enumerate(x)
        i > 1 && print(io, ',')
        write_json_sorted(io, v, tmp)
    end
    print(io, ']')
    return nothing
end

write_json_sorted(io::IO, x::AbstractString, tmp::String) = print(io, JSON.json(scrub(x, tmp)))
write_json_sorted(io::IO, x, tmp::String) = print(io, JSON.json(x))

function canonical_lines(text::AbstractString, tmp::String)
    lines = String[]
    for line in split(text, '\n')
        isempty(strip(line)) && continue
        push!(lines, canonical_json_line(line, tmp))
    end
    return join(lines, "\n") * (isempty(lines) ? "" : "\n")
end

const LOG_CHILD = raw"""
import PiKit
using Logging
const path = ARGS[1]
for spec in ("info", "debug", "pikit_logging=error,ai_json=debug")
    logger = PiKit.TagFilterLogger(; file=path, stderr=false, spec=spec)
    for group in ("ai_json", "pikit_logging", "unknown_tag")
        for level in (Logging.Debug, Logging.Info, Logging.Error)
            enabled = Logging.shouldlog(logger, level, PiKit, group, :probe)
            println("spec=", spec, " group=", group, " level=", lowercase(string(level)),
                    " enabled=", enabled)
        end
    end
    Logging.with_logger(logger) do
        for group in ("ai_json", "pikit_logging", "unknown_tag")
            @debug "probe" _group = group
            @info "probe" _group = group
            @error "probe" _group = group
        end
    end
    close(logger.sink)
end
logger = PiKit.TagFilterLogger(; file=nothing, stderr=true, spec="info")
println("min_enabled=", Logging.min_enabled_level(logger))
"""

function log_snapshot(tmp::String)
    dir = mktempdir()
    script = joinpath(dir, "log_probe.jl")
    logfile = joinpath(dir, "probe.log")
    write(script, LOG_CHILD)
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(ROOT) $(script) $(logfile)`
    env = copy(ENV)
    env["PIKIT_AGENT_DIR"] = joinpath(tmp, "log-agent")
    delete!(env, "PIKIT_LOG")
    delete!(env, "PIKIT_LOG_FILE")
    delete!(env, "PIKIT_LOG_STDERR")
    out_path = joinpath(dir, "stdout")
    err_path = joinpath(dir, "stderr")
    proc = run(pipeline(ignorestatus(setenv(cmd, env)); stdin=devnull, stdout=out_path, stderr=err_path); wait=true)
    proc.exitcode == 0 || error("log probe failed: " * read(err_path, String))
    lines = String[]
    append!(lines, [strip(l) for l in split(read(out_path, String), '\n') if !isempty(strip(l))])
    if isfile(logfile)
        for line in split(read(logfile, String), '\n')
            isempty(strip(line)) && continue
            push!(lines, replace(strip(line), TS_PREFIX_RE => ""))
        end
    end
    return join(lines, "\n") * "\n"
end

function artifacts(tmp::String)
    work = joinpath(tmp, "work")
    mkpath(work)
    sessions = joinpath(tmp, "sessions")
    write(joinpath(work, "hello.txt"), "snapshot line\n")

    print_run = run_child(work, ["-p", "hi", "--provider", "faux", "--no-session"]; tmp=tmp)
    print_run.code == 0 || error("print mode failed: " * print_run.stderr)

    json_run = run_child(work, ["--mode", "json", "--provider", "faux", "--no-session", "hi"]; tmp=tmp)
    json_run.code == 0 || error("json mode failed: " * json_run.stderr)

    rpc_run = run_child(work, ["--mode", "rpc", "--provider", "faux", "--no-session"];
                        input="{\"id\":\"1\",\"type\":\"get_state\"}\n", tmp=tmp)
    rpc_run.code == 0 || error("rpc mode failed: " * rpc_run.stderr)

    tool_run = run_child(work, ["-p", "read it", "--provider", "faux", "--session-dir", sessions];
                         fixture=TOOL_FIXTURE, tmp=tmp)
    tool_run.code == 0 || error("tool session run failed: " * tool_run.stderr)

    files = sort(filter(f -> endswith(f, ".jsonl"), collect(Iterators.flatten(
        [joinpath(r, f) for f in fs] for (r, _, fs) in walkdir(sessions)))))
    isempty(files) && error("no session file written")
    session_text = read(files[1], String)

    return Dict(
        "print.txt" => print_run.stdout,
        "json.jsonl" => canonical_lines(json_run.stdout, tmp),
        "rpc_get_state.json" => canonical_lines(rpc_run.stdout, tmp),
        "session.jsonl" => canonical_lines(session_text, tmp),
        "log_filter.txt" => log_snapshot(tmp),
        "tool_print.txt" => tool_run.stdout,
    )
end

function compare(expected::String, actual::String)
    expected == actual && return nothing
    exp_lines = split(expected, '\n')
    act_lines = split(actual, '\n')
    for i in 1:max(length(exp_lines), length(act_lines))
        e = i <= length(exp_lines) ? exp_lines[i] : "<missing>"
        a = i <= length(act_lines) ? act_lines[i] : "<missing>"
        e == a && continue
        return "line $i\n  expected: $e\n  actual:   $a"
    end
    return "content differs in length only"
end

function main(args)
    write_baseline = "--write-baseline" in args
    check = "--check" in args
    (write_baseline || check) || error("usage: snapshot-regression.jl --write-baseline|--check")
    isfile(TEXT_FIXTURE) || error("missing fixture $(TEXT_FIXTURE)")
    isfile(TOOL_FIXTURE) || error("missing fixture $(TOOL_FIXTURE)")
    failed = false
    mktempdir() do tmp
        produced = try
            artifacts(tmp)
        catch err
            println(stderr, "FAIL: snapshot generation error: ", sprint(showerror, err))
            return exit(1)
        end
        if write_baseline
            mkpath(SNAP_DIR)
            for name in sort(collect(keys(produced)))
                write(joinpath(SNAP_DIR, name), produced[name])
                println("wrote ", relpath(joinpath(SNAP_DIR, name), ROOT))
            end
            return nothing
        end
        for name in sort(collect(keys(produced)))
            path = joinpath(SNAP_DIR, name)
            if !isfile(path)
                println(stderr, "FAIL: missing baseline $(relpath(path, ROOT))")
                failed = true
                continue
            end
            diff = compare(read(path, String), produced[name])
            if diff === nothing
                println("ok ", name)
            else
                println(stderr, "FAIL: $(name) differs from baseline\n", diff)
                failed = true
            end
        end
    end
    failed && exit(1)
    write_baseline || println("OK: snapshot matches baseline")
    return nothing
end

main(ARGS)
