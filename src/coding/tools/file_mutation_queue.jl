const LOG_TAG = "coding_tools_file_mutation_queue"

const _FILE_QUEUE_LOCK = ReentrantLock()
const _FILE_QUEUES = Dict{String,ReentrantLock}()

function with_file_lock(f::Function, path::AbstractString)
    key = normpath(abspath(String(path)))
    lk = lock(_FILE_QUEUE_LOCK) do
        get!(_FILE_QUEUES, key, ReentrantLock())
    end
    lock(lk)
    try
        return f()
    finally
        unlock(lk)
    end
end
