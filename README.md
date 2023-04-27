# QUBODrivers.jl 🔴🟢🟣🔵

<div align="center">
    <a href="/docs/src/assets/">
        <img src="/docs/src/assets/logo.svg" width=400px alt="QUBODrivers.jl" />
    </a>
    <br>
    <br>
    <a href="https://codecov.io/gh/psrenergy/QUBODrivers.jl">
        <img src="https://codecov.io/gh/psrenergy/QUBODrivers.jl/branch/master/graph/badge.svg?token=729WFU0752"/>
    </a>
    <a href="https://github.com/psrenergy/QUBODrivers.jl/actions/workflows/ci.yml">
        <img src="https://github.com/psrenergy/QUBODrivers.jl/actions/workflows/ci.yml/badge.svg?branch=master" alt="CI" />
    </a>
    <a href="https://www.youtube.com/watch?v=OTmzlTbqdNo">
        <img src="https://img.shields.io/badge/JuliaCon-2022-9558b2" alt="JuliaCon 2022">
    </a>
    <a href="https://psrenergy.github.io/QUBODrivers.jl/dev">
        <img src="https://img.shields.io/badge/docs-dev-blue.svg" alt="Docs">
    </a>
    <a href="https://zenodo.org/badge/latestdoi/623618138">
        <img src="https://zenodo.org/badge/623618138.svg" alt="DOI">
    </a>
</div>

## Introduction
This package aims to provide a common [MOI](https://github.com/jump-dev/MathOptInterface.jl)-compliant API for [QUBO](https://en.wikipedia.org/wiki/Quadratic_unconstrained_binary_optimization) Sampling and Annealing machines.
It also contains a few testing tools, including utility samplers for performance comparison and sanity checks, and some basic analysis features.

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

## Badge
If your project is using [QUBODrivers.jl](https://github.com/psrenergy/QUBODrivers.jl), consider adding the official badge to your project's README file:

[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/psrenergy/QUBODrivers.jl)

```md
[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/psrenergy/QUBODrivers.jl)
```

---

<div align="center">
    <h2>PSR Quantum Optimization Toolchain</h2>
    <a href="https://github.com/psrenergy/ToQUBO.jl">
        <img width="200px" src="https://raw.githubusercontent.com/psrenergy/ToQUBO.jl/master/docs/src/assets/logo.svg" alt="ToQUBO.jl" />
    </a>
    <a href="https://github.com/psrenergy/QUBODrivers.jl">
        <img width="200px" src="https://raw.githubusercontent.com/psrenergy/QUBODrivers.jl/master/docs/src/assets/logo.svg" alt="QUBODrivers.jl" />
    </a>
    <a href="https://github.com/psrenergy/QUBOTools.jl">
        <img width="200px" src="https://raw.githubusercontent.com/psrenergy/QUBOTools.jl/main/docs/src/assets/logo.svg" alt="QUBOTools.jl" />
    </a>
</div>
