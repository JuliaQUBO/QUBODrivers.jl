@doc raw"""
    AbstractSampler{T} <: MOI.AbstractOptimizer
"""
abstract type AbstractSampler{T} <: MOI.AbstractOptimizer end

@doc raw"""
    sample(::AbstractSampler{T})::SampleSet{T} where {T}
"""
function sample end

function sample(::AbstractSampler{T})::SampleSet{T} where {T} 
    return SampleSet{T}()
end