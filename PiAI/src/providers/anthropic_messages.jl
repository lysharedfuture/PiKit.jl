const LOG_TAG = "ai_provider_anthropic"

function anthropic_endpoint(base_url)
    base = rstrip(base_url, '/')
    endswith(base, "/v1") ? base * "/messages" : base * "/v1/messages"
end

function anthropic_cache_control(model::Model, opts::StreamOptions)
    something(opts.cache_retention, "short") == "none" && return nothing
    c = Dict{String,Any}("type" => "ephemeral")
    if something(opts.cache_retention, "short") == "long" && _compat(model, "supportsLongCacheRetention", false)
        c["ttl"] = "1h"
    end
    return c
end

function anthropic_user_content(m::UserMessage)
    if m.content isa AbstractString
        return m.content
    end
    parts = Any[]
    for c in m.content
        if c isa TextContent
            push!(parts, Dict{String,Any}("type" => "text", "text" => c.text))
        elseif c isa ImageContent
            push!(parts, Dict{String,Any}("type" => "image",
                "source" => Dict{String,Any}("type" => "base64", "media_type" => c.mime_type, "data" => c.data)))
        end
    end
    return parts
end

function anthropic_assistant_content(m::AssistantMessage)
    parts = Any[]
    for c in m.content
        if c isa TextContent
            push!(parts, Dict{String,Any}("type" => "text", "text" => c.text))
        elseif c isa ThinkingContent
            c.redacted && continue
            d = Dict{String,Any}("type" => "thinking", "thinking" => c.thinking)
            c.thinking_signature === nothing || (d["signature"] = c.thinking_signature)
            push!(parts, d)
        elseif c isa ToolCall
            push!(parts, Dict{String,Any}("type" => "tool_use", "id" => c.id, "name" => c.name,
                                          "input" => c.arguments))
        end
    end
    return isempty(parts) ? "" : parts
end

function anthropic_tool_result_content(m::ToolResultMessage)
    return Any[Dict{String,Any}("type" => "tool_result", "tool_use_id" => m.tool_call_id,
                                "content" => Any[Dict{String,Any}("type" => "text", "text" => content_text(m.content))],
                                "is_error" => m.is_error)]
end

function build_anthropic_messages(ctx::LLMContext)
    out = Any[]
    function push_message(role, content)
        if !isempty(out) && out[end]["role"] == role && content isa AbstractVector
            existing = out[end]["content"]
            if existing isa AbstractVector
                append!(existing, content)
                return
            elseif existing isa AbstractString
                out[end]["content"] = Any[Dict{String,Any}("type" => "text", "text" => existing)]
                append!(out[end]["content"], content)
                return
            end
        end
        push!(out, Dict{String,Any}("role" => role, "content" => content))
    end
    for m in ctx.messages
        if m isa UserMessage
            push_message("user", anthropic_user_content(m))
        elseif m isa AssistantMessage
            content = anthropic_assistant_content(m)
            isempty(content) || push_message("assistant", content)
        elseif m isa ToolResultMessage
            push_message("user", anthropic_tool_result_content(m))
        end
    end
    return out
end

function build_anthropic_body(model::Model, ctx::LLMContext, opts::StreamOptions)
    body = Dict{String,Any}()
    body["model"] = model.id
    max_tokens = something(opts.max_tokens, model.max_tokens)
    body["max_tokens"] = max_tokens
    system_parts = String[]
    for m in ctx.messages
        m isa SystemMessage || continue
        t = system_text(m)
        isempty(t) || push!(system_parts, t)
    end
    cache = anthropic_cache_control(model, opts)
    if !isempty(system_parts)
        sysblock = Dict{String,Any}("type" => "text", "text" => join(system_parts, "\n\n"))
        cache === nothing || (sysblock["cache_control"] = cache)
        body["system"] = Any[sysblock]
    end
    msgs = build_anthropic_messages(ctx)
    if cache !== nothing && !isempty(msgs)
        for i in reverse(eachindex(msgs))
            msgs[i]["role"] == "user" || continue
            content = msgs[i]["content"]
            if content isa AbstractString
                content = Any[Dict{String,Any}("type" => "text", "text" => content)]
            end
            if content isa AbstractVector && !isempty(content) && content[end] isa AbstractDict
                content[end]["cache_control"] = cache
            end
            msgs[i]["content"] = content
            break
        end
    end
    body["messages"] = msgs
    tools = current_tools(ctx.messages)
    if !isempty(tools)
        t = Any[]
        for (i, tool) in enumerate(tools)
            d = Dict{String,Any}("name" => String(get(tool, "name", "")),
                                 "description" => String(get(tool, "description", "")),
                                 "input_schema" => get(tool, "parameters", Dict{String,Any}("type" => "object")))
            i == length(tools) && cache !== nothing && (d["cache_control"] = cache)
            push!(t, d)
        end
        body["tools"] = t
    end
    body["stream"] = true
    reasoning = something(opts.reasoning, "off")
    if reasoning != "off"
        budget = get(opts.thinking_budgets, reasoning, 8192)
        budget = clamp(budget, 1024, max(1024, max_tokens - 1024))
        body["thinking"] = Dict{String,Any}("type" => "enabled", "budget_tokens" => budget)
    elseif opts.temperature !== nothing && _compat(model, "supportsTemperature", true)
        body["temperature"] = opts.temperature
    end
    return body
