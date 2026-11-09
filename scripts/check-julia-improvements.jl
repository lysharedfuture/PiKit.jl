#!/usr/bin/env julia
# Check docs/src/julia-improvements.md against the required topics table in
# specs/development-process/spec.md.

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SPEC = joinpath(ROOT, "specs", "development-process", "spec.md")
const DOCS = joinpath(ROOT, "docs", "src", "julia-improvements.md")
const FIELDS = ["上游", "观察", "Julia 方案", "结论"]
const CONCLUSIONS = ["采纳", "建议上游", "Julia 生态缺口"]

struct Topic
    phase::Int
    wave::String
    id::String
    topic::String
end

function parse_topics(path)
    topics = Topic[]
    for line in eachline(path)
        m = match(r"^\|\s*(\d+)\s*\|\s*(\w+)\s*\|\s*([0-9A-Za-z]+-\d+)\s*\|\s*(.*?)\s*\|\s*$", line)
        m === nothing && continue
        push!(topics, Topic(parse(Int, m.captures[1]), m.captures[2], m.captures[3], m.captures[4]))
    end
    return topics
end

function parse_records(path)
    records = Dict{String,Dict{String,String}}()
    order = String[]
    current = nothing
    for line in eachline(path)
        m = match(r"^###\s+([0-9A-Za-z]+-\d+)\s+(.*)$", line)
        if m !== nothing
            current = m.captures[1]
            records[current] = Dict{String,String}("title" => m.captures[2])
            push!(order, current)
            continue
        end
        startswith(line, "## ") && (current = nothing)
        current === nothing && continue
        fm = match(r"^-\s*(上游|观察|Julia 方案|结论)[:：]\s*(.*)$", line)
        fm === nothing && continue
        records[current][fm.captures[1]] = strip(fm.captures[2])
    end
    return records, order
end

function check_anchor(anchor, upstream_dir)
    m = match(r"^(.+):(\d+)$", anchor)
    m === nothing && return false, "anchor must be <path>:<line>"
    rel = m.captures[1]
    line_no = parse(Int, m.captures[2])
    path = joinpath(upstream_dir, rel)
    isfile(path) || return false, "missing upstream file $(rel)"
    n = countlines(path)
    line_no <= n || return false, "line $(line_no) beyond EOF ($(n)) in $(rel)"
    return true, nothing
end

function fail(messages)
    for msg in messages
        println(stderr, "FAIL: ", msg)
    end
    exit(1)
end

function main(args)
    structure = "--structure" in args
    strict = "--strict" in args
    wave = nothing
    phase = nothing
    all = "--all" in args
    upstream_dir = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--wave"
            i < length(args) || error("--wave requires a value")
            wave = args[i+1]; i += 1
        elseif a == "--phase"
            i < length(args) || error("--phase requires a value")
            phase = tryparse(Int, args[i+1]); i += 1
        elseif a == "--upstream"
            i < length(args) || error("--upstream requires a path")
            upstream_dir = args[i+1]; i += 1
        elseif !startswith(a, "--")
            upstream_dir = a
        end
        i += 1
    end
    topics = parse_topics(SPEC)
    isempty(topics) && fail(["no required topics found in $(SPEC)"])
    records, order = parse_records(DOCS)
    known = Set(t.id for t in topics)
    problems = String[]

    for id in order
        id in known || push!(problems, "unknown improvement ID: $(id)")
    end
    for t in topics
        haskey(records, t.id) || push!(problems, "missing record $(t.id) ($(t.topic))")
    end

    selected = if wave !== nothing
        filter(t -> t.wave == wave, topics)
    elseif phase !== nothing
        filter(t -> t.phase == phase, topics)
    elseif all
        topics
    else
        Topic[]
    end
    wave !== nothing && isempty(selected) && push!(problems, "unknown wave: $(wave)")
    phase !== nothing && isempty(selected) && push!(problems, "unknown phase: $(phase)")

    if !structure
        for t in selected
            rec = get(records, t.id, nothing)
            rec === nothing && continue
            for field in FIELDS
                value = get(rec, field, "")
                isempty(value) && push!(problems, "$(t.id) missing $(field)")
                if strict && (occursin("未记录", value) || occursin("TODO", value))
                    push!(problems, "$(t.id) still has a placeholder in $(field)")
                end
            end
            if haskey(rec, "结论") && !(rec["结论"] in CONCLUSIONS)
                push!(problems, "$(t.id) invalid conclusion: $(rec["结论"])")
            end
        end
        if !strict
            for t in selected
                rec = get(records, t.id, nothing)
                rec === nothing && continue
                for field in ["上游", "观察"]
                    isempty(get(rec, field, "")) && push!(problems, "$(t.id) missing $(field)")
                end
            end
        end
    end

    if upstream_dir !== nothing && isdir(upstream_dir)
        for (id, rec) in records
            anchor = get(rec, "上游", "")
            isempty(anchor) && continue
            ok, msg = check_anchor(anchor, upstream_dir)
            ok || push!(problems, "$(id) invalid upstream anchor: $(msg)")
        end
    elseif upstream_dir !== nothing
        push!(problems, "upstream snapshot not found: $(upstream_dir)")
    else
        println("note: 锚点未校验 (no --upstream snapshot)")
    end

    if !isempty(problems)
        fail(problems)
    end
    scope = wave !== nothing ? "wave $(wave)" : phase !== nothing ? "phase $(phase)" :
            all ? "all phases" : "structure"
    println("OK: $(scope) $(length(selected) == 0 ? "" : "($(length(selected)) required topics)")")
    return nothing
end

main(ARGS)
