include("exact_sampler.jl")
include("identity_sampler.jl")
include("mip_sampler.jl")
include("random_sampler.jl")
include("benchmark.jl")

function test_sampler_bundle()
    @testset "□ Utility Samplers Bundle" verbose = true begin
        test_exact_sampler()
        test_identiy_sampler()
        test_mip_sampler()
        test_random_sampler()
        test_benchmark_helper()
    end

    return nothing
end