end

function _anthropic_stop_reason(reason::String)
    reason in ("end_turn", "stop_sequence") && return "stop"
    reason == "max_tokens" && return "length"
    reason == "tool_use" && return "toolUse"
    return "stop"
end

function _apply_anthropic_usage!(usage::Usage, u)
    u isa AbstractDict || return
    usage.input = Int(get(u, "input_tokens", usage.input))
    usage.output = Int(get(u, "output_tokens", usage.output))
    usage.cache_read = Int(get(u, "cache_read_input_tokens", usage.cache_read))
    usage.cache_write = Int(get(u, "cache_creation_input_tokens", usage.cache_write))
    creation = get(u, "cache_creation", nothing)
    if creation isa AbstractDict && haskey(creation, "ephemeral_1h_input_tokens")
        usage.cache_write_1h = Int(creation["ephemeral_1h_input_tokens"])
    end
    usage.total_tokens = usage.input + usage.output + usage.cache_read + usage.cache_write
end

function _consume_anthropic_stream(s, io, model, opts, partial)
    signal = opts.signal
    tool_buffers = Dict{Int,IOBuffer}()
    stop_reason = Ref{Union{Nothing,String}}(nothing)
    foreach_sse(io; signal=signal) do ev
        is_aborted(signal) && return
        data = try
            json_parse(ev.data)
        catch err
            @debug "bad Anthropic SSE chunk" _group=LOG_TAG exception=(err, catch_backtrace())
            return
        end
        data isa AbstractDict || return
        typ = get(data, "type", ev.event === nothing ? "" : ev.event)
        if typ == "message_start"
            msg = get(data, "message", Dict{String,Any}())
            _apply_anthropic_usage!(partial.usage, get(msg, "usage", nothing))
            rid = get(msg, "id", nothing)
            rid === nothing || (partial.response_id = String(rid))
            rmodel = get(msg, "model", nothing)
            rmodel === nothing || (partial.response_model = String(rmodel))
        elseif typ == "content_block_start"
            index = Int(get(data, "index", length(partial.content)))
            block = get(data, "content_block", Dict{String,Any}())
            btype = get(block, "type", "")
            if btype == "text"
                push!(partial.content, TextContent(String(get(block, "text", "")), nothing))
                push_event!(s, TextStartEvent(length(partial.content), partial))
            elseif btype == "thinking"
                sig = get(block, "signature", nothing)
                push!(partial.content, ThinkingContent(String(get(block, "thinking", "")), sig, false))
                push_event!(s, ThinkingStartEvent(length(partial.content), partial))
            elseif btype == "redacted_thinking"
                text = String(get(block, "data", ""))
                push!(partial.content, ThinkingContent(text, nothing, true))
                cidx = length(partial.content)
                push_event!(s, ThinkingStartEvent(cidx, partial))
                push_event!(s, ThinkingEndEvent(cidx, text, partial))
            elseif btype == "tool_use"
                call = ToolCall(String(get(block, "id", "")), String(get(block, "name", "")), Dict{String,Any}())
                push!(partial.content, call)
                tool_buffers[index] = IOBuffer()
                push_event!(s, ToolCallStartEvent(length(partial.content), partial))
            end
        elseif typ == "content_block_delta"
            index = Int(get(data, "index", 0))
            delta = get(data, "delta", Dict{String,Any}())
            dtype = get(delta, "type", "")
            if dtype == "text_delta"
                idx = index + 1
                if idx <= length(partial.content) && partial.content[idx] isa TextContent
                    old = partial.content[idx]::TextContent
                    text = String(get(delta, "text", ""))
                    partial.content[idx] = TextContent(old.text * text, old.text_signature)
                    push_event!(s, TextDeltaEvent(idx, text, partial))
                end
            elseif dtype == "thinking_delta"
                idx = index + 1
                if idx <= length(partial.content) && partial.content[idx] isa ThinkingContent
                    old = partial.content[idx]::ThinkingContent
                    text = String(get(delta, "thinking", ""))
                    partial.content[idx] = ThinkingContent(old.thinking * text, old.thinking_signature, old.redacted)
                    push_event!(s, ThinkingDeltaEvent(idx, text, partial))
                end
            elseif dtype == "signature_delta"
                idx = index + 1
                if idx <= length(partial.content) && partial.content[idx] isa ThinkingContent
                    old = partial.content[idx]::ThinkingContent
                    partial.content[idx] = ThinkingContent(old.thinking, String(get(delta, "signature", "")), old.redacted)
                end
            elseif dtype == "input_json_delta"
                idx = index + 1
                text = String(get(delta, "partial_json", ""))
                if haskey(tool_buffers, index)
                    write(tool_buffers[index], text)
                    push_event!(s, ToolCallDeltaEvent(idx, text, partial))
                end
            end
        elseif typ == "content_block_stop"
            index = Int(get(data, "index", 0))
            idx = index + 1
            idx <= length(partial.content) || return
            block = partial.content[idx]
            if block isa TextContent
                push_event!(s, TextEndEvent(idx, block.text, partial))
            elseif block isa ThinkingContent
                push_event!(s, ThinkingEndEvent(idx, block.thinking, partial))
            elseif block isa ToolCall
                text = haskey(tool_buffers, index) ? String(take!(tool_buffers[index])) : ""
                args, err = isempty(text) ? (Dict{String,Any}(), nothing) : _salvage_arguments(text)
                call = ToolCall(block.id, block.name, args; arguments_error=err)
                partial.content[idx] = call
                push_event!(s, ToolCallEndEvent(idx, call, partial))
            end
        elseif typ == "message_delta"
            delta = get(data, "delta", Dict{String,Any}())
            sr = get(delta, "stop_reason", nothing)
            sr === nothing || (stop_reason[] = String(sr))
            _apply_anthropic_usage!(partial.usage, get(data, "usage", nothing))
        elseif typ == "message_stop"
            return
        elseif typ == "error"
            err = get(data, "error", Dict{String,Any}())
            partial.error_message = String(get(err, "message", "Anthropic stream error"))
        end
    end
    return stop_reason[]
