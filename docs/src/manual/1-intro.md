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
`QUBODrivers.jl` employs [QUBOTools](https://github.com/psrenergy/QUBOTools.jl) on many tasks involving data management and querying.
It is worth taking a look at [QUBOTool's docs](https://psrenergy.github.io/QUBOTools.jl).

## Table of Contents

```@contents
Pages = ["2-solve.md", "3-samplers.md", "4-setup.md", "5-tests.md", "6-benchmarks.md"]
Depth = 2
```
