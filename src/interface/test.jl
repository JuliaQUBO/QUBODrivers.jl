@doc raw"""
    test(optimizer::Type{S}; examples::Bool=true, kwargs...) where {S<:AbstractSampler}
    test(config!::Function, optimizer::Type{S}; examples::Bool=true, kwargs...) where {S<:AbstractSampler}

Run QUBODrivers' interface and example test suite for a sampler implementation.

These methods are implemented by the `QUBODrivers_Test_Ext` package extension and
become available when `Test` is loaded in the active environment. The core
package does not depend on `Test` directly.

Benchmark conformance checks are enabled by default. Pass
`benchmark_conformance=false` to disable all benchmark conformance checks, or
disable individual groups with `metadata_conformance=false`,
`timing_sanity=false`, `determinism=false`, `reads_semantics=false`,
`time_limit_acceptance=false`, or `termination_status=false`. The default
`determinism=:auto` runs seed determinism only for samplers whose
[`supports_seed`](@ref) trait is true.
"""
function test end