end

function stream_anthropic(model::Model, ctx::LLMContext, opts::StreamOptions)
    return AssistantMessageEventStream() do s
        start_ns = time_ns()
        partial = empty_assistant(model)
        partial.thinking_level = opts.reasoning
        push_event!(s, StartEvent(partial))
        url = anthropic_endpoint(model.base_url)
        body = build_anthropic_body(model, ctx, opts)
        if opts.on_payload !== nothing
            replaced = opts.on_payload(body, model)
            replaced !== nothing && (body = replaced)
        end
        payload = json_write(body)
        headers = merged_headers(Dict{String,String}(
            "content-type" => "application/json",
            "x-api-key" => something(opts.api_key, ""),
            "anthropic-version" => "2023-06-01",
            "user-agent" => "pikit/0.1.0",
        ), opts.headers)
        max_retries = max(0, opts.max_retries)
        attempt = 0
        last_error = nothing
        while true
            attempt += 1
            outcome = try
                open_http_stream("POST", url, headers, payload; timeout_ms=opts.timeout_ms, signal=opts.signal) do io, status, resp_headers
                    opts.on_response !== nothing && opts.on_response(status, resp_headers, model)
                    if status < 200 || status >= 300
                        return (:http_error, status, read_error_body(io), resp_headers)
                    end
                    return (:ok, _consume_anthropic_stream(s, io, model, opts, partial))
                end
            catch err
                is_aborted(opts.signal) && return (:aborted, err)
                return (:exception, err)
            end
            if outcome[1] === :ok
                reason = outcome[2] === nothing ? "stop" : String(outcome[2])
                stop_reason = partial.error_message === nothing ? _anthropic_stop_reason(reason) : "error"
                apply_cost!(partial.usage, model.cost)
                partial.duration_ms = _duration_ms(start_ns)
                if stop_reason == "error"
                    partial.stop_reason = "error"
                    push_event!(s, ErrorEvent("error", partial))
                else
                    partial.stop_reason = stop_reason
                    push_event!(s, DoneEvent(stop_reason, partial))
                end
                return
            elseif outcome[1] === :aborted
                partial.stop_reason = "aborted"
                partial.error_message = "Request aborted"
                partial.duration_ms = _duration_ms(start_ns)
                push_event!(s, ErrorEvent("aborted", partial))
                return
            elseif outcome[1] === :http_error
                status, body_text, resp_headers = outcome[2], outcome[3], outcome[4]
                last_error = "HTTP $(status): $(body_text)"
                if should_provider_retry(status) && attempt <= max_retries
                    wait_ms = something(retry_after_ms(resp_headers; cap_ms=opts.max_retry_delay_ms),
                                        backoff_ms(attempt; cap_ms=opts.max_retry_delay_ms))
                    @warn "provider HTTP retry" _group=LOG_TAG status=status attempt=attempt
                    sleep_abortable(wait_ms / 1000, opts.signal) && begin
                        partial.stop_reason = "aborted"
                        partial.error_message = "Request aborted"
                        push_event!(s, ErrorEvent("aborted", partial))
                        return
                    end
                    continue
                end
            else
                last_error = sprint(showerror, outcome[2])
                if attempt <= max_retries
                    wait_ms = backoff_ms(attempt; cap_ms=opts.max_retry_delay_ms)
                    @warn "provider connection retry" _group=LOG_TAG attempt=attempt
                    sleep_abortable(wait_ms / 1000, opts.signal) && begin
                        partial.stop_reason = "aborted"
                        partial.error_message = "Request aborted"
                        push_event!(s, ErrorEvent("aborted", partial))
                        return
                    end
                    continue
                end
            end
            partial.stop_reason = "error"
            partial.error_message = something(last_error, "Provider request failed")
            partial.duration_ms = _duration_ms(start_ns)
            @error "provider request failed" _group=LOG_TAG model=model.id error=partial.error_message
            push_event!(s, ErrorEvent("error", partial))
            return
        end
    end
end
