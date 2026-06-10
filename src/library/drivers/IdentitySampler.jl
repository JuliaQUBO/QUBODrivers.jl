module IdentitySampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

@doc raw"""
    IdentitySampler.Optimizer{T}

This sampler selects precisely the state vector provided as warm-start.
Use it to check model conversion, objective evaluation, fixed variables, and
warm-start plumbing without invoking a stochastic or external backend.

Every variable must have a valid `MOI.VariablePrimalStart` value before
optimization.

`IdentitySampler` ignores `QUBODrivers.FinalNumberOfReads`; it always returns
the single warm-start state.
"""
QUBODrivers.@setup Optimizer begin
    name    = "Identity Sampler"
    version = QUBODrivers.__version__()
end

QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = false

function sample_state(sampler::Optimizer{T}, n::Integer) where {T}
    ψ = Vector{Int}(undef, n)

    for i = 1:n
        s = QUBOTools.start(sampler, i; domain = :bool)

        if !isnothing(s)
            ψ[i] = s
        else
            v = QUBOTools.variable(sampler, i)

            error("Warm-start value for '$v' is missing")
        end
    end

    return ψ
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min)

    # Retrieve warm-start state
    samples = Vector{Sample{T,Int}}(undef, 1)
    results = @timed begin
        ψ = sample_state(sampler, n)
        λ = QUBOTools.value(ψ, L, Q, α, β)

        samples[] = Sample{T}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = QUBODrivers._sampler_metadata(
        origin                = "Identity Sampler @ QUBODrivers.jl",
        algorithm_name        = "Identity Sampler",
        execution_mode        = "warm_start",
        optimizer_evaluations = 1,
        number_of_reads       = 1,
        final_number_of_reads = 1,
        status                = "locally_solved",
        termination_status    = MOI.LOCALLY_SOLVED,
    )
    metadata["time"] = Dict{String,Any}("effective" => results.time)

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module
