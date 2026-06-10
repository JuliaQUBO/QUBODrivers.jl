# Test Suite

QUBODrivers includes a reusable test suite for sampler authors. It checks the
MOI interface, model conversion, result queries, fixed variables, and example
QUBO/Ising problems.

`QUBODrivers.test` is the public entry point. Its methods are provided by the
`QUBODrivers_Test_Ext` package extension, which Julia loads automatically when
both `QUBODrivers` and `Test` are present in the active environment. This keeps
`Test` out of QUBODrivers' hard dependencies while still exposing a stable
testing API.

The extension module names themselves, such as `QUBODrivers_Test_Ext` and
`MOI_PythonCall_Ext`, are internal implementation details. Users should call the
public APIs they enable, like `QUBODrivers.test`, instead of importing those
extension modules directly.

## Basic Usage

Add `Test` to the active test environment, then call `QUBODrivers.test` inside a
regular `@testset`.

```julia
using Test
using QUBODrivers

@testset "My sampler" begin
    QUBODrivers.test(MySampler.Optimizer)
end
```

If your sampler needs deterministic configuration, pass a setup function. The
function receives each optimizer instance before it is tested.

```julia
QUBODrivers.test(MySampler.Optimizer) do model
    MOI.set(model, MOI.RawOptimizerAttribute("seed"), 1)
    MOI.set(model, MOI.RawOptimizerAttribute("num_reads"), 100)
end
```

For slow backends, disable the example problem set and run only the interface
checks:

```julia
QUBODrivers.test(MySampler.Optimizer; examples = false)
```

Benchmark conformance checks are also enabled by default. They exercise a tiny
three-variable model and verify that benchmark-facing metadata, timing, reads,
seed, time-limit, and termination-status behavior matches QUBODrivers' public
schema and traits.

Disable the full conformance group for drivers that are not benchmark-ready yet:

```julia
QUBODrivers.test(MySampler.Optimizer; benchmark_conformance = false)
```

You can also disable individual groups:

```julia
QUBODrivers.test(
    MySampler.Optimizer;
    metadata_conformance = false,
    timing_sanity = false,
    determinism = false,
    reads_semantics = false,
    time_limit_acceptance = false,
    termination_status = false,
)
```

## What the Suite Expects

A sampler should:

- be instantiable as an `MOI.AbstractOptimizer`;
- support binary and spin variable domains through MOI;
- accept linear, quadratic, and single-variable objectives;
- handle fixed variables consistently;
- return at least one result for solvable test models;
- expose result count, objective values, variable primals, solve time, and
  status through standard MOI attributes.
- return benchmark-ready metadata accepted by
  `QUBODrivers.validate_metadata`;
- stamp positive `metadata["time"]["total"]` and
  `metadata["time"]["effective"]`, with effective time no larger than total
  time;
- accept `QUBODrivers.FinalNumberOfReads()` and either honor it for the final
  emitted `SampleSet` length or report `honors_final_reads(optimizer) == false`;
- accept `MOI.TimeLimitSec()` without error, and keep total time within a
  generous smoke-test slack if `enforces_time_limit(optimizer)` is true;
- return a termination status in `OPTIMAL`, `LOCALLY_SOLVED`, `TIME_LIMIT`,
  `ITERATION_LIMIT`, or `OTHER_LIMIT`;
- produce identical sample states and values for repeated same-seed runs when
  `supports_seed(optimizer)` is true.

The benchmark conformance assertions are intentionally limited to the metadata
schema documented on the [Metadata Schema](@ref) page and the public capability
traits, including [`QUBODrivers.validate_metadata`](@ref),
[`QUBODrivers.supports_seed`](@ref),
[`QUBODrivers.honors_final_reads`](@ref), and
[`QUBODrivers.enforces_time_limit`](@ref).

```@docs
QUBODrivers.test
```
