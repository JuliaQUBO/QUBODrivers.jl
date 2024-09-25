module ExactSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

@doc raw"""
    ExactSampler.Optimizer{T}

This sampler performs an exhaustive search over all ``2^{n}`` possible states.

!!! warn
    Due to the exponetially large amount of visited states, it is not possible
    to use this sampler for problems any larger than ``20`` variables big.
"""
QUBODrivers.@setup Optimizer begin
    name    = "Exact Sampler"
    version = QUBODrivers.__version__()
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
    metadata = Dict{String,Any}(
        "origin" => "Exact Sampler @ QUBODrivers.jl",
        "time"   => Dict{String,Any}("effective" => results.time),
        "status" => "optimal",
    )

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module