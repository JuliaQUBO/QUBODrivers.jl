module RandomSampler

import QUBOTools
import QUBODrivers: MOI, Sample, SampleSet, @setup, sample, qubo

using Random

@setup Optimizer begin
    name       = "Random Sampler"
    sense      = :min
    domain     = :bool
    version    = v"0.6.0"
    attributes = begin
        RandomSeed["seed"]::Union{Integer,Nothing} = nothing
        NumberOfReads["num_reads"]::Integer        = 1_000
        RandomGenerator["rng"]::AbstractRNG        = Random.GLOBAL_RNG
    end
end

@doc raw"""
    RandomSampler.Optimizer{T}

## Attributes
- `RandomSeed`, `"seed"`: Random seed to initialize the random number generator.
- `NumberOfReads`, `"num_reads"`: Number of random states sampled per run.
- `RandomGenerator`, `"rng"`: Random Number Generator instance.
""" Optimizer

sample_state(rng::AbstractRNG, n::Integer) = rand(rng, (0, 1), n)

function sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    Q, α, β = qubo(sampler, Dict)

    # Retrieve Attributes
    n         = MOI.get(sampler, MOI.NumberOfVariables())
    num_reads = MOI.get(sampler, RandomSampler.NumberOfReads())
    seed      = MOI.get(sampler, RandomSampler.RandomSeed())
    rng       = MOI.get(sampler, RandomSampler.RandomGenerator())

    # Validate Input
    @assert num_reads >= 0
    @assert isnothing(seed) || seed >= 0
    @assert rng isa AbstractRNG

    # Seed Random Number generator
    Random.seed!(rng, seed)

    # Sample Random States
    samples = Vector{Sample{T,Int}}(undef, num_reads)
    results = @timed for i = 1:num_reads
        ψ = sample_state(rng, n)
        λ = QUBOTools.value(Q, ψ, α, β)

        samples[i] = Sample{T,Int}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = Dict{String,Any}(
        "origin" => "Random Sampler @ QUBODrivers.jl",
        "time"   => Dict{String,Any}("effective" => results.time),
    )

    return SampleSet{T}(samples, metadata)
end

end # module