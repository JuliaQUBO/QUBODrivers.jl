using Test
using QUBODrivers
using QUBODrivers: QUBOTools

include("drivers/exact_sampler.jl")
include("drivers/identity_sampler.jl")
include("drivers/random_sampler.jl")

function test_drivers()
    @testset "Driver Bundle" verbose = true begin
        test_exact_sampler()
        test_identiy_sampler()
        test_random_sampler()
    end

    return nothing
end

function main()
    test_drivers()
end

main() # Here we go!