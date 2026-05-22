# API Reference

This page collects the public QUBODrivers API used by solver users and sampler
authors. QUBOTools provides the lower-level model and sample containers; this
package documents the MOI-facing sampler layer built on top of them.

## Package

```@docs
QUBODrivers
```

## Sampler Interface

```@docs; canonical=false
QUBODrivers.AbstractSampler
QUBODrivers.sample
QUBODrivers.set_model!
```

## Setup and Attributes

```@docs; canonical=false
QUBODrivers.@setup
QUBODrivers.SamplerAttribute
QUBODrivers.RawSamplerAttribute
QUBODrivers.@raw_attr_str
QUBODrivers.get_raw_attr
QUBODrivers.set_raw_attr!
QUBODrivers.default_raw_attr
```

## Built-In Samplers

```@docs; canonical=false
QUBODrivers.ExactSampler.Optimizer
QUBODrivers.RandomSampler.Optimizer
QUBODrivers.IdentitySampler.Optimizer
```

## Test and Benchmark Helpers

```@docs; canonical=false
QUBODrivers.test
QUBODrivers.benchmark
```

## Re-Exported Types

QUBODrivers re-exports a few commonly used QUBOTools and MOI names:

- `QUBODrivers.MOI` aliases MathOptInterface;
- `QUBODrivers.Sample` and `QUBODrivers.SampleSet` are QUBOTools sample
  containers returned by [`QUBODrivers.sample`](@ref);
- `QUBODrivers.Spin`, `QUBODrivers.↑`, and `QUBODrivers.↓` are the spin domain
  set and values used by QUBOTools' MOI extension.
