# Introduction

## QUBO

An optimization problem is in its QUBO form if it is written as

```math
\begin{array}{rl}
           \min & \alpha \left[ \mathbf{x}'\mathbf{Q}\,\mathbf{x} + \mathbf{\ell}'\mathbf{x} + \beta \right] \\
    \text{s.t.} & \mathbf{x} \in S \cong \mathbb{B}^{n}
\end{array}
```

with linear terms ``\mathbf{\ell} \in \mathbb{R}^{n}`` and quadratic ``\mathbf{Q} \in \mathbb{R}^{n \times n}``. ``\alpha, \beta \in \mathbb{R}`` are, respectively, the scaling and offset factors.

The MOI-JuMP optimizers defined using the `QUBODrivers.AbstractSampler{T} <: MOI.AbstractOptimizer` interface only support models given in the QUBO form.
`QUBODrivers.jl` employs [QUBOTools](https://github.com/JuliaQUBO/QUBOTools.jl) on many tasks involving data management and querying.
It is worth taking a look at the [QUBOTools docs](https://JuliaQUBO.github.io/QUBOTools.jl).

## Package Layout

The package has three main layers:

- user-facing JuMP/MOI optimizers, including the built-in utility samplers;
- sampler-author tools, centered on [`QUBODrivers.@setup`](@ref) and
  [`QUBODrivers.sample`](@ref);
- testing and benchmarking helpers that exercise the sampler interface.

All solver-specific wrappers should preserve the same public contract: accept a
QUBO or Ising model through MOI, call their backend in `QUBODrivers.sample`, and
return a QUBOTools sample set that JuMP users can query through standard result
APIs.

## Table of Contents

```@contents
Pages = ["2-solve.md", "3-samplers.md", "4-setup.md", "7-integration.md", "5-tests.md", "6-benchmarks.md", "8-api.md"]
Depth = 2
```
