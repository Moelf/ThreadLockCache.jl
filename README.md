# ThreadLockCache

[![Build Status](https://github.com/Moelf/ThreadLockCache.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Moelf/ThreadLockCache.jl/actions/workflows/CI.yml?query=branch%3Amain)

** This is not a production ready package, in the sense that the community is
unable to decide what's the best practice in general at the moment. **

## What does this pkg do?
It's basically an alternative to
[MultiThreadedCaches.jl](https://github.com/JuliaConcurrent/MultiThreadedCaches.jl) and/or
[LRUCache.jl](https://github.com/JuliaCollections/LRUCache.jl).

### Difference from MultiThreadedCaches.jl

- There's no "base cache", only 1 slot per `threadid()`
- Don't use this package when threads are expected to miss local cahce a lot
- Do use this package when you want to avoid overhead of checking/copying against "base cache"

### Difference from LRUCache.jl

- We use `==` insead of `hash()` to compare key
- We use `Vector{K}` and `Vector{V}` instead of a `Dict{K, V}` internally
- Because each slot in keys and values has its own lock, we reduce contention when
you need to check "cache hit" in a tight loop.

## Why?

Because multi-threaded cache is hard:
```julia
julia> f(i) = (sleep(0.0001); i)
f (generic function with 1 method)

julia> function bad()
           bad_buffer = zeros(Int, Threads.maxthreadid())
           @sync for i = 1:100
               Threads.@spawn begin
               tid = Threads.threadid()
               bad_buffer[tid] += f(i)
               end
           end
           return sum(bad_buffer)
       end
bad (generic function with 1 method)

julia> [bad() for _ = 1:5]
5-element Vector{Int64}:
 240
 167
 256
 222
 107
```

Btw, you don't even need multiple threads to make this go bad
```julia
julia> function bad_async()
           bad_buffer = zeros(Int, Threads.maxthreadid())
           @sync for i = 1:100
               @async begin
               tid = Threads.threadid()
               bad_buffer[tid] += f(i)
               end
           end
           return sum(bad_buffer)
       end
bad_async (generic function with 1 method)

julia> [bad_async() for _ = 1:5]
5-element Vector{Int64}:
 100
 100
 100
 100
 100
```

Still incorrect if you're using `@threads`:
```julia
julia> function bad_threads()
           bad_buffer = zeros(Int, Threads.maxthreadid())
           Threads.@threads for i = 1:100
               tid = Threads.threadid()
               bad_buffer[tid] += f(i)
           end
           return sum(bad_buffer)
       end
bad_threads (generic function with 1 method)

julia> [bad_threads() for _ = 1:5]
5-element Vector{Int64}:
 5050
 5050
 5050
 4998
 5050
```
