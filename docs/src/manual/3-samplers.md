# Samplers

QUBODrivers includes four utility samplers. They are intentionally simple:
their main role is to exercise the interface, provide small-instance baselines,
and make examples runnable without external services or fixed solver choices.

| Sampler | Purpose | Main result behavior |
| :-- | :-- | :-- |
| [`ExactSampler.Optimizer`](@ref) | Exhaustive enumeration for small models | returns every state |
| [`RandomSampler.Optimizer`](@ref) | Random baseline and smoke tests | returns `num_reads` random states |
| [`IdentitySampler.Optimizer`](@ref) | Warm-start and conversion checks | returns the provided start state |
| [`MIPSampler.Optimizer`](@ref) | Exact MIP-backed baseline using a user-supplied MOI optimizer | returns one best incumbent |

## Exact Sampler

Use `ExactSampler` to validate small problem formulations or compare another
sampler against a known complete set of states. The cost grows exponentially
with the number of variables.

```@example exact-sampler
using JuMP
using QUBODrivers

model = Model(ExactSampler.Optimizer)

@variable(model, x[1:2], Bin)
@objective(model, Min, -x[1] - 2x[2] + 3x[1] * x[2])

optimize!(model)

result_count(model)
```

```@docs
QUBODrivers.ExactSampler.Optimizer
```

## Random Sampler

Use `RandomSampler` as a cheap stochastic baseline. Set `"num_reads"` to control
how many states are sampled and `"seed"` for reproducible examples.

```@example random-sampler
using JuMP
using QUBODrivers

model = Model(RandomSampler.Optimizer)
set_optimizer_attribute(model, "num_reads", 4)
set_optimizer_attribute(model, "seed", 1)

@variable(model, x[1:3], Bin)
@objective(model, Min, x[1] + x[2] - x[3])

optimize!(model)

result_count(model)
```

```@docs
QUBODrivers.RandomSampler.Optimizer
```

## Identity Sampler

Use `IdentitySampler` when the requested result is the warm-start vector itself.
It is useful in tests for objective evaluation, fixed variable handling, and
model conversion.

```@example identity-sampler
using QUBODrivers

MOI = QUBODrivers.MOI

model = MOI.instantiate(IdentitySampler.Optimizer; with_bridge_type = Float64)
x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

for (xi, start) in zip(x, [1.0, 0.0, 1.0])
    MOI.set(model, MOI.VariablePrimalStart(), xi, start)
end

objective = MOI.ScalarAffineFunction{Float64}(
    MOI.ScalarAffineTerm{Float64}[
        MOI.ScalarAffineTerm{Float64}(1.0, x[1]),
        MOI.ScalarAffineTerm{Float64}(2.0, x[2]),
        MOI.ScalarAffineTerm{Float64}(3.0, x[3]),
    ],
    0.0,
)

MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
MOI.set(model, MOI.ObjectiveFunction{typeof(objective)}(), objective)

MOI.optimize!(model)

(
    round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)),
    MOI.get(model, MOI.ObjectiveValue(1)),
)
```

```@docs
QUBODrivers.IdentitySampler.Optimizer
```

## MIP Sampler

Use `MIPSampler` as an exact correctness baseline for small and medium QUBO
instances when you want to choose the MIP backend yourself. The sampler is
implemented directly against MathOptInterface and does not depend on JuMP or on
any concrete MIP solver package.

```julia
using JuMP
using QUBODrivers
using GLPK

model = Model(MIPSampler.Optimizer)
set_attribute(model, MIPSampler.MIPOptimizer(), GLPK.Optimizer)

@variable(model, x[1:3], Bin)
@objective(model, Min, x[1] + x[2] - 2x[1] * x[3])

optimize!(model)

value.(x)
objective_value(model)
```

Internally, `MIPSampler` linearizes binary products with auxiliary variables
and the standard Fortet/McCormick inequalities. The reformulation is a baseline
route, not a replacement for specialized large-scale QUBO heuristics. For a
broader discussion of efficient binary polynomial reformulations, see Elloumi,
Sourour, and Verchere, "Efficient linear reformulations for binary polynomial
optimization problems", Computers & Operations Research 155 (2023), 106240.

