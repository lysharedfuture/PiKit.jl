const LOG_TAG = "ai_provider_common"

function system_text(msg::SystemMessage)
    parts = String[]
    msg.content isa AbstractString && !isempty(msg.content) && push!(parts, msg.content)
    msg.content isa AbstractVector && for c in msg.content
        c isa TextContent && push!(parts, c.text)
    end
    if msg.sections !== nothing
        for (_, v) in msg.sections
            v === nothing || push!(parts, v)
        end
    end
    return join(parts, "\n\n")
end

function content_text(content)
    parts = String[]
    for c in content
        c isa TextContent && push!(parts, c.text)
    end
    return join(parts, "\n")
end

function current_tools(messages)
    tools = Dict{String,Dict{String,Any}}()
    for m in messages
        m isa SystemMessage || continue
        for t in m.tools_added
            name = get(t, "name", nothing)
            name === nothing || (tools[String(name)] = Dict{String,Any}(String(k) => plain(v) for (k, v) in t))
        end
        for t in m.tools_removed
            name = get(t, "name", nothing)
            name === nothing || delete!(tools, String(name))
        end
    end
    return collect(values(tools))
end

function tool_declaration_json(t)
    if t isa ToolDeclaration
        return Dict{String,Any}("name" => t.name, "description" => t.description, "parameters" => t.parameters)
    end
    return Dict{String,Any}(String(k) => plain(v) for (k, v) in t)
end

function _compat(model::Model, key, default=nothing)
    return get(model.compat, String(key), default)
end

function _duration_ms(start_ns)
    return Int(round((time_ns() - start_ns) / 1_000_000))
end

function finished_error_message(model::Model, partial::AssistantMessage, text; stop_reason="error")
    partial.stop_reason = stop_reason
    partial.error_message = text
    return partial
end
