@doc raw"""
    AbstractSampler{T} <: MOI.AbstractOptimizer

Abstract supertype for QUBODrivers sampler optimizers.

Concrete sampler optimizers are usually generated with [`QUBODrivers.@setup`](@ref).
They are MathOptInterface optimizers that accept QUBO or Ising models with
binary or spin variables and return one or more sampled states through standard
MOI result attributes.

The type parameter `T` is the numeric coefficient type used by the internal
`QUBOTools.Model`.
"""
abstract type AbstractSampler{T} <: MOI.AbstractOptimizer end

@doc raw"""
    sample(::AbstractSampler{T})::SampleSet{T} where {T}

Run the backend sampler and return a `QUBOTools.SampleSet`.

Sampler packages implement this method for their optimizer type. The method
should read the model from the sampler, read any MOI or raw optimizer
attributes it needs, call the backend, and return a `SampleSet{T}` whose
samples use the same sense and domain as the backend output.

`MOI.optimize!` calls this method and attaches the returned sample set to the
optimizer. If the returned metadata does not include a `"time"` dictionary with
a `"total"` entry, or does not include `"status"`, QUBODrivers fills those
fields with default values.
"""
function sample end

function sample(::S) where {S<:AbstractSampler}
    error("`QUBODrivers.sample` is not implemented for '$S'")
end

function _sampler_metadata(;
    origin::String,
    algorithm_name::String,
    backend_name = "QUBODrivers.jl",
    backend_version = __version__(),
    execution_mode::String,
    optimizer_iterations = nothing,
    optimizer_evaluations = nothing,
    number_of_reads = nothing,
    final_number_of_reads = nothing,
    seeds::Dict{String,Any} = Dict{String,Any}(),
    status::String = "",
    termination_status = nothing,
)
    metadata = Dict{String,Any}(
        "origin"    => origin,
        "algorithm" => Dict{String,Any}(
            "name" => algorithm_name,
        ),
        "backend"   => Dict{String,Any}(
            "name"    => backend_name,
            "version" => backend_version,
        ),
        "execution" => Dict{String,Any}(
            "mode" => execution_mode,
        ),
        "optimizer" => Dict{String,Any}(
            "iterations"  => optimizer_iterations,
            "evaluations" => optimizer_evaluations,
        ),
        "reads"     => Dict{String,Any}(
            "number_of_reads"       => number_of_reads,
            "final_number_of_reads" => final_number_of_reads,
        ),
        "seeds"     => seeds,
        "status"    => status,
    )

    if !isnothing(termination_status)
        metadata["termination_status"] = termination_status
    end

    return metadata
end

@doc raw"""
    set_model!(sampler::AbstractSampler{T}, model::QUBOTools.Model{VI,T,Int}) where {T}

Store the QUBOTools model backing a sampler.

The [`@setup`](@ref) macro provides this method for generated optimizer types.
Custom sampler types that do not use `@setup` must provide it so that
`MOI.copy_to` can transfer JuMP/MOI models into the sampler before
optimization.
"""
function set_model! end

function _sample!(sampler::AbstractSampler{T}) where {T}
    results = @timed sample(sampler)

    _sample!(sampler, results.value, results.time)

    return nothing
end

function _sample!(sampler::AbstractSampler{T}, sampleset::SampleSet{T}, total_time::Float64) where {T}
    metadata = QUBOTools.metadata(sampleset)::Dict{String,Any}

    if !haskey(metadata, "time")
        metadata["time"] = Dict{String,Any}("total" => total_time)
    elseif !haskey(metadata["time"], "total")
        metadata["time"]["total"] = total_time
    end

    if !haskey(metadata, "status")
        metadata["status"] = ""
    end

    QUBOTools.attach!(sampler, sampleset)

    return nothing
end
