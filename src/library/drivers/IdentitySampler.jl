module IdentitySampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

@doc raw"""
    IdentitySampler.Optimizer{T}

This sampler selects precisely the state vector provided as warm-start.
"""
QUBODrivers.@setup Optimizer begin
    name = "Identity Sampler"
end

function sample_state(sampler::Optimizer{T}, n::Integer) where {T}
    return round.(Int, start.(sampler, 1:n))
end

function sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min)

    # Retrieve warm-start state
    samples = Vector{Sample{T,Int}}(undef, 1)
    results = @timed begin
        ψ = sample_state(sampler, n)
        λ = QUBOTools.value(L, Q, ψ, α, β)

        samples[] = Sample{T}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = Dict{String,Any}(
        "origin" => "Identity Sampler @ QUBODrivers.jl",
        "time"   => Dict{String,Any}("effective" => results.time),
    )

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module