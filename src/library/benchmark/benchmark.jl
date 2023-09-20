@doc raw"""
    benchmark_suite(::Type{S}) where {T,S<:AbstractSampler{T}}

## Example

```
using QUBODrivers
using SuperSampler
using BenchmarkTools

SUITE = QUBODrivers.benchmark_suite(SuperSampler.Optimizer)

results = BenchmarkTools.run(SUITE)
```
"""
function benchmark_suite end

function QUBODrivers.benchmark_suite(::Type{S}) where {T,S<:AbstractSampler{T}}
    suite = BenchmarkTools.BenchmarkGroup()

    error("This feature is not implemented yet.")

    return suite
end

@doc raw"""
    benchmark(::Type{S}) where {T,S<:AbstractSampler{T}}

"""
function benchmark end

function QUBODrivers.benchmark(::Type{S}) where {T,S<:AbstractSampler{T}}
    suite = QUBODrivers.benchmark_suite(S)

    results = BenchmarkTools.run(suite)

    return results
end
