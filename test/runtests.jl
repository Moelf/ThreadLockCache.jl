using ThreadLockCaches
using ThreadLockCaches: init_cache!
using LRUCache
using Test

@info "Testing with:" Threads.nthreads()

@testset "basics" begin
    cache = ThreadLockCache{Int,Int}()
    init_cache!(cache)

    @test length(cache.thread_locks) == Threads.nthreads()

    get!(cache, 1) do
        return 10
    end

    # The second get!() shouldn't have any effect, and the result should still be 10.
    @test get!(cache, 1) do
        return 100
    end == 10

end
@testset "KV types" begin
    cache = ThreadLockCache{Int,String}()
    init_cache!(cache)

    @test get!(()->"hi", cache, 1) == "hi"
    @test get!(()->"bye", cache, 1) == "hi"

    cache = ThreadLockCache{Any,Any}()
    init_cache!(cache)

    @test get!(()->"hi", cache, 1) == "hi"
    @test get!(()->2.0, cache, 1) == "hi"
    @test get!(()->3.0, cache, 1.0) == "hi"
end


populate!(c,x) = get!(c, x) do
    UInt64(2)
end

@testset "no allocations for cache-hit" begin
    cache = ThreadLockCache{Int64, Int64}()
    init_cache!(cache)

    # Populate the cache
    populate!(cache, 10)

    @test @allocated(populate!(cache, 10)) == 0
    @test @allocated(populate!(cache, 10)) == 0

    populate!(cache, 11)
    @test @allocated(populate!(cache, 11)) == 0
end


const Nevents = 10^4
const ClusterSize = 1000
## ====================shared utility and mock function================================
function _mock_io(cluster)
    # can be cached by using `cluster` or its `start` as key
    start = first(cluster)
    res = [collect(i:i+20)./start for i in 1:ClusterSize]
    for _ in 1:400, i in res
        i .= sin.(i)
        i .= exp.(i)
        i .= cos.(i)
    end
    return res
end

const all_indicies = 1:Nevents

# this does not have to be evenly distributed
const all_ranges = Base.Iterators.partition(all_indicies, ClusterSize)

# everytime user index into the column, they get back 1 element in a cluster
# we need to find the cluster range that contains this index
function _findrange(cluster_ranges, idx)
    for cluster in cluster_ranges
        first_entry = first(cluster) 
        n_entries = length(cluster) # the real structure record this instead of last()
        if first_entry + n_entries - 1 >= idx
            return cluster
        end
    end
end

## ====================different getindex implementations=========================
# function no_cache_getindex(idx)
#     cluster = _findrange(all_ranges, idx)
#     localidx = idx - first(cluster) + 1
#     data = _mock_io(cluster)
#     return data[localidx]
# end

const lru = LRU{Int64, Vector{Vector{Float64}}}(; maxsize = Threads.nthreads())
function LRU_getindex(idx)
    cluster = _findrange(all_ranges, idx)
    key = first(cluster)
    data = get!(lru, key) do
        res = _mock_io(cluster)
    end
    localidx = idx - first(cluster) + 1
    return data[localidx]
end

const TLC = ThreadLockCache{UnitRange{Int64}, Vector{Vector{Float64}}}()
function TLC_getindex(idx)
    cluster = _findrange(all_ranges, idx)
    data = get!(TLC, cluster) do
        res = _mock_io(cluster)
    end
    localidx = idx - first(cluster) + 1
    return data[localidx]
end
@testset "Benchmark" begin

    ## ================================================================ 
    ##################### user code ############################
    function user_code(MyGet::F) where F
        ch = Channel{Float64}(Nevents)
        Threads.@threads for i in 1:Nevents
            put!(ch, sum(MyGet(i)))
        end
        close(ch)
        return sum(ch)
    end

    user_code(TLC_getindex)
    user_code(LRU_getindex)
    tlc_value = @time user_code(TLC_getindex)
    lru_value = @time user_code(LRU_getindex)
    @test tlc_value ≈ lru_value ≈ -48199.884295147735
end
