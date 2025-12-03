module QUBODrivers_Test_Ext

import Test
import QUBODrivers
import MathOptInterface as MOI
using QUBOTools: ↑, ↓

const VI     = MOI.VariableIndex
const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}
const SQF{T} = MOI.ScalarQuadraticFunction{T}
const SQT{T} = MOI.ScalarQuadraticTerm{T}
const Spin   = QUBODrivers.Spin

# Interface Tests
include("interface/moi.jl")
include("interface/automatic.jl")

# Example Tests
include("examples/examples.jl")

function QUBODrivers.test(::Type{S}; examples::Bool = true) where {S<:QUBODrivers.AbstractSampler}
    QUBODrivers.test(identity, S; examples)

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
) where {S<:QUBODrivers.AbstractSampler}
    QUBODrivers.test(config!, S{Float64}; examples)

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    sampler = S()

    sampler_name    = MOI.get(sampler, MOI.SolverName())
    sampler_version = MOI.get(sampler, MOI.SolverVersion())

    Test.@testset "☢ QUBODrivers' Test Suite for «$(sampler_name) v$(sampler_version)» ☢" verbose = true begin
        Test.@testset "→ Interface" begin
            _test_moi_interface(config!, S)
            _test_automatic_interface(config!, S)
        end

        if examples
            _test_examples(config!, S)
        end
    end

    return nothing
end

end