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

## What the Suite Expects

A sampler should:

- be instantiable as an `MOI.AbstractOptimizer`;
- support binary and spin variable domains through MOI;
- accept linear, quadratic, and single-variable objectives;
- handle fixed variables consistently;
- return at least one result for solvable test models;
- expose result count, objective values, variable primals, solve time, and
  status through standard MOI attributes.

```@docs
QUBODrivers.test
```
