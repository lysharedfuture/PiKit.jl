const LOG_TAG = "ai_json"

"""
    plain(x)

Recursively convert `x` to plain JSON-compatible values: dictionaries become
`Dict{String,Any}`, vectors become `Vector{Any}`, and strings are copied.
Other values are returned unchanged.
"""
plain(::Nothing) = nothing
plain(x::Number) = x
plain(x::Bool) = x
plain(x::AbstractString) = String(x)
plain(x::AbstractDict) = Dict{String,Any}(String(k) => plain(v) for (k, v) in x)
plain(x::AbstractVector) = Any[plain(v) for v in x]
plain(x) = x

function ordered_plain(x::JSON.Object)
    return Dict{String,Any}(String(k) => (String(k) == "sections" ? sections_plain(v) : plain(v)) for (k, v) in pairs(x))
end
ordered_plain(x) = plain(x)

function sections_plain(v)
    v === nothing && return nothing
    if v isa JSON.Object
        return Pair{String,Union{String,Nothing}}[
            String(k) => (val === nothing ? nothing : String(val)) for (k, val) in pairs(v)
        ]
    elseif v isa AbstractDict
        return Pair{String,Union{String,Nothing}}[
            String(k) => (val === nothing ? nothing : String(val)) for (k, val) in v
        ]
    end
    return nothing
end

"""
    json_parse(s::AbstractString) -> Any

Parse JSON text and convert the result with `plain`, including `sections`
objects preserved as ordered pairs.
"""
json_parse(s::AbstractString) = ordered_plain(JSON.parse(s))

function _json_write(io::IO, x)
    if x isa AbstractDict
        print(io, '{')
        first = true
        for (k, v) in x
            first || print(io, ',')
            first = false
            print(io, JSON.json(String(k)))
            print(io, ':')
            _json_write(io, v)
        end
        print(io, '}')
    elseif x isa AbstractVector{<:Pair}
        print(io, '{')
        first = true
        for (k, v) in x
            first || print(io, ',')
            first = false
            print(io, JSON.json(String(k)))
            print(io, ':')
            _json_write(io, v)
        end
        print(io, '}')
    elseif x isa AbstractVector
        print(io, '[')
        for (i, v) in enumerate(x)
            i > 1 && print(io, ',')
            _json_write(io, v)
        end
        print(io, ']')
    else
        print(io, JSON.json(x))
    end
end

"""
    json_write(x) -> String

Serialize `x` to compact JSON text. Dictionaries, pair vectors, and arrays are
walked manually so key order is preserved; other values are encoded by JSON.jl.
"""
function json_write(x)
    io = IOBuffer()
    _json_write(io, x)
    return String(take!(io))
end

"""
    to_json(x)

Convert a content block or message to its upstream JSON-compatible `Dict`
form. Content blocks carry a `"type"` discriminator; messages delegate to
`message_to_json`.
"""
function to_json(c::TextContent)
    d = Dict{String,Any}("type" => "text", "text" => c.text)
    c.text_signature === nothing || (d["textSignature"] = c.text_signature)
    return d
end

to_json(c::ImageContent) = Dict{String,Any}("type" => "image", "data" => c.data, "mimeType" => c.mime_type)

function to_json(c::ThinkingContent)
    d = Dict{String,Any}("type" => "thinking", "thinking" => c.thinking)
    c.thinking_signature === nothing || (d["thinkingSignature"] = c.thinking_signature)
    c.redacted && (d["redacted"] = true)
    return d
end

function to_json(c::ToolCall)
    d = Dict{String,Any}("type" => "toolCall", "id" => c.id, "name" => c.name, "arguments" => c.arguments)
    c.thought_signature === nothing || (d["thoughtSignature"] = c.thought_signature)
    c.namespace === nothing || (d["namespace"] = c.namespace)
    c.arguments_error === nothing || (d["argumentsError"] = c.arguments_error)
    return d
end

"""
    content_from_json(d) -> AbstractContent

Build a content block from a JSON object, dispatching on its `"type"` field:
`"text"`, `"image"`, `"thinking"`, or `"toolCall"`.

# Throws
- `ArgumentError`: `d` has a missing or unknown `"type"`.
"""
function content_from_json(d)
    t = get(d, "type", nothing)
    if t == "text"
        return TextContent(String(get(d, "text", "")), get(d, "textSignature", nothing))
    elseif t == "image"
        return ImageContent(String(get(d, "data", "")), String(get(d, "mimeType", "image/png")))
    elseif t == "thinking"
        return ThinkingContent(String(get(d, "thinking", "")),
                               get(d, "thinkingSignature", nothing),
                               Bool(get(d, "redacted", false)))
    elseif t == "toolCall"
        args = get(d, "arguments", Dict{String,Any}())
        args isa AbstractDict || (args = Dict{String,Any}())
        return ToolCall(String(get(d, "id", "")), String(get(d, "name", "")),
                        Dict{String,Any}(String(k) => plain(v) for (k, v) in args);
                        thought_signature=get(d, "thoughtSignature", nothing),
                        namespace=get(d, "namespace", nothing),
                        arguments_error=get(d, "argumentsError", nothing))
    end
    throw(ArgumentError("unknown content type: $(t)"))
