const LOG_TAG = "logging"

const LOG_LEVEL_NAMES = Dict{String,LogLevel}(
    "debug" => Logging.Debug,
    "info" => Logging.Info,
    "warn" => Logging.Warn,
    "error" => Logging.Error,
)

const SENSITIVE_KEY = r"(?i)(authorization|api[-_]?key|x-api-key|token|secret|password|credential)"

"""
    redact(value)

Recursively replace values of credential-like keys with `"[REDACTED]"`.
Used before logging payloads or provider options.
"""
redact(x) = x
redact(d::AbstractDict) = Dict{Any,Any}(k => (occursin(SENSITIVE_KEY, String(k)) ? "[REDACTED]" : redact(v)) for (k, v) in d)
redact(v::AbstractVector) = [redact(x) for x in v]
redact(s::AbstractString) = s
redact(x::NamedTuple) = NamedTuple{keys(x)}(map(redact, values(x)))

function default_log_file()
    dir = get(ENV, "PIKIT_AGENT_DIR", joinpath(homedir(), ".pikit", "agent"))
    return get(ENV, "PIKIT_LOG_FILE", joinpath(dir, "logs", "app.log"))
end

function parse_log_spec(spec::AbstractString)
    global_level = "info"
    tags = Dict{String,LogLevel}()
    for part in split(spec, ','; keepempty=false)
        item = strip(part)
        isempty(item) && continue
        if occursin('=', item)
            tag, level = split(item, '='; limit=2)
            tag = strip(tag)
            lvl = lowercase(strip(level))
            haskey(LOG_LEVEL_NAMES, lvl) && (tags[tag] = LOG_LEVEL_NAMES[lvl])
        else
            lvl = lowercase(item)
            haskey(LOG_LEVEL_NAMES, lvl) && (global_level = lvl)
        end
    end
    return LOG_LEVEL_NAMES[global_level], tags
end

"""
    TagFilterLogger

File-first logger. Level selection is per `_group` (which each source file sets
to its `LOG_TAG`). stderr mirroring is opt-in via `PIKIT_LOG_STDERR=1`.
"""
mutable struct TagFilterLogger <: AbstractLogger
    sink::IO
    owns_sink::Bool
    sink_lock::ReentrantLock
    stderr_mirror::Bool
    global_level::LogLevel
    tag_levels::Dict{String,LogLevel}
    fallback::Bool
    warned::Bool
    closed::Bool
end

function TagFilterLogger(; file::Union{Nothing,AbstractString}=nothing,
                         stderr::Bool=false,
                         spec::AbstractString=get(ENV, "PIKIT_LOG", "info"))
    global_level, tag_levels = parse_log_spec(spec)
    io = stderr ? Base.stderr : IOBuffer()
    logger = TagFilterLogger(io, false, ReentrantLock(), stderr, global_level, tag_levels, false, false, false)
    if !stderr && file !== nothing
        try
            mkpath(dirname(String(file)))
            logger.sink = open(String(file), "a")
            logger.owns_sink = true
        catch err
            logger.fallback = true
            logger.sink = Base.stderr
            logger.owns_sink = false
            logger.warned = true
            println(Base.stderr, "[pikit] log file unavailable ($file): $(sprint(showerror, err)); logging to stderr")
        end
    elseif !stderr
        logger.sink = devnull
        logger.owns_sink = false
    end
    return logger
end

function min_level(logger::TagFilterLogger, group)
    name = group === nothing ? "" : String(group)
    return get(logger.tag_levels, name, logger.global_level)
end

function Logging.shouldlog(logger::TagFilterLogger, level, _module, group, id)
    return !logger.closed && level >= min_level(logger, group)
end

function Logging.min_enabled_level(logger::TagFilterLogger)
    level = logger.global_level
    for l in values(logger.tag_levels)
        level = min(level, l)
    end
    return level
end

Logging.catch_exceptions(::TagFilterLogger) = false

function format_log_value(v)
    v isa AbstractString && return repr(v)
    return string(v)
end

function Logging.handle_message(logger::TagFilterLogger, level, message, _module, group, id, file, line; kwargs...)
    logger.closed && return
    name = group === nothing ? "" : String(group)
    ts = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS.mmm")
    lvl = lowercase(string(level))
    extras = IOBuffer()
    for (k, v) in kwargs
        print(extras, ' ', k, '=', format_log_value(redact(v)))
    end
    text = string("[", ts, "] [", lvl, "] [", name, "] ", message, String(take!(extras)), "\n")
    lock(logger.sink_lock) do
        try
            write(logger.sink, text)
            flush(logger.sink)
        catch
            if !logger.warned
                logger.warned = true
                println(Base.stderr, "[pikit] log write failed; falling back to stderr")
            end
            logger.fallback = true
        end
        if logger.stderr_mirror && logger.sink !== Base.stderr
            try
                write(Base.stderr, text)
                flush(Base.stderr)
            catch err
                println(Base.stderr, "[pikit] stderr mirror failed: ", sprint(showerror, err))
            end
        end
    end
    return nothing
end

const _LOGGING_INSTALLED = Ref(false)

function install_logging!()
    _LOGGING_INSTALLED[] && return
    _LOGGING_INSTALLED[] = true
    logger = TagFilterLogger(
        file=default_log_file(),
        stderr=get(ENV, "PIKIT_LOG_STDERR", "0") == "1",
    )
    Logging.global_logger(logger)
    return logger
end

function close_logging!()
    logger = Logging.global_logger()
    if logger isa TagFilterLogger && logger.owns_sink && !logger.closed
        logger.closed = true
        if isopen(logger.sink)
            try
                close(logger.sink)
            catch err
                println(Base.stderr, "[pikit] log close failed: ", sprint(showerror, err))
            end
        end
    end
    _LOGGING_INSTALLED[] = false
    Logging.global_logger(ConsoleLogger())
    return nothing
end
