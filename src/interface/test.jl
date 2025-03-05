@doc raw"""
    test(optimizer::Type{S}; examples::Bool=false) where {S<:AbstractSampler}
    test(config!::Function, optimizer::Type{S}; examples::Bool=false) where {S<:AbstractSampler}
"""
function test end