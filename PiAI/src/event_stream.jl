const LOG_TAG = "ai_event_stream"

"""
    AssistantMessageEventStream

Channel-backed stream of `AbstractAssistantMessageEvent`. The producer task is
started by the constructor and the channel is always closed at the end.
"""
mutable struct AssistantMessageEventStream
    channel::Channel{AbstractAssistantMessageEvent}
    task::Union{Nothing,Task}
    final::Ref{Union{Nothing,AssistantMessage}}
    closed::Bool
end

function AssistantMessageEventStream(producer::Function)
    s = AssistantMessageEventStream(Channel{AbstractAssistantMessageEvent}(32), nothing,
                                    Ref{Union{Nothing,AssistantMessage}}(nothing), false)
    s.task = @async begin
        try
            producer(s)
        catch err
            @error "provider stream crashed" _group=LOG_TAG exception=(err, catch_backtrace())
            if s.final[] === nothing
                msg = AssistantMessage(AbstractContent[]; stop_reason="error",
                                       error_message=sprint(showerror, err))
                s.final[] = msg
                try
                    put!(s.channel, ErrorEvent("error", msg))
                catch err
                    @debug "unable to enqueue provider error" _group=LOG_TAG exception=(err, catch_backtrace())
                end
            end
        finally
            if !s.closed
                s.closed = true
                close(s.channel)
            end
        end
    end
    return s
end

function push_event!(s::AssistantMessageEventStream, ev)
    if ev isa DoneEvent
        s.final[] = ev.message
    elseif ev isa ErrorEvent
        s.final[] = ev.error
    end
    try
        put!(s.channel, ev)
    catch err
        @debug "event stream closed" _group=LOG_TAG exception=(err, catch_backtrace())
    end
    return nothing
end

finish!(s::AssistantMessageEventStream, msg::AssistantMessage) = (s.final[] = msg)

function result(s::AssistantMessageEventStream)
    s.task === nothing || wait(s.task)
    if s.final[] === nothing
        return AssistantMessage(AbstractContent[]; stop_reason="error",
                                error_message="provider produced no final message")
    end
    return s.final[]
end

Base.iterate(s::AssistantMessageEventStream) = iterate(s.channel)
Base.iterate(s::AssistantMessageEventStream, state) = iterate(s.channel, state)
Base.eltype(::Type{AssistantMessageEventStream}) = AbstractAssistantMessageEvent
Base.IteratorSize(::Type{AssistantMessageEventStream}) = Base.SizeUnknown()
Base.isdone(s::AssistantMessageEventStream) = isready(s.channel) ? false : !isopen(s.channel)