end

"""
    usage_to_json(u::Usage) -> Dict{String,Any}

Serialize `u` to the upstream usage object, including cost and the optional
`cacheWrite1h` and `reasoning` counters.
"""
function usage_to_json(u::Usage)
    d = Dict{String,Any}(
        "input" => u.input,
        "output" => u.output,
        "cacheRead" => u.cache_read,
        "cacheWrite" => u.cache_write,
        "totalTokens" => u.total_tokens,
        "cost" => cost_to_json(u.cost),
    )
    u.cache_write_1h === nothing || (d["cacheWrite1h"] = u.cache_write_1h)
    u.reasoning === nothing || (d["reasoning"] = u.reasoning)
    return d
end

function cost_to_json(c::Cost)
    d = Dict{String,Any}(
        "input" => c.input,
        "output" => c.output,
        "cacheRead" => c.cache_read,
        "cacheWrite" => c.cache_write,
        "total" => c.total,
    )
    c.total_from_provider === nothing || (d["totalFromProvider"] = c.total_from_provider)
    return d
end

function cost_from_json(d)
    d === nothing && return Cost()
    return Cost(
        Float64(get(d, "input", 0.0)),
        Float64(get(d, "output", 0.0)),
        Float64(get(d, "cacheRead", 0.0)),
        Float64(get(d, "cacheWrite", 0.0)),
        Float64(get(d, "total", 0.0)),
        get(d, "totalFromProvider", nothing),
    )
end

"""
    usage_from_json(d) -> Usage

Build a `Usage` from a JSON usage object; missing counters default to zero and
`nothing` yields `empty_usage()`.
"""
function usage_from_json(d)
    d === nothing && return empty_usage()
    input = Int(get(d, "input", 0))
    output = Int(get(d, "output", 0))
    cache_read = Int(get(d, "cacheRead", 0))
    cache_write = Int(get(d, "cacheWrite", 0))
    total = Int(get(d, "totalTokens", input + output + cache_read + cache_write))
    return Usage(
        input, output, cache_read, cache_write,
        get(d, "cacheWrite1h", nothing),
        get(d, "reasoning", nothing),
        total,
        cost_from_json(get(d, "cost", nothing)),
    )
end

const MESSAGE_KNOWN_KEYS = Dict(
    "system" => Set(["role", "content", "sections", "toolsAdded", "toolsRemoved", "timestamp"]),
    "user" => Set(["role", "content", "timestamp"]),
    "assistant" => Set(["role", "content", "api", "provider", "model", "responseModel", "responseId",
                        "usage", "stopReason", "errorMessage", "providerThinkingLevel", "thinkingLevel",
                        "timestamp", "durationMs"]),
    "toolResult" => Set(["role", "toolCallId", "toolName", "content", "details", "usage", "isError",
                         "timestamp", "durationMs"]),
)

function extra_keys(d, role)
    known = get(MESSAGE_KNOWN_KEYS, role, Set{String}())
    return Dict{String,Any}(String(k) => plain(v) for (k, v) in d if !(String(k) in known))
end

content_to_json(c) = c isa AbstractString ? String(c) : Any[to_json(x) for x in c]

function content_field_from_json(v)
    v === nothing && return AbstractContent[]
    v isa AbstractString && return String(v)
    return AbstractContent[content_from_json(x) for x in v]
end

"""
    message_to_json(m::AbstractMessage) -> Dict{String,Any}

Serialize a message to its upstream JSON object. `m.extra` keys are merged in
first, so unknown fields survive a round trip.

# Throws
- `ArgumentError`: `m` is not a concrete message type.
"""
function message_to_json(m::SystemMessage)
    d = Dict{String,Any}(m.extra)
    d["role"] = "system"
    d["content"] = content_to_json(m.content)
    m.sections === nothing || (d["sections"] = m.sections)
    isempty(m.tools_added) || (d["toolsAdded"] = m.tools_added)
    isempty(m.tools_removed) || (d["toolsRemoved"] = m.tools_removed)
    d["timestamp"] = m.timestamp
    return d
end

