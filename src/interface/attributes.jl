@doc raw"""
    SamplerAttribute
"""
abstract type SamplerAttribute <: MOI.AbstractOptimizerAttribute end

@doc raw"""
    RawSamplerAttribute{key}
"""
struct RawSamplerAttribute{key} <: SamplerAttribute
    RawSamplerAttribute{key}() where {key} = new{key}()
end

RawSamplerAttribute(key::String) = RawSamplerAttribute{Symbol(key)}()

@doc raw"""
    @raw_attr_str
"""
macro raw_attr_str(key::String)
    return :(RawSamplerAttribute{$(esc(QuoteNode(Symbol(key))))})
end

@doc raw"""
    default_raw_attr
"""
function default_raw_attr end

@doc raw"""
    get_raw_attr
"""
function get_raw_attr end

@doc raw"""
    set_raw_attr!
"""
function set_raw_attr! end
