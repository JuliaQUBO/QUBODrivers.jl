module RandomSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

using Random

@doc raw"""
    RandomSampler.Optimizer{T}

Sampler that evaluates uniformly random states.

`RandomSampler` is a lightweight baseline for smoke tests, examples, and
benchmark harnesses. It samples independent states in the model domain,
evaluates their objective values with QUBOTools, and returns the final sampled
states.

## Attributes
- `QUBODrivers.RandomSeed`, `"seed"`: Random seed to initialize the random
  number generator.
- `NumberOfReads`, `"num_reads"`: Default final read count.
- `QUBODrivers.FinalNumberOfReads`, `"final_num_reads"`: Number of random
  states emitted in the returned sample set. If unset, this defaults to
  `NumberOfReads`.
- `RandomGenerator`, `"rng"`: Random Number Generator instance.
"""
QUBODrivers.@setup Optimizer begin
    name       = "Random Sampler"
    version    = QUBODrivers.__version__()
    attributes = begin
        "seed"::Union{Integer,Nothing}             = nothing
        NumberOfReads["num_reads"]::Integer        = 1_000
        RandomGenerator["rng"]::AbstractRNG        = Random.GLOBAL_RNG
    end
end

QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = true

sample_state(rng::AbstractRNG, n::Integer) = rand(rng, (0, 1), n)

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min)

    # Retrieve Attributes
    num_reads       = MOI.get(sampler, NumberOfReads())
    final_num_reads = MOI.get(sampler, QUBODrivers.FinalNumberOfReads())
    seed            = MOI.get(sampler, QUBODrivers.RandomSeed())
    rng             = MOI.get(sampler, RandomGenerator())

    # Validate Input
    @assert num_reads >= 0
    @assert final_num_reads >= 0
    @assert isnothing(seed) || seed >= 0
    @assert rng isa AbstractRNG

    # Seed Random Number generator
    Random.seed!(rng, seed)

    # Sample Random States
    samples = Vector{Sample{T,Int}}(undef, final_num_reads)
    results = @timed for i = 1:final_num_reads
        ψ = sample_state(rng, n)::Vector{Int}
        λ = QUBOTools.value(ψ, L, Q, α, β)

        samples[i] = Sample{T,Int}(ψ, λ)
    end

    # Write Solution Metadata
    metadata = QUBODrivers._sampler_metadata(
        origin                = "Random Sampler @ QUBODrivers.jl",
        algorithm_name        = "Random Sampler",
        execution_mode        = "random_sampling",
        optimizer_evaluations = final_num_reads,
        number_of_reads       = final_num_reads,
        final_number_of_reads = final_num_reads,
        status                = "locally_solved",
        termination_status    = MOI.LOCALLY_SOLVED,
    )
    metadata["time"] = Dict{String,Any}("effective" => results.time)

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module
