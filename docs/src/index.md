# QUBODrivers.jl Documentation

## Introduction

QUBODrivers.jl provides a common
[MathOptInterface](https://github.com/jump-dev/MathOptInterface.jl)-compatible
API for [QUBO](https://en.wikipedia.org/wiki/Quadratic_unconstrained_binary_optimization)
samplers and annealing backends.

The package includes:

- utility samplers for exact enumeration, random sampling, warm-start identity
  sampling, and MIP-backed baseline solving;
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

## Citing QUBODrivers.jl
<!-- citation-policy:start -->
For general use of `QUBODrivers.jl` and the broader `QUBO.jl` ecosystem, cite the
[published journal article](https://doi.org/10.1080/10556788.2026.2702926). The
earlier [arXiv preprint](https://arxiv.org/abs/2307.02577) remains available,
but the journal article is the version of record.

For a direct software citation, use the
[Zenodo concept DOI](https://doi.org/10.5281/zenodo.7811951). The concept DOI
is the evergreen identifier for `QUBODrivers.jl`, resolves to the latest archived
release, and is the DOI recorded in `CITATION.cff`. When reproducibility
requires an exact release, cite the matching Zenodo version DOI instead; the
archive for `v0.6.6` is
[10.5281/zenodo.23420133](https://doi.org/10.5281/zenodo.23420133).

The BibTeX entries below cite the ecosystem article and the `v0.6.6` software
archive. Replace the `@software` entry's `doi` and `url` with the concept DOI
when an evergreen software citation is preferred:

```bibtex
@article{xavier2026qubojl,
  author       = {Maciel Xavier, Pedro and Ripper, Pedro and Andrade, Tiago and Dias Garcia, Joaquim and Maculan, Nelson and Bernal Neira, David E.},
  title        = {{QUBO.jl: a Julia ecosystem for quadratic unconstrained binary optimization}},
  journal      = {Optimization Methods and Software},
  year         = {2026},
  pages        = {1--24},
  doi          = {10.1080/10556788.2026.2702926},
  url          = {https://doi.org/10.1080/10556788.2026.2702926}
}

@software{qubodrivers:2026,
  author       = {Maciel Xavier, Pedro and Ripper, Pedro and Andrade, Tiago and Dias Garcia, Joaquim and Bernal Neira, David E.},
  title        = {{QUBODrivers.jl}},
  year         = {2026},
  publisher    = {Zenodo},
  version      = {v0.6.6},
  doi          = {10.5281/zenodo.23420133},
  url          = {https://doi.org/10.5281/zenodo.23420133},
  note         = {Evergreen concept DOI: 10.5281/zenodo.7811951}
}
```

Machine-readable metadata is in
[`CITATION.cff`](https://github.com/JuliaQUBO/QUBODrivers.jl/blob/main/CITATION.cff),
with BibTeX in
[`CITATION.bib`](https://github.com/JuliaQUBO/QUBODrivers.jl/blob/main/CITATION.bib).
<!-- citation-policy:end -->
