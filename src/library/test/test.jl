# Interface Tests
include("interface/moi.jl")
include("interface/automatic.jl")

# Example Tests
include("examples/examples.jl")

@doc raw"""
    test(optimizer::Type{S}; examples::Bool=false) where {S<:AbstractSampler}
    test(config!::Function, optimizer::Type{S}; examples::Bool=false) where {S<:AbstractSampler}
"""
function test end

function QUBODrivers.test(::Type{S}; examples::Bool = true) where {S<:AbstractSampler}
    QUBODrivers.test(identity, S; examples)

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
) where {S<:AbstractSampler}
    QUBODrivers.test(config!, S{Float64}; examples)

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
) where {T,S<:AbstractSampler{T}}
    solver = S()

    solver_name    = MOI.get(solver, MOI.SolverName())
    solver_version = MOI.get(solver, MOI.SolverVersion())

    Test.@testset "☢ QUBODrivers' Test Suite for «$(solver_name) v$(solver_version)» ☢" verbose = true begin
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