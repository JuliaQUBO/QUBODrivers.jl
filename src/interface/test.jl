@doc raw"""
    test(optimizer::Type{S}; examples::Bool=true) where {S<:AbstractSampler}
    test(config!::Function, optimizer::Type{S}; examples::Bool=true) where {S<:AbstractSampler}

Run QUBODrivers' interface and example test suite for a sampler implementation.

These methods are implemented by the `QUBODrivers_Test_Ext` package extension and
become available when `Test` is loaded in the active environment. The core
package does not depend on `Test` directly.
"""
function test end
