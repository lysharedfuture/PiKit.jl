const LOG_TAG = "ai_provider_openai"

function openai_message(m::SystemMessage)
    return Dict{String,Any}("role" => "system", "content" => system_text(m))
end

function openai_message(m::UserMessage)
    if m.content isa AbstractString
        return Dict{String,Any}("role" => "user", "content" => m.content)
    end
    parts = Any[]
    for c in m.content
        if c isa TextContent
            push!(parts, Dict{String,Any}("type" => "text", "text" => c.text))
        elseif c isa ImageContent
            push!(parts, Dict{String,Any}("type" => "image_url",
                "image_url" => Dict{String,Any}("url" => "data:$(c.mime_type);base64,$(c.data)")))
        end
    end
    return Dict{String,Any}("role" => "user", "content" => parts)
end

function openai_message(m::AssistantMessage)
    d = Dict{String,Any}("role" => "assistant")
    text = content_text(m.content)
    isempty(text) || (d["content"] = text)
    calls = Any[]
    for c in m.content
        c isa ToolCall || continue
        push!(calls, Dict{String,Any}(
            "id" => c.id, "type" => "function",
            "function" => Dict{String,Any}("name" => c.name, "arguments" => json_write(c.arguments))))
    end
    isempty(calls) || (d["tool_calls"] = calls)
    return d
end

function openai_message(m::ToolResultMessage)
    return Dict{String,Any}("role" => "tool", "tool_call_id" => m.tool_call_id,
                            "content" => content_text(m.content))
end

openai_message(::AbstractMessage) = nothing

function _message_has_tool_history(messages)
    for m in messages
        m isa ToolResultMessage && return true
        if m isa AssistantMessage
            any(c -> c isa ToolCall, m.content) && return true
        end
    end
    return false
end

function build_openai_body(model::Model, ctx::LLMContext, opts::StreamOptions)
    tools = current_tools(ctx.messages)
    body = Dict{String,Any}()
    body["model"] = model.id
    body["messages"] = Any[openai_message(m) for m in ctx.messages if openai_message(m) !== nothing]
    body["stream"] = true
    retention = something(opts.cache_retention, "short")
    if retention != "none" && opts.session_id !== nothing
        body["prompt_cache_key"] = first(opts.session_id, 64)
        if retention == "long" && _compat(model, "supportsLongCacheRetention", false)
            body["prompt_cache_retention"] = "24h"
        end
    end
    _compat(model, "supportsStore", false) && (body["store"] = false)
    if !isempty(tools) || _message_has_tool_history(ctx.messages)
        body["tools"] = Any[tool_declaration_json(t) for t in tools]
        isempty(tools) || (body["tool_choice"] = "auto")
    end
    opts.temperature === nothing || (body["temperature"] = opts.temperature)
    max_tokens = something(opts.max_tokens, model.max_tokens)
    field = String(_compat(model, "maxTokensField", "max_tokens"))
    body[field] = max_tokens
    reasoning = something(opts.reasoning, "off")
    if reasoning != "off" && _compat(model, "supportsReasoningEffort", true)
        body["reasoning_effort"] = reasoning == "max" ? "high" : reasoning
    end
    if _compat(model, "supportsUsageInStreaming", false)
        body["stream_options"] = Dict{String,Any}("include_usage" => true)
    end
    _compat(model, "zaiToolStream", false) && (body["tool_stream"] = true)
    return body
end

function _salvage_arguments(text::String)
    isempty(strip(text)) && return Dict{String,Any}(), nothing
    try
        parsed = json_parse(text)
        parsed isa AbstractDict && return Dict{String,Any}(String(k) => plain(v) for (k, v) in parsed), nothing
    catch err
        @debug "tool arguments were not valid JSON; attempting salvage" _group=LOG_TAG
    end
    s = strip(text)
    if startswith(s, '{')
        in_string = false
        escaped = false
        stack = Char[]
        last_safe = 0
        for (i, ch) in enumerate(s)
            if in_string
                if escaped
                    escaped = false
                elseif ch == '\\'
                    escaped = true
                elseif ch == '"'
                    in_string = false
                end
            else
                if ch == '"'
                    in_string = true
                elseif ch == '{' || ch == '['
                    push!(stack, ch)
                elseif (ch == '}' || ch == ']') && !isempty(stack)
                    pop!(stack)
                    isempty(stack) && (last_safe = i)
                end
            end
        end
        candidates = String[]
        if !isempty(stack) && !in_string
            repaired = s * repeat("}", count(==('{'), stack)) * repeat("]", count(==('['), stack))
            push!(candidates, repaired)
        end
        last_safe > 0 && push!(candidates, s[1:last_safe])
        cut = findlast(',', s)
        cut !== nothing && push!(candidates, s[1:cut-1] * "}")
        for cand in candidates
            try
                parsed = json_parse(cand)
                parsed isa AbstractDict && return Dict{String,Any}(String(k) => plain(v) for (k, v) in parsed), nothing
            catch err
                @debug "salvage candidate failed" _group=LOG_TAG
            end
        end
    end
    return Dict{String,Any}(), "Model produced invalid JSON for tool arguments: $(text)"
