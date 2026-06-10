module QUBODrivers_Test_Ext

import Test
import QUBODrivers
import MathOptInterface as MOI
import QUBOTools
using QUBOTools: ↑, ↓

const VI     = MOI.VariableIndex
const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}
const SQF{T} = MOI.ScalarQuadraticFunction{T}
const SQT{T} = MOI.ScalarQuadraticTerm{T}
const Spin   = QUBODrivers.Spin

# Interface Tests
include("interface/fixed.jl")
include("interface/moi.jl")
include("interface/automatic.jl")
include("interface/benchmark_conformance.jl")

# Example Tests
include("examples/examples.jl")

function QUBODrivers.test(
    ::Type{S};
    examples::Bool = true,
    benchmark_conformance::Bool = true,
    metadata_conformance::Bool = benchmark_conformance,
    timing_sanity::Bool = benchmark_conformance,
    determinism = benchmark_conformance ? :auto : false,
    reads_semantics::Bool = benchmark_conformance,
    time_limit_acceptance::Bool = benchmark_conformance,
    termination_status::Bool = benchmark_conformance,
) where {S<:QUBODrivers.AbstractSampler}
    QUBODrivers.test(
        identity,
        S;
        examples,
        benchmark_conformance,
        metadata_conformance,
        timing_sanity,
        determinism,
        reads_semantics,
        time_limit_acceptance,
        termination_status,
    )

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
    benchmark_conformance::Bool = true,
    metadata_conformance::Bool = benchmark_conformance,
    timing_sanity::Bool = benchmark_conformance,
    determinism = benchmark_conformance ? :auto : false,
    reads_semantics::Bool = benchmark_conformance,
    time_limit_acceptance::Bool = benchmark_conformance,
    termination_status::Bool = benchmark_conformance,
) where {S<:QUBODrivers.AbstractSampler}
    QUBODrivers.test(
        config!,
        S{Float64};
        examples,
        benchmark_conformance,
        metadata_conformance,
        timing_sanity,
        determinism,
        reads_semantics,
        time_limit_acceptance,
        termination_status,
    )

    return nothing
end

function QUBODrivers.test(
    config!::Function,
    ::Type{S};
    examples::Bool = true,
    benchmark_conformance::Bool = true,
    metadata_conformance::Bool = benchmark_conformance,
    timing_sanity::Bool = benchmark_conformance,
    determinism = benchmark_conformance ? :auto : false,
    reads_semantics::Bool = benchmark_conformance,
    time_limit_acceptance::Bool = benchmark_conformance,
    termination_status::Bool = benchmark_conformance,
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

        if benchmark_conformance ||
           metadata_conformance ||
           timing_sanity ||
           _run_seed_determinism(determinism, S) ||
           reads_semantics ||
           time_limit_acceptance ||
           termination_status
            _test_benchmark_conformance(
                config!,
                S;
                metadata_conformance,
                timing_sanity,
                determinism,
                reads_semantics,
                time_limit_acceptance,
                termination_status,
            )
        end
    end

    return nothing
end

end
