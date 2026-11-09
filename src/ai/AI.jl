module AI

using Logging
using Dates
using Random
using JSON
using HTTP

include("types.jl")
include("json.jl")
include("abort.jl")
include("event_stream.jl")
include("sse.jl")
include("schema.jl")
include("models.jl")
include("credentials.jl")
include("retry.jl")
include("overflow.jl")
include("providers/common.jl")
include("providers/http_utils.jl")
include("providers/openai_completions.jl")
include("providers/anthropic_messages.jl")
include("providers/faux.jl")
include("providers/registry.jl")

export AbstractContent, TextContent, ImageContent, ThinkingContent, ToolCall,
       Cost, Usage, empty_usage, token_total, copy_usage, apply_cost!,
       AbstractMessage, AbstractAgentMessage, SystemMessage, UserMessage,
       AssistantMessage, ToolResultMessage, as_content,
       Model, ModelCost, ToolDeclaration, AbortToken, abort!, on_abort, is_aborted,
       StreamOptions, LLMContext, normalize_context, empty_assistant,
       AbstractAssistantMessageEvent, StartEvent, TextStartEvent, TextDeltaEvent,
       TextEndEvent, ThinkingStartEvent, ThinkingDeltaEvent, ThinkingEndEvent,
       ToolCallStartEvent, ToolCallDeltaEvent, ToolCallEndEvent, DoneEvent, ErrorEvent,
       AssistantMessageEventStream, push_event!, result, finish!,
       foreach_sse, SSEEvent, json_parse, json_write, to_json, message_to_json,
       message_from_json, content_from_json, usage_to_json, usage_from_json,
       validate_arguments, load_models, load_user_models, all_models, find_model,
       resolve_api_key, is_retryable_assistant_error, is_retryable_error_text,
       is_non_retryable_error, retry_delay_ms, is_context_overflow,
       PROVIDERS, register_provider!, provider_registered, stream,
       faux_text, faux_thinking, faux_tool_call, faux_assistant_message,
       set_responses!, append_responses!, reset_faux!, faux_call_count,
       faux_last_context, faux_last_model, load_faux_responses,
       register_faux_provider!, EMPTY_USAGE, THINKING_LEVELS, STOP_REASONS, time_millis

function __init__()
    register_provider!("openai-completions", stream_openai)
    register_provider!("anthropic-messages", stream_anthropic)
    register_provider!("faux", stream_faux; model=Model("faux-1", "Faux Model", "faux", "faux",
                                                        "http://faux.invalid"; reasoning=true))
    return nothing
end

end # module AI
