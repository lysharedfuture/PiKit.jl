const LOG_TAG = "pikit_cli_modes_print"

function _assistant_text(msg::PiAISDK.AssistantMessage)
    return join([c.text for c in msg.content if c isa PiAISDK.TextContent], "\n")
end

function _assistant_exit_code(msg::Union{Nothing,PiAISDK.AssistantMessage})
    msg === nothing && return 0
    if msg.stop_reason == "error"
        println(stderr, something(msg.error_message, "Request failed"))
        return 1
    elseif msg.stop_reason == "aborted"
        println(stderr, something(msg.error_message, "Request aborted"))
        return 1
    elseif msg.stop_reason == "length"
        println(stderr, "Response was truncated: the model reached its output token limit.")
        return 1
    end
    return 0
end

"""
    run_print_mode(s::AgentSession, prompt_text::String; images=ImageContent[])

Send one prompt, print the final assistant text to stdout, and return the
process exit code (`0` success, `1` for error/aborted/truncated responses).
"""
function run_print_mode(s::AgentSession, prompt_text::String; images=PiAISDK.ImageContent[])
    isempty(prompt_text) && isempty(images) && return 0
    prompt!(s, prompt_text; images=images)
    msg = s.last_assistant
    if msg === nothing
        return 0
    end
    code = _assistant_exit_code(msg)
    if msg.stop_reason in ("stop", "toolUse", "length")
        text = _assistant_text(msg)
        isempty(text) || println(stdout, text)
    end
    return code
end