end

mutable struct OpenAIToolState
    content_index::Int
    id::String
    name::String
    buffer::IOBuffer
end

function _finalize_openai_tool!(s, partial, st::OpenAIToolState)
    args, err = _salvage_arguments(String(take!(st.buffer)))
    call = ToolCall(st.id, st.name, args; arguments_error=err)
    partial.content[st.content_index] = call
    push_event!(s, ToolCallEndEvent(st.content_index, call, partial))
    return nothing
end

function _openai_stop_reason(reason::String, partial::AssistantMessage)
    if reason == "stop" || reason == "end_turn"
        return "stop"
    elseif reason == "length"
        return "length"
    elseif reason == "tool_calls" || reason == "tool_use"
        return "toolUse"
    elseif reason == "content_filter"
        partial.error_message = "Response blocked by content filter"
        return "error"
    end
    partial.error_message = "Unknown finish_reason: $(reason)"
    return "error"
end

function _consume_openai_stream(s, io, model, opts, partial, started::Ref{Bool})
    signal = opts.signal
    open_text = Ref{Union{Nothing,Int}}(nothing)
    open_thinking = Ref{Union{Nothing,Int}}(nothing)
    tools = Dict{Int,OpenAIToolState}()
    final_reason = Ref{Union{Nothing,String}}(nothing)

    close_text = () -> begin
        idx = open_text[]
        idx === nothing && return
        block = partial.content[idx]
        block isa TextContent && push_event!(s, TextEndEvent(idx, block.text, partial))
        open_text[] = nothing
    end
    close_thinking = () -> begin
        idx = open_thinking[]
        idx === nothing && return
        block = partial.content[idx]
        block isa ThinkingContent && push_event!(s, ThinkingEndEvent(idx, block.thinking, partial))
        open_thinking[] = nothing
    end

    function append_text!(delta)
        close_thinking()
        idx = open_text[]
        if idx === nothing
            push!(partial.content, TextContent("", nothing))
            idx = length(partial.content)
            open_text[] = idx
            push_event!(s, TextStartEvent(idx, partial))
        end
        old = partial.content[idx]::TextContent
        partial.content[idx] = TextContent(old.text * delta, old.text_signature)
        push_event!(s, TextDeltaEvent(idx, delta, partial))
    end

    function append_thinking!(delta)
        close_text()
        idx = open_thinking[]
        if idx === nothing
            push!(partial.content, ThinkingContent("", nothing, false))
            idx = length(partial.content)
            open_thinking[] = idx
            push_event!(s, ThinkingStartEvent(idx, partial))
        end
        old = partial.content[idx]::ThinkingContent
        partial.content[idx] = ThinkingContent(old.thinking * delta, old.thinking_signature, old.redacted)
        push_event!(s, ThinkingDeltaEvent(idx, delta, partial))
    end

    function append_tool!(index::Int, id::Union{Nothing,String}, name::Union{Nothing,String}, args_delta::String)
        close_text(); close_thinking()
        st = get(tools, index, nothing)
        if st === nothing
            st = OpenAIToolState(0, something(id, ""), something(name, ""), IOBuffer())
            push!(partial.content, ToolCall(st.id, st.name, Dict{String,Any}()))
            st.content_index = length(partial.content)
            tools[index] = st
            push_event!(s, ToolCallStartEvent(st.content_index, partial))
        else
            id === nothing || isempty(st.id) && (st.id = id)
            name === nothing || isempty(st.name) && (st.name = name)
            if (!isempty(st.id) || !isempty(st.name)) && partial.content[st.content_index] isa ToolCall
                partial.content[st.content_index] = ToolCall(st.id, st.name, Dict{String,Any}())
            end
        end
        write(st.buffer, args_delta)
        push_event!(s, ToolCallDeltaEvent(st.content_index, args_delta, partial))
    end

    function apply_usage(u)
        u isa AbstractDict || return
        usage = partial.usage
        usage.input = Int(get(u, "prompt_tokens", usage.input))
        usage.output = Int(get(u, "completion_tokens", usage.output))
        details = get(u, "prompt_tokens_details", nothing)
        details isa AbstractDict && (usage.cache_read = Int(get(details, "cached_tokens", usage.cache_read)))
        cdetails = get(u, "completion_tokens_details", nothing)
        if cdetails isa AbstractDict && haskey(cdetails, "reasoning_tokens")
            usage.reasoning = Int(cdetails["reasoning_tokens"])
        end
        usage.total_tokens = Int(get(u, "total_tokens", usage.input + usage.output + usage.cache_read))
    end

    foreach_sse(io; signal=signal) do ev
        is_aborted(signal) && return
        data = ev.data
        data == "[DONE]" && return
        chunk = try
            json_parse(data)
        catch err
            @debug "bad SSE JSON chunk" _group=LOG_TAG exception=(err, catch_backtrace())
            return
        end
        chunk isa AbstractDict || return
        apply_usage(get(chunk, "usage", nothing))
        choices = get(chunk, "choices", Any[])
        isempty(choices) && return
        choice = choices[1]
        delta = get(choice, "delta", Dict{String,Any}())
        delta isa AbstractDict || (delta = Dict{String,Any}())
        text = get(delta, "content", nothing)
        if text isa AbstractString && !isempty(text)
            started[] || (started[] = true)
            append_text!(String(text))
        end
        reasoning = get(delta, "reasoning_content", get(delta, "reasoning", nothing))
        if reasoning isa AbstractString && !isempty(reasoning)
            started[] || (started[] = true)
            append_thinking!(String(reasoning))
        end
        for tc in get(delta, "tool_calls", Any[])
            tc isa AbstractDict || continue
            index = Int(get(tc, "index", 0))
            fn = get(tc, "function", Dict{String,Any}())
            args = fn isa AbstractDict ? get(fn, "arguments", "") : ""
            args isa AbstractString || (args = "")
            started[] || (started[] = true)
            append_tool!(index, get(tc, "id", nothing),
                         fn isa AbstractDict ? get(fn, "name", nothing) : nothing, String(args))
        end
        fr = get(choice, "finish_reason", nothing)
        fr isa AbstractString && (final_reason[] = String(fr))
    end

    close_text()
    close_thinking()
    for (_, st) in tools
        _finalize_openai_tool!(s, partial, st)
    end
    return final_reason[]
