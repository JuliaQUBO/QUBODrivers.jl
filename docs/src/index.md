# QUBODrivers.jl Documentation

## Introduction

QUBODrivers.jl provides a common
[MathOptInterface](https://github.com/jump-dev/MathOptInterface.jl)-compatible
API for [QUBO](https://en.wikipedia.org/wiki/Quadratic_unconstrained_binary_optimization)
samplers and annealing backends.

The package includes:

- utility samplers for exact enumeration, random sampling, and warm-start
  identity sampling;
- a macro for declaring sampler optimizers and user-facing attributes;
- MOI and QUBOTools plumbing for model conversion and result access;
- a reusable test suite for sampler implementations.

If you want to solve a model, start with [Solving QUBO](@ref). If you want to
implement a new sampler wrapper, start with [Sampler Setup](@ref) and
[Implementing a Sampler](@ref).

## Quick Start

### Installation

[QUBODrivers.jl](https://github.com/JuliaQUBO/QUBODrivers.jl) is registered in Julia's General Registry and is available for download using the standard package manager.

```julia-repl
julia> import Pkg

julia> Pkg.add("QUBODrivers")
```

### Example

```@example
using JuMP
using QUBODrivers

model = Model(ExactSampler.Optimizer)

Q = [
    -1.0  2.0  2.0
     2.0 -1.0  2.0
     2.0  2.0 -1.0
]

@variable(model, x[1:3], Bin)
@objective(model, Min, x' * Q * x)

optimize!(model)

for i = 1:result_count(model)
    xi = value.(x; result=i)
    yi = objective_value(model; result=i)

    println("f($xi) = $yi")
end
```

<!-- ## Citing QUBODrivers.jl
```tex
@software{QUBODrivers.jl:2023,
  author    = {Pedro Xavier and Pedro Ripper and Tiago Andrade and Joaquim Garcia and David Bernal Neira},
  title     = {QUBODrivers.jl},
  month     = {apr},
  year      = {2023},
  publisher = {Zenodo},
  version   = {v0.3.4},
  doi       = {10.5281/zenodo.13840948},
  url       = {https://doi.org/10.5281/zenodo.13840948}
}
``` -->
