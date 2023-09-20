@doc raw"""
    AbstractSampler{T} <: MOI.AbstractOptimizer
"""
abstract type AbstractSampler{T} <: MOI.AbstractOptimizer end

@doc raw"""
    sample(::AbstractSampler{T})::SampleSet{T} where {T}
"""
function sample end

function sample(::S) where {S<:AbstractSampler}
    error("`QUBODrivers.sample` is not implemented for '$S'")

    return nothing
end

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
