@doc raw"""
    benchmark(sampler::AbstractSampler)

""" function benchmark end

function QUBODrivers.benchmark(sampler::AbstractSampler)
    
end

@doc raw"""
    benchmark_suite(sampler::AbstractSampler)

## Example

```
using QUBODrivers
using SuperSampler

SUITE = QUBODrivers.benchmark_suite(SuperSampler.Optimizer)
```
""" function benchmark_suite end

function QUBODrivers.benchmark_suite(sampler::AbstractSampler)
    suite = BenchmarkTools.BenchmarkGroup()

    return suite
end