```@docs
QUBODrivers.MIPSampler.Optimizer
QUBODrivers.MIPSampler.MIPOptimizer
```

## External Sampler Packages

Several JuliaQUBO packages implement the same sampler interface for external
libraries, heuristics, or services. Their source can be useful when building a
new wrapper.

This table is the reviewed source of truth for public external sampler
packages. When a new JuliaQUBO or SECQUOIA driver package is ready for users,
open a QUBODrivers documentation PR that adds its package URL, solver type, and
source file path.

| Project                                                                                   | Solver                                | Source Code                                                                                                                                |
| :---------------------------------------------------------------------------------------- | :------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------- |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | `DWave.Optimizer`                     | [`src/sampler.jl`](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/sampler.jl)                                                         |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | `DWave.Neal.Optimizer`                | [`src/neal/sampler.jl`](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/neal/sampler.jl)                                               |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | `DWave.Tabu.Optimizer`                | [`src/tabu/sampler.jl`](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/tabu/sampler.jl)                                               |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | `DWave.Greedy.Optimizer`              | [`src/greedy/sampler.jl`](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/greedy/sampler.jl)                                           |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | `DWave.Random.Optimizer`              | [`src/random/sampler.jl`](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/random/sampler.jl)                                           |
| [QiskitOpt.jl](https://github.com/JuliaQUBO/QiskitOpt.jl)                                 | `QiskitOpt.QAOA.Optimizer`            | [`src/QAOA.jl`](https://github.com/JuliaQUBO/QiskitOpt.jl/blob/main/src/QAOA.jl)                                                           |
| [QiskitOpt.jl](https://github.com/JuliaQUBO/QiskitOpt.jl)                                 | `QiskitOpt.VQE.Optimizer`             | [`src/VQE.jl`](https://github.com/JuliaQUBO/QiskitOpt.jl/blob/main/src/VQE.jl)                                                             |
| [PySA.jl](https://github.com/JuliaQUBO/PySA.jl)                                           | `PySA.Optimizer`                      | [`src/PySA.jl`](https://github.com/JuliaQUBO/PySA.jl/blob/main/src/PySA.jl)                                                                |
| [MQLib.jl](https://github.com/JuliaQUBO/MQLib.jl)                                         | `MQLib.Optimizer`                     | [`src/MQLib.jl`](https://github.com/JuliaQUBO/MQLib.jl/blob/main/src/MQLib.jl)                                                             |
| [QUBODecomposition.jl](https://github.com/JuliaQUBO/QUBODecomposition.jl)                 | `QUBODecomposition.Optimizer`         | [`src/optimizer.jl`](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/src/optimizer.jl)                                         |
| [CIMOptimizer.jl](https://github.com/JuliaQUBO/CIMOptimizer.jl)                           | `CIMOptimizer.Optimizer`              | [`src/CIMOptimizer.jl`](https://github.com/JuliaQUBO/CIMOptimizer.jl/blob/main/src/CIMOptimizer.jl)                                        |
| [QuantumAnnealingInterface.jl](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl) | `QuantumAnnealingInterface.Optimizer` | [`src/QuantumAnnealingInterface.jl`](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl/blob/main/src/QuantumAnnealingInterface.jl) |

### QUBODecomposition

QUBODecomposition is a standalone composite optimizer configured with a
user-supplied child optimizer factory and an explicit free logical-variable
budget, `max_variables`, including isolated variables. It dispatches fitting
models whole, solves fitting disconnected components, and uses conditioned
serial neighborhood sweeps for oversized connected components under the default
`:components_then_sweeps` strategy. Sweeps return heuristic incumbents; exact
child solves do not certify a coupled global optimum. Strict `:whole_model` and
`:components` strategies reject oversized nonconstant inputs or components.

As of October 8, 2026, the package is under development, with no published release
or General registration verified. Use its
[canonical development manual](https://juliaqubo.github.io/QUBODecomposition.jl/dev/)
for source-based installation,
[configuration](https://juliaqubo.github.io/QUBODecomposition.jl/dev/configuration/),
algorithms and released ToQUBO 0.7.1 integration. See also
[Public composition pattern](@ref), [Composite accounting](@ref), and
[Composite conformance evidence](@ref). QUBODrivers does not depend on this
external package.
