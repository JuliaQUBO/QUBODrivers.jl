using Test
using PythonCall
using QUBODrivers
using QUBODrivers: MOI, QUBOTools

const MOIU = MOI.Utilities
const VI   = MOI.VariableIndex

include("assets/test_macro_throws.jl")

include("setup/setup.jl")
include("drivers/sampler_bundle.jl")

include("ext/ext.jl")

function main()
    @testset "◈ ◈ ◈ QUBODrivers.jl Test Suite ◈ ◈ ◈" verbose = true begin
        test_setup_macro()
        test_sampler_bundle()
        test_extensions()
    end

    return nothing
end

main() # Here we go!
