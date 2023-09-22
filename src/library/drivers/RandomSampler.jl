module RandomSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

using Random

@doc raw"""
    RandomSampler.Optimizer{T}

## Attributes
- `RandomSeed`, `"seed"`: Random seed to initialize the random number generator.
- `NumberOfReads`, `"num_reads"`: Number of random states sampled per run.
- `RandomGenerator`, `"rng"`: Random Number Generator instance.
"""
QUBODrivers.@setup Optimizer begin
    name       = "Random Sampler"
    version    = v"0.3.0"
    attributes = begin
        RandomSeed["seed"]::Union{Integer,Nothing} = nothing
        NumberOfReads["num_reads"]::Integer        = 1_000
        RandomGenerator["rng"]::AbstractRNG        = Random.GLOBAL_RNG
    end
end

sample_state(rng::AbstractRNG, n::Integer) = rand(rng, (0, 1), n)

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min)

    # Retrieve Attributes
    num_reads = MOI.get(sampler, NumberOfReads())
    seed      = MOI.get(sampler, RandomSeed())
    rng       = MOI.get(sampler, RandomGenerator())

    # Validate Input
    @assert num_reads >= 0
    @assert isnothing(seed) || seed >= 0
    @assert rng isa AbstractRNG

    # Seed Random Number generator
    Random.seed!(rng, seed)

    # Sample Random States
    samples = Vector{Sample{T,Int}}(undef, num_reads)
    results = @timed for i = 1:num_reads
        ψ = sample_state(rng, n)::Vector{Int}
        λ = QUBOTools.value(ψ, L, Q, α, β)

        samples[i] = Sample{T,Int}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = Dict{String,Any}(
        "origin" => "Random Sampler @ QUBODrivers.jl",
        "time"   => Dict{String,Any}("effective" => results.time),
    )

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module