end

function stream_openai(model::Model, ctx::LLMContext, opts::StreamOptions)
    return AssistantMessageEventStream() do s
        start_ns = time_ns()
        partial = empty_assistant(model)
        partial.thinking_level = opts.reasoning
        push_event!(s, StartEvent(partial))
        url = rstrip(model.base_url, '/') * "/chat/completions"
        body = build_openai_body(model, ctx, opts)
        if opts.on_payload !== nothing
            replaced = opts.on_payload(body, model)
            replaced !== nothing && (body = replaced)
        end
        payload = json_write(body)
        headers = merged_headers(Dict{String,String}(
            "content-type" => "application/json",
            "authorization" => "Bearer $(something(opts.api_key, ""))",
            "user-agent" => "pikit/0.1.0",
        ), opts.headers)
        max_retries = max(0, opts.max_retries)
        attempt = 0
        last_error = nothing
        while true
            attempt += 1
            started = Ref(false)
            outcome = try
                open_http_stream("POST", url, headers, payload; timeout_ms=opts.timeout_ms, signal=opts.signal) do io, status, resp_headers
                    opts.on_response !== nothing && opts.on_response(status, resp_headers, model)
                    if status < 200 || status >= 300
                        body_text = read_error_body(io)
                        return (:http_error, status, body_text, resp_headers)
                    end
                    reason = _consume_openai_stream(s, io, model, opts, partial, started)
                    return (:ok, reason)
                end
            catch err
                if is_aborted(opts.signal)
                    return (:aborted, err)
                end
                return (:exception, err)
            end
            if outcome[1] === :ok
                last_error = nothing
                reason = outcome[2] === nothing ? "stop" : String(outcome[2])
                stop_reason = _openai_stop_reason(reason, partial)
                if stop_reason == "error" && partial.error_message === nothing
                    partial.error_message = "Provider returned finish_reason=$(reason)"
                end
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
                if should_provider_retry(status) && attempt <= max_retries && !started[]
                    wait_ms = something(retry_after_ms(resp_headers; cap_ms=opts.max_retry_delay_ms),
                                        backoff_ms(attempt; cap_ms=opts.max_retry_delay_ms))
                    @warn "provider HTTP retry" _group=LOG_TAG status=status attempt=attempt
                    sleep_abortable(wait_ms / 1000, opts.signal) && begin
                        partial.stop_reason = "aborted"
                        partial.error_message = "Request aborted"
                        partial.duration_ms = _duration_ms(start_ns)
                        push_event!(s, ErrorEvent("aborted", partial))
                        return
                    end
                    continue
                end
            else
                last_error = sprint(showerror, outcome[2])
                if attempt <= max_retries && !started[]
                    wait_ms = backoff_ms(attempt; cap_ms=opts.max_retry_delay_ms)
                    @warn "provider connection retry" _group=LOG_TAG attempt=attempt
                    sleep_abortable(wait_ms / 1000, opts.signal) && begin
                        partial.stop_reason = "aborted"
                        partial.error_message = "Request aborted"
                        partial.duration_ms = _duration_ms(start_ns)
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
