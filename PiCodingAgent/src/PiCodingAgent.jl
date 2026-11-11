module PiCodingAgent

using Logging
using Dates
using Random
using UUIDs
using Base64
using Unicode
using HTTP
using ripgrep_jll
using PiAI
using PiAI: plain
using PiAgentCore

include("types.jl")
include("config.jl")
include("tools/truncate.jl")
include("tools/path_utils.jl")
include("tools/file_mutation_queue.jl")
include("tools/shell_env.jl")
include("tools/tools_manager.jl")
include("tools/read.jl")
include("tools/write.jl")
include("tools/edit.jl")
include("tools/bash.jl")
include("tools/powershell.jl")
include("tools/grep.jl")
include("tools/find.jl")
include("tools/ls.jl")
include("tools/registry.jl")
include("system_prompt.jl")
include("session.jl")
include("compaction.jl")
include("runtime.jl")

export AgentSession, create_agent_session, prompt!, continue!, abort!, settle!,
       compact!, close!, subscribe, get_state, set_model!, set_thinking_level!,
       steer!, follow_up!, clear_queues!, set_session_name!, sync_agent_context!,
       SessionManager, SessionHeader, AbstractSessionEntry, MessageEntry, ModelChangeEntry,
       ThinkingLevelChangeEntry, UsageEntry, CompactionEntry, ContextEditEntry,
       SessionInfoEntry, UnknownEntry, create_session, load_session, append_message!,
       append_entry!, build_context, list_sessions, find_session, fork_session, close!,
       header_to_json, entry_to_json, entry_from_json, BashExecutionMessage,
       CompactionSummaryMessage, coding_convert_to_llm, RetryPolicy, retry_policy,
       default_agent_dir, load_settings, user_settings, project_settings, configured_session_dir, is_tty,
       create_tool, create_tools, DEFAULT_TOOL_NAMES, OPTIONAL_TOOL_NAMES,
       read_tool, write_tool, edit_tool, bash_tool, powershell_tool, grep_tool,
       find_tool, ls_tool, truncate_head, truncate_tail, truncate_line, TruncationResult,
       format_size, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES, GREP_MAX_LINE_LENGTH,
       ReadOperations, GrepOperations, FindOperations, LsOperations, BashOperations,
       PowerShellOperations, DEFAULT_READ_OPERATIONS, DEFAULT_GREP_OPERATIONS,
       DEFAULT_FIND_OPERATIONS, DEFAULT_LS_OPERATIONS, DEFAULT_BASH_OPERATIONS,
       resolve_to_cwd, resolve_read_path, path_exists, ensure_tool, default_bash_exec,
       get_shell_config,
       get_powershell_config, get_shell_env, kill_process_tree,
       build_system_sections, build_system_message, estimate_tokens, estimate_context_tokens,
       should_compact, find_cut_point, compact!, session_root, session_dir_for_cwd,
       now_iso, new_entry_id

end # module PiCodingAgent
