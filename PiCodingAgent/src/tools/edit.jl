const LOG_TAG = "coding_tools_edit"

const EDIT_SCHEMA = Dict{String,Any}(
    "type" => "object",
    "properties" => Dict{String,Any}(
        "path" => Dict{String,Any}("type" => "string", "description" => "Path to the file to edit (relative or absolute)"),
        "edits" => Dict{String,Any}(
            "type" => "array",
            "description" => "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead.",
            "items" => Dict{String,Any}(
                "type" => "object",
                "properties" => Dict{String,Any}(
                    "oldText" => Dict{String,Any}("type" => "string", "description" => "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call."),
                    "newText" => Dict{String,Any}("type" => "string", "description" => "Replacement text for this targeted edit."),
                ),
                "required" => ["oldText", "newText"],
                "additionalProperties" => false,
            ),
        ),
    ),
    "required" => ["path", "edits"],
    "additionalProperties" => false,
)

function normalize_edits(args::AbstractDict)
    edits = get(args, "edits", nothing)
    if edits isa AbstractString
        parsed = json_parse(edits)
        edits = parsed
    end
    if edits isa AbstractDict
        edits = Any[edits]
    end
    if edits === nothing && haskey(args, "oldText") && haskey(args, "newText")
        edits = Any[Dict{String,Any}("oldText" => args["oldText"], "newText" => args["newText"])]
    end
    edits isa AbstractVector || throw(ArgumentError("edits must be an array of {oldText, newText} objects"))
    out = Dict{String,Any}[]
    for e in edits
        e isa AbstractDict || throw(ArgumentError("each edit must be an object"))
        haskey(e, "oldText") && haskey(e, "newText") ||
            throw(ArgumentError("each edit requires oldText and newText"))
        push!(out, Dict{String,Any}("oldText" => String(e["oldText"]), "newText" => String(e["newText"])))
    end
    isempty(out) && throw(ArgumentError("edits must not be empty"))
    return out
end

function prepare_edit_args(args::AbstractDict)
    d = Dict{String,Any}(String(k) => v for (k, v) in args)
    if haskey(d, "oldText") && haskey(d, "newText") && !haskey(d, "edits")
        d["edits"] = Any[Dict{String,Any}("oldText" => d["oldText"], "newText" => d["newText"])]
    elseif get(d, "edits", nothing) isa AbstractString
        d["edits"] = json_parse(d["edits"])
    elseif get(d, "edits", nothing) isa AbstractDict
        d["edits"] = Any[d["edits"]]
    end
    return d
end

function _detect_eol(s::String)
    occursin("\r\n", s) && return "\r\n"
    occursin('\r', s) && return "\r"
    return "\n"
end

function _normalize_eol(s::String)
    return replace(s, "\r\n" => "\n", '\r' => '\n')
end

function _restore_eol(s::String, eol::String)
    eol == "\n" && return s
    return replace(s, "\n" => eol)
end

function _line_diff(old::String, new::String)
    a = split(old, '\n')
    b = split(new, '\n')
    n, m = length(a), length(b)
    lcs = zeros(Int, n + 1, m + 1)
    for i in n:-1:1, j in m:-1:1
        lcs[i, j] = a[i] == b[j] ? lcs[i+1, j+1] + 1 : max(lcs[i+1, j], lcs[i, j+1])
    end
    out = String[]
    i, j = 1, 1
    while i <= n && j <= m
        if a[i] == b[j]
            push!(out, " " * a[i]); i += 1; j += 1
        elseif lcs[i+1, j] >= lcs[i, j+1]
            push!(out, "-" * a[i]); i += 1
        else
            push!(out, "+" * b[j]); j += 1
        end
    end
    while i <= n
        push!(out, "-" * a[i]); i += 1
    end
    while j <= m
        push!(out, "+" * b[j]); j += 1
    end
    return join(out, "\n")
end

function _unified_patch(path, old::String, new::String)
    diff = _line_diff(old, new)
    return "--- a/$(path)\n+++ b/$(path)\n" * diff
end

function _find_unique(text::String, needle::String)
    positions = UnitRange{Int}[]
    start = 1
    while true
        found = findnext(needle, text, start)
        found === nothing && break
        push!(positions, found)
        start = last(found) + 1
        start > lastindex(text) && break
    end
    return positions
end

function edit_tool(cwd::String)
    execute = function (id, args, signal, on_update)
        edits = normalize_edits(args)
        resolved = resolve_to_cwd(String(args["path"]), cwd)
        return with_file_lock(resolved) do
            ispath(resolved) || return PiAgentCore.ToolResult(
                AbstractContent[TextContent("File not found: $(resolved)")]; is_error=true)
            raw_bytes = read(resolved)
            bom = length(raw_bytes) >= 3 && raw_bytes[1:3] == UInt8[0xef, 0xbb, 0xbf]
            body_bytes = bom ? raw_bytes[4:end] : raw_bytes
            raw = String(body_bytes)
            eol = _detect_eol(raw)
            original = _normalize_eol(raw)
            ranges = UnitRange{Int}[]
            replacements = Pair{UnitRange{Int},String}[]
            for e in edits
                old_text = _normalize_eol(e["oldText"])
                new_text = _normalize_eol(e["newText"])
                isempty(old_text) && return PiAgentCore.ToolResult(
                    AbstractContent[TextContent("oldText must not be empty")]; is_error=true)
                found = _find_unique(original, old_text)
                isempty(found) && return PiAgentCore.ToolResult(
                    AbstractContent[TextContent("Could not find the text to replace in $(resolved):\n$(old_text)")]; is_error=true)
                length(found) > 1 && return PiAgentCore.ToolResult(
                    AbstractContent[TextContent("Found multiple matches for the text to replace in $(resolved); make the oldText unique.")]; is_error=true)
                r = found[1]
                for existing in ranges
                    if !(last(existing) < first(r) || last(r) < first(existing))
                        return PiAgentCore.ToolResult(
                            AbstractContent[TextContent("Edits overlap in $(resolved); merge overlapping edits into one.")]; is_error=true)
                    end
                end
                push!(ranges, r)
                push!(replacements, r => new_text)
            end
            sort!(replacements; by=p -> first(first(p)))
            io = IOBuffer()
            cursor = 1
            for (r, new_text) in replacements
                if cursor < first(r)
                    print(io, original[cursor:prevind(original, first(r))])
                end
                print(io, new_text)
                cursor = last(r) + 1
            end
            cursor <= lastindex(original) && print(io, original[cursor:end])
            updated = String(take!(io))
            output = (bom ? "\ufeff" : "") * _restore_eol(updated, eol)
            write(resolved, output)
            details = Dict{String,Any}(
                "diff" => _line_diff(original, updated),
                "patch" => _unified_patch(String(args["path"]), original, updated),
            )
            return PiAgentCore.ToolResult(
                AbstractContent[TextContent("Successfully replaced $(length(edits)) block(s) in $(String(args["path"])).")];
                details=details)
        end
    end
    description = "Edit a file by replacing exact text blocks. Each edits[].oldText must match the original file exactly and uniquely; multiple disjoint edits can be applied in one call."
    return PiAgentCore.Tool("edit", description, EDIT_SCHEMA, execute;
                          label="edit", prepare_arguments=prepare_edit_args, execution_mode=:sequential)
end
