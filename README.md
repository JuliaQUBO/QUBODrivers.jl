# QUBODrivers.jl 🔴🟢🟣🔵

<div align="center">
    <a href="/docs/src/assets/">
        <img src="/docs/src/assets/logo.svg" width=400px alt="QUBODrivers.jl" />
    </a>
    <br>
    <br>
    <a href="https://arxiv.org/abs/2307.02577">
        <img src="https://img.shields.io/badge/arXiv-2307.02577-b31b1b.svg" alt="arXiv"/>
    </a>
    <a href="https://doi.org/10.1080/10556788.2026.2702926">
        <img src="https://img.shields.io/badge/DOI-10.1080%2F10556788.2026.2702926-blue.svg" alt="Journal article DOI"/>
    </a>
    <a href="https://codecov.io/gh/JuliaQUBO/QUBODrivers.jl">
        <img src="https://codecov.io/gh/JuliaQUBO/QUBODrivers.jl/branch/main/graph/badge.svg?token=729WFU0752"/>
    </a>
    <a href="https://github.com/JuliaQUBO/QUBODrivers.jl/actions/workflows/ci.yml">
        <img src="https://github.com/JuliaQUBO/QUBODrivers.jl/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" />
    </a>
    <a href="https://www.youtube.com/watch?v=OTmzlTbqdNo">
        <img src="https://img.shields.io/badge/JuliaCon-2022-9558b2" alt="JuliaCon 2022">
    </a>
    <a href="https://JuliaQUBO.github.io/QUBODrivers.jl/dev">
        <img src="https://img.shields.io/badge/docs-dev-blue.svg" alt="Docs">
    </a>
    <a href="https://doi.org/10.5281/zenodo.7811951">
        <img src="https://zenodo.org/badge/DOI/10.5281/zenodo.7811951.svg" alt="QUBODrivers.jl Zenodo DOI">
    </a>
</div>

## Introduction
This package aims to provide a common [MOI](https://github.com/jump-dev/MathOptInterface.jl)-compliant API for [QUBO](https://en.wikipedia.org/wiki/Quadratic_unconstrained_binary_optimization) sampling devices.
It also contains a few additional tools, including utility samplers and a simple test suite.

### QUBO
Problems assigned to solvers defined within QUBODrivers.jl's interface are given by

$$\begin{array}{rl}
\text{QUBO}:~ \displaystyle \min_{\mathbf{x}} & \displaystyle \alpha \left[{ \mathbf{x}' Q \mathbf{x} + \ell' \mathbf{x} + \beta }\right] \\
\text{s.t.} & \displaystyle \mathbf{x} \in S \cong \mathbb{B}^{n}
\end{array}$$

where $Q \in \mathbb{R}^{n \times n}$ is a strictly upper triangular matrix and $\mathbf{\ell} \in \mathbb{R}^{n}$.

## Quick Start

### Installation
```julia
julia> import Pkg

julia> Pkg.add("QUBODrivers")
``` 

### Example
```julia
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

## Build your own driver

Sampler authors should start with the
[Implementing a Sampler](https://JuliaQUBO.github.io/QUBODrivers.jl/dev/manual/7-integration/)
tutorial for the `@setup` and `sample` interface, packaging checklist, and
reference implementations. Use the
[Test Suite](https://JuliaQUBO.github.io/QUBODrivers.jl/dev/manual/5-tests/)
page to wire `QUBODrivers.test` into your package tests.

## List of [QUBODrivers.jl](https://github.com/JuliaQUBO/QUBODrivers.jl)-powered packages

| Package                                                           |  Solvers                                         |
| :---------------------------------------------------------------- | :----------------------------------------------- |
| [`QUBODrivers.jl`](https://github.com/JuliaQUBO/QUBODrivers.jl)   | `ExactSampler` `RandomSampler` `IdentitySampler` `MIPSampler` |
| [`QiskitOpt.jl`](https://github.com/JuliaQUBO/QiskitOpt.jl)       | `QiskitOpt.QAOA` `QiskitOpt.VQE`                 |
| [`DWave.jl`](https://github.com/JuliaQUBO/DWave.jl)               | `DWave` `DWave.Neal`                             |
| [`PySA.jl`](https://github.com/JuliaQUBO/PySA.jl)                 | `PySA`                                           |
| [`CIMOptimizer.jl`](https://github.com/JuliaQUBO/CIMOptimizer.jl) | `CIMOptimizer`                                   |
| [`MQLib.jl`](https://github.com/JuliaQUBO/MQLib.jl)               | `MQLib`                                          |

## Badge
If your project is using [QUBODrivers.jl](https://github.com/JuliaQUBO/QUBODrivers.jl), consider adding the official badge to your project's README file:

[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/JuliaQUBO/QUBODrivers.jl)

```md
[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/JuliaQUBO/QUBODrivers.jl)
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
archive for `v0.6.8` is
[10.5281/zenodo.23648751](https://doi.org/10.5281/zenodo.23648751).

The BibTeX entries below cite the ecosystem article and the `v0.6.8` software
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
  version      = {v0.6.8},
  doi          = {10.5281/zenodo.23648751},
  url          = {https://doi.org/10.5281/zenodo.23648751},
  note         = {Evergreen concept DOI: 10.5281/zenodo.7811951}
}
```

Machine-readable metadata is in
[`CITATION.cff`](https://github.com/JuliaQUBO/QUBODrivers.jl/blob/main/CITATION.cff),
with BibTeX in
[`CITATION.bib`](https://github.com/JuliaQUBO/QUBODrivers.jl/blob/main/CITATION.bib).
<!-- citation-policy:end -->

---

<div align="center">
    <a href="https://github.com/JuliaQUBO/QUBO.jl">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/JuliaQUBO/QUBO.jl/refs/heads/main/docs/src/assets/logo-collaboration-dark.png">
      <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/JuliaQUBO/QUBO.jl/refs/heads/main/docs/src/assets/logo-collaboration-light.png">
      <img alt="QUBO.jl Collaboration" src="https://raw.githubusercontent.com/JuliaQUBO/QUBO.jl/refs/heads/main/docs/src/assets/logo-collaboration-light.png">
    </picture> 
    </a>
</div>
