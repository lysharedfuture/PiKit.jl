const LOG_TAG = "coding_session"

const SESSION_VERSION = 3

abstract type AbstractSessionEntry end

struct SessionHeader
    id::String
    version::Int
    timestamp::String
    cwd::String
    parent_session::Union{Nothing,String}
    extra::Dict{String,Any}
end

struct MessageEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    message::PiAISDK.AbstractMessage
    extra::Dict{String,Any}
end

struct ModelChangeEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    provider::String
    model_id::String
    extra::Dict{String,Any}
end

struct ThinkingLevelChangeEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    thinking_level::String
    extra::Dict{String,Any}
end

struct UsageEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    kind::String
    provider::String
    model::String
    usage::PiAISDK.Usage
    note::Union{Nothing,String}
    extra::Dict{String,Any}
end

struct CompactionEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    summary::String
    first_kept_entry_id::String
    tokens_before::Int
    system_message::Union{Nothing,PiAISDK.SystemMessage}
    usage::Union{Nothing,PiAISDK.Usage}
    details::Any
    from_hook::Union{Nothing,Bool}
    extra::Dict{String,Any}
end

struct ContextEditEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    target_id::String
    replacement::Any
    extra::Dict{String,Any}
end

struct SessionInfoEntry <: AbstractSessionEntry
    id::String
    parent_id::Union{Nothing,String}
    timestamp::String
    name::Union{Nothing,String}
    extra::Dict{String,Any}
end

struct UnknownEntry <: AbstractSessionEntry
    id::Union{Nothing,String}
    parent_id::Union{Nothing,String}
    timestamp::Union{Nothing,String}
    entry_type::String
    raw::Dict{String,Any}
end

mutable struct SessionManager
    header::SessionHeader
    entries::Vector{AbstractSessionEntry}
    leaf_id::Union{Nothing,String}
    path::Union{Nothing,String}
    io::Union{Nothing,IO}
end

entry_id(e::AbstractSessionEntry) = e.id
entry_parent(e::AbstractSessionEntry) = e.parent_id

function now_iso()
    return Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS.sss") * "Z"
end

function new_entry_id(existing::Set{String})
    for _ in 1:100
        id = bytes2hex(rand(UInt8, 4))
        id in existing || return id
    end
    return string(uuid4())
end

function session_root(; dir=nothing)
    dir !== nothing && return String(dir)
    haskey(ENV, "PIKIT_SESSION_DIR") && return ENV["PIKIT_SESSION_DIR"]
    return joinpath(default_agent_dir(), "sessions")
end

function session_dir_for_cwd(cwd::String; dir=nothing)
    root = session_root(; dir=dir)
    slug = replace(strip(cwd, '/'), r"[/\\:]" => "-")
    return joinpath(root, "--" * slug * "--")
end

function header_to_json(h::SessionHeader)
    d = Dict{String,Any}(h.extra)
    d["type"] = "session"
    d["version"] = h.version
    d["id"] = h.id
    d["timestamp"] = h.timestamp
    d["cwd"] = h.cwd
    h.parent_session === nothing || (d["parentSession"] = h.parent_session)
    return d
end

