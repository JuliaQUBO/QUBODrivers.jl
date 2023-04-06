module IdentitySampler

import QUBOTools
import QUBODrivers: MOI, Sample, SampleSet, @setup, sample, qubo, warm_start

@setup Optimizer begin
    name   = "Identity Sampler"
    sense  = :min
    domain = :bool
end

@doc raw"""
    IdentitySampler.Optimizer{T}

This sampler selects precisely the state vector provided as warm-start.
""" Optimizer

function sample_state(sampler::Optimizer{T}, n::Integer) where {T}
    return round.(Int, warm_start.(sampler, 1:n))
end

function sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    Q, α, β = qubo(sampler, Dict)

    # Retrieve Attributes
    n = MOI.get(sampler, MOI.NumberOfVariables())

    # Retrieve warm-start state
    samples = Vector{Sample{T,Int}}(undef, 1)
    results = @timed begin
        ψ = sample_state(sampler, n)
        λ = QUBOTools.value(Q, ψ, α, β)
        
        samples[] = Sample{T}(ψ, λ)
    end 

    # Write Solution Metadata
    metadata = Dict{String,Any}(
        "origin" => "Identity Sampler @ QUBODrivers.jl",
        "time"   => Dict{String,Any}("effective" => results.time),
    )

    return SampleSet{T}(samples, metadata)
end

end # module