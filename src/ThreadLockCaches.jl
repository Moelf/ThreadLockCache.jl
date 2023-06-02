module ThreadLockCaches

export ThreadLockCache

struct ThreadLockCache{K, V}
    buffer_keys::Vector{K}
    buffer_values::Vector{V}
    thread_locks::Vector{ReentrantLock}
    function ThreadLockCache(Ks::Vector{K}, Vs::Vector{V}, thread_locks::Vector{ReentrantLock}) where {K, V}
        nt = isdefined(Base.Threads, :maxthreadid) ? Threads.maxthreadid() : Threads.nthreads()
        if length(Ks) != length(Vs) != nt
            error("length of keys/values must equal to # of threads at the moment (nt = $nt)")
        end
        new{K, V}(Ks, Vs, thread_locks)
    end
end

function ThreadLockCache{K, V}() where {K, V}
    buffer_keys = K[]
    buffer_values = V[]
    thread_locks = ReentrantLock[]
    TLC = ThreadLockCache(buffer_keys, buffer_values, thread_locks)
    init_cache!(TLC)
    return TLC
end

function ThreadLockCache(Ks::Vector{K}, Vs::Vector{V}) where {K, V}
    thread_locks = [ReentrantLock() for _ in eachindex(Ks)]
    TLC = ThreadLockCache(Ks, Vs, thread_locks)
    init_cache!(TLC)
    return TLC
end

"""
    init_cache!(cache::MultiThreadedCache{K,V})

This function must be called whenever number of threads increased (e.g adopting foreign threads).

!!! note
    This function is *not thread safe*, it must not be called concurrently with any other
    code that touches the cache. This should only be called during cache initialization or whenever 
    number of threads increased.
"""
function init_cache!(cache::ThreadLockCache)
    nt = isdefined(Base.Threads, :maxthreadid) ? Threads.maxthreadid() : Threads.nthreads()
    resize!(cache.buffer_keys, nt)
    resize!(cache.buffer_values, nt)
    resize!(cache.thread_locks, nt)

    for i in eachindex(cache.thread_locks)
        cache.thread_locks[i] = ReentrantLock()
    end

    return cache
end

function Base.get!(func::F, cache::ThreadLockCache{K,V}, key::K) where {F,K,V}
    tid = Threads.threadid()
    tlock = cache.thread_locks[tid]

    v = Base.@lock tlock begin
        if isassigned(cache.buffer_keys, tid) && 
            isassigned(cache.buffer_values, tid) && cache.buffer_keys[tid] == key
            cache.buffer_values[tid]
        else
            cache.buffer_keys[tid] = key
            cache.buffer_values[tid] = func()
        end
    end

    return v
end

function Base.show(io::IO, cache::ThreadLockCache{K, V}) where {K, V}
    N = length(cache.thread_locks)
    println(io, "ThreadLockCache (with slots for $N threads):")
    println(io, "      key_slots: ", cache.buffer_keys)
    println(io, "    value_slots: ", cache.buffer_values)
    nothing
end

end