function entry_to_json(e::MessageEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "message"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["message"] = PiAISDK.message_to_json(e.message)
    return d
end
function entry_to_json(e::ModelChangeEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "model_change"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["provider"] = e.provider; d["modelId"] = e.model_id
    return d
end
function entry_to_json(e::ThinkingLevelChangeEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "thinking_level_change"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["thinkingLevel"] = e.thinking_level
    return d
end
function entry_to_json(e::UsageEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "usage"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["kind"] = e.kind; d["provider"] = e.provider
    d["model"] = e.model; d["usage"] = PiAISDK.usage_to_json(e.usage)
    e.note === nothing || (d["note"] = e.note)
    return d
end
function entry_to_json(e::CompactionEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "compaction"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["summary"] = e.summary
    d["firstKeptEntryId"] = e.first_kept_entry_id; d["tokensBefore"] = e.tokens_before
    e.system_message === nothing || (d["systemMessage"] = PiAISDK.message_to_json(e.system_message))
    e.usage === nothing || (d["usage"] = PiAISDK.usage_to_json(e.usage))
    e.details === nothing || (d["details"] = e.details)
    e.from_hook === nothing || (d["fromHook"] = e.from_hook)
    return d
end
function entry_to_json(e::ContextEditEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "context_edit"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp; d["targetId"] = e.target_id; d["replacement"] = e.replacement
    return d
end
function entry_to_json(e::SessionInfoEntry)
    d = Dict{String,Any}(e.extra)
    d["type"] = "session_info"; d["id"] = e.id; d["parentId"] = e.parent_id
    d["timestamp"] = e.timestamp
    e.name === nothing || (d["name"] = e.name)
    return d
end
entry_to_json(e::UnknownEntry) = Dict{String,Any}(e.raw)

const ENTRY_KNOWN_KEYS = Dict(
    "message" => Set(["type", "id", "parentId", "timestamp", "message"]),
    "model_change" => Set(["type", "id", "parentId", "timestamp", "provider", "modelId"]),
    "thinking_level_change" => Set(["type", "id", "parentId", "timestamp", "thinkingLevel"]),
    "usage" => Set(["type", "id", "parentId", "timestamp", "kind", "provider", "model", "usage", "note"]),
    "compaction" => Set(["type", "id", "parentId", "timestamp", "summary", "firstKeptEntryId", "tokensBefore", "systemMessage", "usage", "details", "fromHook"]),
    "context_edit" => Set(["type", "id", "parentId", "timestamp", "targetId", "replacement"]),
    "session_info" => Set(["type", "id", "parentId", "timestamp", "name"]),
)

function _entry_extra(d, typ)
    known = get(ENTRY_KNOWN_KEYS, typ, Set{String}())
    return Dict{String,Any}(String(k) => plain(v) for (k, v) in d if !(String(k) in known))
end

function entry_from_json(d)
    typ = String(get(d, "type", ""))
    id = get(d, "id", nothing)
    parent_id = get(d, "parentId", nothing)
    timestamp = get(d, "timestamp", nothing)
    if typ == "message"
        return MessageEntry(String(id), parent_id, String(timestamp),
                            PiAISDK.message_from_json(get(d, "message", Dict{String,Any}())),
                            _entry_extra(d, typ))
    elseif typ == "model_change"
        return ModelChangeEntry(String(id), parent_id, String(timestamp),
                                String(get(d, "provider", "")), String(get(d, "modelId", "")),
                                _entry_extra(d, typ))
    elseif typ == "thinking_level_change"
        return ThinkingLevelChangeEntry(String(id), parent_id, String(timestamp),
                                        String(get(d, "thinkingLevel", "off")), _entry_extra(d, typ))
    elseif typ == "usage"
        return UsageEntry(String(id), parent_id, String(timestamp), String(get(d, "kind", "")),
                          String(get(d, "provider", "")), String(get(d, "model", "")),
                          PiAISDK.usage_from_json(get(d, "usage", nothing)), get(d, "note", nothing),
                          _entry_extra(d, typ))
    elseif typ == "compaction"
        sm = get(d, "systemMessage", nothing)
        return CompactionEntry(String(id), parent_id, String(timestamp),
                               String(get(d, "summary", "")), String(get(d, "firstKeptEntryId", "")),
                               Int(get(d, "tokensBefore", 0)),
                               sm === nothing ? nothing : PiAISDK.message_from_json(sm)::PiAISDK.SystemMessage,
                               get(d, "usage", nothing) === nothing ? nothing : PiAISDK.usage_from_json(d["usage"]),
                               get(d, "details", nothing), get(d, "fromHook", nothing), _entry_extra(d, typ))
    elseif typ == "context_edit"
        return ContextEditEntry(String(id), parent_id, String(timestamp),
                                String(get(d, "targetId", "")), get(d, "replacement", nothing),
                                _entry_extra(d, typ))
    elseif typ == "session_info"
        return SessionInfoEntry(String(id), parent_id, String(timestamp), get(d, "name", nothing),
                                _entry_extra(d, typ))
    end
    return UnknownEntry(id, parent_id, timestamp, typ,
                        Dict{String,Any}(String(k) => plain(v) for (k, v) in d))
end

function _new_header(cwd; id=nothing, parent=nothing)
    return SessionHeader(something(id, string(uuid4())), SESSION_VERSION, now_iso(), cwd,
                         parent, Dict{String,Any}())
end

function create_session(cwd::String; id=nothing, dir=nothing, parent=nothing, in_memory=false, name=nothing)
    header = _new_header(cwd; id=id, parent=parent)
    if in_memory
        sm = SessionManager(header, AbstractSessionEntry[], nothing, nothing, nothing)
        name === nothing || append_entry!(sm, SessionInfoEntry(new_entry_id(Set{String}()), nothing, now_iso(), name, Dict{String,Any}()))
        return sm
    end
    dir_path = session_dir_for_cwd(cwd; dir=dir)
    mkpath(dir_path)
    base = replace(Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH-MM-SS"), ':' => '-')
    path = joinpath(dir_path, base * "_" * string(uuid4()) * ".jsonl")
    io = open(path, "a")
    write(io, json_write(header_to_json(header)), "\n")
    flush(io)
    sm = SessionManager(header, AbstractSessionEntry[], nothing, path, io)
    name === nothing || append_entry!(sm, SessionInfoEntry(new_entry_id(Set{String}()), nothing, now_iso(), name, Dict{String,Any}()))
    return sm
end

function load_session(path::String)
    isfile(path) || throw(ArgumentError("Session file not found: $(path)"))
    raw = read(path, String)
    lines = split(raw, '\n')
    ids = Set{String}()
    entries = AbstractSessionEntry[]
    header = nothing
    for (i, line) in enumerate(lines)
        isempty(strip(line)) && continue
        d = try
            json_parse(line)
        catch err
            @warn "skipping malformed session line" _group=LOG_TAG path=path line=i
            continue
        end
        d isa AbstractDict || continue
        if get(d, "type", nothing) == "session"
            header = SessionHeader(String(get(d, "id", "")), Int(get(d, "version", 1)),
                                   String(get(d, "timestamp", "")), String(get(d, "cwd", "")),
                                   get(d, "parentSession", nothing),
                                   Dict{String,Any}(String(k) => plain(v) for (k, v) in d
                                       if !(String(k) in ("type", "version", "id", "timestamp", "cwd", "parentSession"))))
            continue
        end
        entry = try
            entry_from_json(d)
        catch err
            @warn "skipping unparseable session entry" _group=LOG_TAG path=path line=i exception=(err, catch_backtrace())
            continue
        end
        entry.id === nothing || push!(ids, entry.id)
        push!(entries, entry)
    end
    header === nothing && (header = SessionHeader("", SESSION_VERSION, now_iso(), dirname(path), nothing, Dict{String,Any}()))
    leaf = isempty(entries) ? nothing : entries[end].id
    if !endswith(raw, '\n') && !isempty(raw)
        open(path, "a") do io
            write(io, "\n")
        end
    end
    io = open(path, "a")
    return SessionManager(header, entries, leaf, path, io)
end

function _append_entry(sm::SessionManager, entry::AbstractSessionEntry)
    if sm.io !== nothing
        write(sm.io, json_write(entry_to_json(entry)), "\n")
        flush(sm.io)
    end
    push!(sm.entries, entry)
    id = entry.id
    id === nothing || (sm.leaf_id = id)
    return entry
end

function append_entry!(sm::SessionManager, entry::AbstractSessionEntry)
    existing = Set{String}(e.id for e in sm.entries if e.id !== nothing)
    id = entry.id
    if id === nothing || isempty(id)
        id = new_entry_id(existing)
        entry = _with_id(entry, id)
    end
    parent = entry.parent_id
    if parent === nothing
        entry = _with_parent(entry, sm.leaf_id)
    end
    return _append_entry(sm, entry)
end

_with_id(e::MessageEntry, id) = MessageEntry(id, e.parent_id, e.timestamp, e.message, e.extra)
_with_id(e::ModelChangeEntry, id) = ModelChangeEntry(id, e.parent_id, e.timestamp, e.provider, e.model_id, e.extra)
_with_id(e::ThinkingLevelChangeEntry, id) = ThinkingLevelChangeEntry(id, e.parent_id, e.timestamp, e.thinking_level, e.extra)
_with_id(e::UsageEntry, id) = UsageEntry(id, e.parent_id, e.timestamp, e.kind, e.provider, e.model, e.usage, e.note, e.extra)
_with_id(e::CompactionEntry, id) = CompactionEntry(id, e.parent_id, e.timestamp, e.summary, e.first_kept_entry_id, e.tokens_before, e.system_message, e.usage, e.details, e.from_hook, e.extra)
_with_id(e::ContextEditEntry, id) = ContextEditEntry(id, e.parent_id, e.timestamp, e.target_id, e.replacement, e.extra)
_with_id(e::SessionInfoEntry, id) = SessionInfoEntry(id, e.parent_id, e.timestamp, e.name, e.extra)
_with_id(e::UnknownEntry, id) = e
_with_id(e, id) = e

_with_parent(e::MessageEntry, p) = MessageEntry(e.id, p, e.timestamp, e.message, e.extra)
_with_parent(e::ModelChangeEntry, p) = ModelChangeEntry(e.id, p, e.timestamp, e.provider, e.model_id, e.extra)
_with_parent(e::ThinkingLevelChangeEntry, p) = ThinkingLevelChangeEntry(e.id, p, e.timestamp, e.thinking_level, e.extra)
_with_parent(e::UsageEntry, p) = UsageEntry(e.id, p, e.timestamp, e.kind, e.provider, e.model, e.usage, e.note, e.extra)
_with_parent(e::CompactionEntry, p) = CompactionEntry(e.id, p, e.timestamp, e.summary, e.first_kept_entry_id, e.tokens_before, e.system_message, e.usage, e.details, e.from_hook, e.extra)
_with_parent(e::ContextEditEntry, p) = ContextEditEntry(e.id, p, e.timestamp, e.target_id, e.replacement, e.extra)
_with_parent(e::SessionInfoEntry, p) = SessionInfoEntry(e.id, p, e.timestamp, e.name, e.extra)
_with_parent(e, p) = e

function append_message!(sm::SessionManager, message::PiAISDK.AbstractMessage; timestamp=now_iso())
    if message isa PiAISDK.AssistantMessage && message.stop_reason == "pending"
        throw(ArgumentError("refusing to persist a pending assistant message"))
    end
    return append_entry!(sm, MessageEntry("", sm.leaf_id, timestamp, message, Dict{String,Any}()))
end

function close!(sm::SessionManager)
    if sm.io !== nothing
        try
            isopen(sm.io) && close(sm.io)
        catch err
            @debug "closing session IO failed" _group=LOG_TAG exception=(err, catch_backtrace())
        end
        sm.io = nothing
    end
    return nothing
end

function _entries_by_id(sm::SessionManager)
    d = Dict{String,AbstractSessionEntry}()
    for e in sm.entries
        e.id === nothing || (d[e.id] = e)
    end
    return d
end

function _path_from_leaf(sm::SessionManager)
    by_id = _entries_by_id(sm)
    chain = AbstractSessionEntry[]
    current = sm.leaf_id
    seen = Set{String}()
    while current !== nothing && haskey(by_id, current) && !(current in seen)
        push!(seen, current)
        entry = by_id[current]
        push!(chain, entry)
        current = entry.parent_id
    end
    return reverse(chain)
end

function _has_tool_results_for(messages, assistant::PiAISDK.AssistantMessage)
    call_ids = Set(c.id for c in assistant.content if c isa PiAISDK.ToolCall)
    return PiAISDK.ToolResultMessage[m for m in messages if m isa PiAISDK.ToolResultMessage && m.tool_call_id in call_ids]
end

function build_context(sm::SessionManager; include_system::Bool=true)
    chain = _path_from_leaf(sm)
    edits = Dict{String,Any}()
    for e in sm.entries
        e isa ContextEditEntry && (edits[e.target_id] = e.replacement)
    end
    selected = Tuple{Union{Nothing,String},PiAISDK.AbstractMessage}[]
    compaction_idx = findlast(e -> e isa CompactionEntry, chain)
    if compaction_idx === nothing
        for e in chain
            e isa MessageEntry && push!(selected, (e.id, e.message))
        end
    else
        comp = chain[compaction_idx]::CompactionEntry
        start_idx = findfirst(e -> e.id == comp.first_kept_entry_id, chain)
        if start_idx === nothing
            for e in chain
                e isa MessageEntry && push!(selected, (e.id, e.message))
            end
        else
            comp.system_message === nothing || push!(selected, (nothing, comp.system_message))
            push!(selected, (nothing, CompactionSummaryMessage(comp.summary; tokens_before=comp.tokens_before)))
            for i in start_idx:(compaction_idx - 1)
                e = chain[i]
                e isa MessageEntry || continue
                comp.system_message !== nothing && e.message isa PiAISDK.SystemMessage && continue
                push!(selected, (e.id, e.message))
            end
            for i in (compaction_idx + 1):length(chain)
                e = chain[i]
                e isa MessageEntry && push!(selected, (e.id, e.message))
            end
        end
    end
    omitted = Set{String}(k for (k, v) in edits if v === nothing)
    tool_ids = Set{String}()
    if !isempty(omitted)
        by_id = _entries_by_id(sm)
        for id in omitted
            entry = get(by_id, id, nothing)
            entry isa MessageEntry || continue
            if entry.message isa PiAISDK.AssistantMessage
                for c in entry.message.content
                    c isa PiAISDK.ToolCall && push!(tool_ids, c.id)
                end
            end
        end
    end
    out = PiAISDK.AbstractMessage[]
    for (id, message) in selected
        id !== nothing && id in omitted && continue
        message isa PiAISDK.ToolResultMessage && message.tool_call_id in tool_ids && continue
        push!(out, message)
    end
    return out
end

function list_sessions(cwd::String; dir=nothing)
    dir_path = session_dir_for_cwd(cwd; dir=dir)
    isdir(dir_path) || return String[]
    files = [joinpath(dir_path, f) for f in readdir(dir_path) if endswith(f, ".jsonl")]
    sort!(files; by=f -> stat(f).mtime, rev=true)
    return files
end

function find_session(id_or_path::String; dir=nothing)
    isfile(id_or_path) && return id_or_path
    root = session_root(; dir=dir)
    matches = String[]
    if isdir(root)
        for (base, _, files) in walkdir(root)
            for f in files
                endswith(f, ".jsonl") || continue
                path = joinpath(base, f)
                name = basename(path)
                if startswith(name, id_or_path) || occursin(id_or_path, name)
                    push!(matches, path)
                end
            end
        end
    end
    isempty(matches) && throw(ArgumentError("Session not found: $(id_or_path)"))
    unique!(matches)
    return matches[1]
end

function fork_session(sm::SessionManager, entry_id::String, new_cwd::String; dir=nothing)
    chain = _path_from_leaf(sm)
    idx = findfirst(e -> e.id == entry_id, chain)
    idx === nothing && throw(ArgumentError("Entry not found on active branch: $(entry_id)"))
    copied = chain[1:idx]
    new_sm = create_session(new_cwd; dir=dir, parent=sm.path)
    id_map = Dict{String,String}()
    for entry in copied
        old_id = entry.id
        old_id === nothing && continue
        new_id = new_entry_id(Set{String}(values(id_map)))
        id_map[old_id] = new_id
    end
    last_new_id = nothing
    for entry in copied
        old_id = entry.id
        old_id === nothing && continue
        new_id = id_map[old_id]
        new_parent = entry.parent_id === nothing ? nothing : get(id_map, entry.parent_id, nothing)
        if entry isa CompactionEntry
            kept = get(id_map, entry.first_kept_entry_id, nothing)
            if kept === nothing
                # Compaction target is outside the copied branch: drop the entry and
                # rewire its children to its parent so the copied tree stays connected.
                new_parent === nothing || (id_map[old_id] = new_parent)
                continue
            end
            new_entry = CompactionEntry(new_id, new_parent, entry.timestamp, entry.summary,
                kept, entry.tokens_before, entry.system_message, entry.usage, entry.details,
                entry.from_hook, entry.extra)
        else
            new_entry = _with_parent(_with_id(entry, new_id), new_parent)
        end
        _append_entry(new_sm, new_entry)
        last_new_id = new_id
    end
    new_sm.leaf_id = last_new_id
    return new_sm
end
