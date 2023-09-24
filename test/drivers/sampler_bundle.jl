include("exact_sampler.jl")
include("identity_sampler.jl")
include("random_sampler.jl")

function test_sampler_bundle()
    @testset "□ Utility Samplers Bundle" verbose = true begin
        test_exact_sampler()
        test_identiy_sampler()
        test_random_sampler()
    end

    return nothing
end
