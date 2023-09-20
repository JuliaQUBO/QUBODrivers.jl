# MathOptInterface Attributes
const MOI_ATTRIBUTE = Union{
    MOI.Name,
    MOI.Silent,
    MOI.TimeLimitSec,
    MOI.NumberOfThreads,
    MOI.VariablePrimalStart,
}

mutable struct MOIAttributeData{T}
    name::String
    silent::Bool
    time_limit_sec::Union{Float64,Nothing}
    number_of_threads::Int
    variable_primal_start::Dict{VI,T}

    function MOIAttributeData{T}(;
        name::String                           = "",
        silent::Bool                           = false,
        time_limit_sec::Union{Float64,Nothing} = nothing,
        number_of_threads::Integer             = Threads.nthreads(),
        variable_primal_start                  = Dict{VI,T}(),
    ) where {T}
        return new{T}(
            name,
            silent,
            time_limit_sec,
            number_of_threads,
            variable_primal_start,
        )
    end
end

# MOI.Name
MOI.get(data::MOIAttributeData, ::MOI.Name) = data.name

function MOI.set(data::MOIAttributeData, ::MOI.Name, name::String)
    data.name = name

    return nothing
end

# MOI.Silent
MOI.get(data::MOIAttributeData, ::MOI.Silent) = data.silent

function MOI.set(data::MOIAttributeData, ::MOI.Silent, silent::Bool)
    data.silent = silent

    return nothing
end

# MOI.TimeLimitSec
MOI.get(data::MOIAttributeData, ::MOI.TimeLimitSec) = data.time_limit_sec

function MOI.set(
    data::MOIAttributeData,
    ::MOI.TimeLimitSec,
    time_limit_sec::Union{Float64,Nothing},
)
    @assert isnothing(time_limit_sec) || time_limit_sec >= 0.0

    data.time_limit_sec = time_limit_sec

    return nothing
end

# MOI.NumberOfThreads
MOI.get(data::MOIAttributeData, ::MOI.NumberOfThreads) = data.number_of_threads

function MOI.set(data::MOIAttributeData, ::MOI.NumberOfThreads, number_of_threads::Integer)
    @assert number_of_threads > 0

    data.number_of_threads = number_of_threads

    return nothing
end

# MOI.VariablePrimalStart
function MOI.get(data::MOIAttributeData, ::MOI.VariablePrimalStart, vi::VI)
    return get(data.variable_primal_start, vi, nothing)
end

function MOI.set(
    data::MOIAttributeData,
    ::MOI.VariablePrimalStart,
    vi::VI,
    ::Nothing,
)
    delete!(data.variable_primal_start, vi)

    return nothing
end

function MOI.set(
    data::MOIAttributeData{T},
    ::MOI.VariablePrimalStart,
    vi::VI,
    value::T,
) where {T}
    data.variable_primal_start[vi] = value

    return nothing
end

# VariablePrimalStart
function MOI.get(sampler::AbstractSampler{T}, attr::MOI.VariablePrimalStart, vi::VI) where {T}
    return MOI.get(sampler.attr_data.moiattrs, attr, vi)
end

function MOI.set(
    sampler::AbstractSampler{T},
    attr::MOI.VariablePrimalStart,
    vi::VI,
    value::Union{T,Nothing},
) where {T}
    MOI.set(sampler.attr_data.moiattrs, attr, vi, value)

    return nothing
end

MOI.supports(::AbstractSampler, ::MOI.VariablePrimalStart, ::Type{VI}) = true
MOI.supports(::AbstractSampler, ::MOI.VariablePrimalStart, ::MOI.VariableIndex) = true

# ~*~ :: Sampler Attributes :: ~*~ #
abstract type AbstractSamplerAttribute <: MOI.AbstractOptimizerAttribute end

mutable struct AttributeWrapper{A<:Union{AbstractSamplerAttribute,Nothing},T}
    value::T
    rawattr::Union{String,Nothing}
    optattr::A

    function AttributeWrapper{A,T}(
        default::T;
        rawattr::Union{String,Nothing} = nothing,
        optattr::A                     = nothing,
    ) where {A<:Union{AbstractSamplerAttribute,Nothing},T}
        @assert !(isnothing(rawattr) && isnothing(optattr))

        return new{A,T}(default, rawattr, optattr)
    end
end

struct AttributeData{T}
    rawattrs::Dict{String,AttributeWrapper}
    optattrs::Dict{AbstractSamplerAttribute,AttributeWrapper}
    moiattrs::MOIAttributeData{T}

    function AttributeData{T}(attrs::Vector) where {T}
        rawattrs = Dict{String,AttributeWrapper}()
        optattrs = Dict{AbstractSamplerAttribute,AttributeWrapper}()
        moiattrs = MOIAttributeData{T}()

        for attr::AttributeWrapper in attrs
            if !isnothing(attr.rawattr)
                rawattrs[attr.rawattr] = attr
            end

            if !isnothing(attr.optattr)
                optattrs[attr.optattr] = attr
            end
        end

        return new{T}(rawattrs, optattrs, moiattrs)
    end
end

# ~*~ :: Automatic Sampler Methods :: ~*~ #

# MOI_ATTRIBUTE
function MOI.get(sampler::AbstractSampler, attr::MOI_ATTRIBUTE)
    return MOI.get(sampler.attr_data.moiattrs, attr)
end

function MOI.set(sampler::AbstractSampler, attr::MOI_ATTRIBUTE, value)
    MOI.set(sampler.attr_data.moiattrs, attr, value)

    return nothing
end

MOI.supports(sampler::AbstractSampler, attr::MOI_ATTRIBUTE) = true

# AbstractSamplerAttribute
function MOI.get(sampler::AbstractSampler, attr::AbstractSamplerAttribute)
    if haskey(sampler.attr_data.optattrs, attr)
        return sampler.attr_data.optattrs[attr].value
    else
        error("Attribute '$attr' is not supported")
    end
end

function MOI.set(sampler::AbstractSampler, attr::AbstractSamplerAttribute, value)
    if haskey(sampler.attr_data.optattrs, attr)
        sampler.attr_data.optattrs[attr].value = value
    else
        error("Attribute '$attr' is not supported")
    end

    return nothing
end

function MOI.supports(sampler::AbstractSampler, attr::AbstractSamplerAttribute)
    return haskey(sampler.attr_data.optattrs, attr)
end

# RawOptimizerAttribute
function MOI.get(sampler::AbstractSampler, raw_attr::MOI.RawOptimizerAttribute)
    if haskey(sampler.attr_data.rawattrs, raw_attr.name)
        return sampler.attr_data.rawattrs[raw_attr.name].value
    else
        error("Attribute '$raw_attr' is not supported")
    end
end

function MOI.set(sampler::AbstractSampler, raw_attr::MOI.RawOptimizerAttribute, value)
    if haskey(sampler.attr_data.rawattrs, raw_attr.name)
        sampler.attr_data.rawattrs[raw_attr.name].value = value
    else
        error("Attribute '$raw_attr' is not supported")
    end

    return nothing
end

function MOI.supports(sampler::AbstractSampler, raw_attr::MOI.RawOptimizerAttribute)
    return haskey(sampler.attr_data.rawattrs, raw_attr.name)
end