function message_to_json(m::UserMessage)
    d = Dict{String,Any}(m.extra)
    d["role"] = "user"
    d["content"] = content_to_json(m.content)
    d["timestamp"] = m.timestamp
    return d
end

function message_to_json(m::AssistantMessage)
    d = Dict{String,Any}(m.extra)
    d["role"] = "assistant"
    d["content"] = Any[to_json(c) for c in m.content]
    d["api"] = m.api
    d["provider"] = m.provider
    d["model"] = m.model
    m.response_model === nothing || (d["responseModel"] = m.response_model)
    m.response_id === nothing || (d["responseId"] = m.response_id)
    d["usage"] = usage_to_json(m.usage)
    d["stopReason"] = m.stop_reason
    m.error_message === nothing || (d["errorMessage"] = m.error_message)
    m.provider_thinking_level === nothing || (d["providerThinkingLevel"] = m.provider_thinking_level)
    m.thinking_level === nothing || (d["thinkingLevel"] = m.thinking_level)
    d["timestamp"] = m.timestamp
    m.duration_ms === nothing || (d["durationMs"] = m.duration_ms)
    return d
end

function message_to_json(m::ToolResultMessage)
    d = Dict{String,Any}(m.extra)
    d["role"] = "toolResult"
    d["toolCallId"] = m.tool_call_id
    d["toolName"] = m.tool_name
    d["content"] = Any[to_json(c) for c in m.content]
    m.details === nothing || (d["details"] = m.details)
    m.usage === nothing || (d["usage"] = usage_to_json(m.usage))
    d["isError"] = m.is_error
    d["timestamp"] = m.timestamp
    m.duration_ms === nothing || (d["durationMs"] = m.duration_ms)
    return d
end

message_to_json(::AbstractMessage) = throw(ArgumentError("unknown message type"))

"""
    message_from_json(d) -> AbstractMessage

Build a message from a JSON object, dispatching on `"role"`: `"system"`,
`"user"`, `"assistant"`, or `"toolResult"`. Unknown keys are preserved in the
message's `extra`.

# Throws
- `ArgumentError`: `d` lacks `"role"` or has an unknown role.
"""
function message_from_json(d)
    role = get(d, "role", nothing)
    role === nothing && throw(ArgumentError("message is missing role"))
    if role == "system"
        sections = get(d, "sections", nothing)
        sections isa AbstractDict && (sections = sections_plain(sections))
        return SystemMessage(content_field_from_json(get(d, "content", "")),
            sections=sections,
            tools_added=Dict{String,Any}[Dict{String,Any}(String(k) => plain(v) for (k, v) in x) for x in get(d, "toolsAdded", [])],
            tools_removed=Dict{String,Any}[Dict{String,Any}(String(k) => plain(v) for (k, v) in x) for x in get(d, "toolsRemoved", [])],
            timestamp=Int(get(d, "timestamp", time_millis())),
            extra=extra_keys(d, role))
    elseif role == "user"
        return UserMessage(content_field_from_json(get(d, "content", "")),
                           timestamp=Int(get(d, "timestamp", time_millis())),
                           extra=extra_keys(d, role))
    elseif role == "assistant"
        content = AbstractContent[content_from_json(x) for x in get(d, "content", [])]
        return AssistantMessage(content;
            api=String(get(d, "api", "")), provider=String(get(d, "provider", "")),
            model=String(get(d, "model", "")),
            response_model=get(d, "responseModel", nothing), response_id=get(d, "responseId", nothing),
            usage=usage_from_json(get(d, "usage", nothing)),
            stop_reason=String(get(d, "stopReason", "stop")),
            error_message=get(d, "errorMessage", nothing),
            provider_thinking_level=get(d, "providerThinkingLevel", nothing),
            thinking_level=get(d, "thinkingLevel", nothing),
            timestamp=Int(get(d, "timestamp", time_millis())),
            duration_ms=get(d, "durationMs", nothing),
            extra=extra_keys(d, role))
    elseif role == "toolResult"
        return ToolResultMessage(
            String(get(d, "toolCallId", "")), String(get(d, "toolName", "")),
            content_field_from_json(get(d, "content", [])),
            details=get(d, "details", nothing),
            usage=get(d, "usage", nothing) === nothing ? nothing : usage_from_json(d["usage"]),
            is_error=Bool(get(d, "isError", false)),
            timestamp=Int(get(d, "timestamp", time_millis())),
            duration_ms=get(d, "durationMs", nothing),
            extra=extra_keys(d, role))
    end
    throw(ArgumentError("unknown message role: $(role)"))
end

to_json(m::AbstractMessage) = message_to_json(m)
from_json_message(d) = message_from_json(d)
