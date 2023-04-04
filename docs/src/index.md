# QUBODrivers.jl Documentation

## Introduction
This package aims to provide a common [MOI](https://github.com/jump-dev/MathOptInterface.jl)-compliant API for [QUBO](https://en.wikipedia.org/wiki/Quadratic_unconstrained_binary_optimization) Sampling & Annealing machines.
It also contains a few utility samplers and testing tools for performance comparison, sanity checks and basic analysis features.

## Quick Start

### Installation
[QUBODrivers.jl](https://github.com/psrenergy/QUBODrivers.jl) is registered in Julia's General Registry and is available for download using the standard package manager.

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
    ri = reads(model; result=i)

    println("f($xi) = $yi ($ri)")
end
```

<!-- ## Citing QUBODrivers.jl
```tex
@software{QUBODrivers.jl:2023,
  author = {Pedro Xavier and Pedro Ripper and Tiago Andrade and Joaquim Garcia and David Bernal},
  title        = {QUBODrivers.jl},
  month        = {apr},
  year         = {2023},
  publisher    = {Zenodo},
  version      = {v0.1.0},
  doi          = {10.5281/zenodo.6390515},
  url          = {https://doi.org/10.5281/zenodo.6390515}
}
``` -->