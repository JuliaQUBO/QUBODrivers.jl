using Test
using QUBODrivers
using QUBODrivers: QUBOTools

const VI = MOI.VariableIndex

include("setup/setup.jl")
include("drivers/sampler_bundle.jl")

function main()
    @testset "◈ ◈ ◈ QUBODrivers.jl Test Suite ◈ ◈ ◈" verbose = true begin
        test_setup_macro()
        test_sampler_bundle()
    end

    return nothing
end

main() # Here we go!
