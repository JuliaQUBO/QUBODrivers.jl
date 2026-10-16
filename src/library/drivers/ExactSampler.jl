module ExactSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

@doc raw"""
    ExactSampler.Optimizer{T}

This sampler performs an exhaustive search over all ``2^{n}`` possible states.
It is useful as a correctness oracle for small QUBO and Ising models.

!!! warn
    Due to the exponentially large number of visited states, this sampler is
    intended only for small instances.

`ExactSampler` ignores `QUBODrivers.FinalNumberOfReads`; it always returns the
full exhaustive sample set. A completed solve exposes `MOI.OPTIMAL` through
`MOI.TerminationStatus()`. Post-sample transformations do not retain that
certificate; annotation-only callbacks preserve it.
"""
QUBODrivers.@setup Optimizer begin
    name    = "Exact Sampler"
    version = QUBODrivers.__version__()
end

QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = false

function MOI.optimize!(sampler::Optimizer{T}) where {T}
    # A failed repeated solve must not expose the previous exhaustive result.
    QUBOTools.attach!(sampler, SampleSet{T,Int}(;
        metadata = Dict{String,Any}("status" => "sampling"),
        sense = QUBOTools.sense(sampler), domain = QUBOTools.domain(sampler)))
    return QUBODrivers._sample!(sampler)
end

function MOI.get(sampler::Optimizer{T}, attr::MOI.TerminationStatus) where {T}
    samples = QUBOTools.solution(sampler)
    metadata = QUBOTools.metadata(samples)
    if !isempty(samples) && get(metadata, "termination_status", nothing) === MOI.OPTIMAL
        postprocess = get(metadata, "postprocess", nothing)
        callback = postprocess isa AbstractDict ? get(postprocess, "callback", nothing) : nothing
        transformed = callback isa AbstractDict && get(callback, "transformed", false) === true
        transformed || return MOI.OPTIMAL
    end
    return invoke(MOI.get, Tuple{QUBODrivers.AbstractSampler{T},MOI.TerminationStatus}, sampler, attr)
end

sample_state(i::Integer, n::Integer) = digits(Int, i - 1; base = 2, pad = n)

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    n, L, Q, α, β = QUBOTools.qubo(sampler, :sparse; sense = :min)

    # Retrieve Attributes
    m = 2^n

    # Sample states & measure time
    samples = Vector{Sample{T,Int}}(undef, m)
    results = @timed for i = 1:m
        ψ = sample_state(i, n)
        λ = QUBOTools.value(ψ, L, Q, α, β)

        samples[i] = Sample{T}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = QUBODrivers._sampler_metadata(
        origin                = "Exact Sampler @ QUBODrivers.jl",
        algorithm_name        = "Exact Sampler",
        execution_mode        = "exhaustive_search",
        optimizer_evaluations = m,
        number_of_reads       = m,
        final_number_of_reads = m,
        status                = "optimal",
        termination_status    = MOI.OPTIMAL,
    )
    metadata["time"] = Dict{String,Any}("effective" => results.time)

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module
