# Samplers

QUBODrivers includes three utility samplers. They are intentionally simple:
their main role is to exercise the interface, provide small-instance baselines,
and make examples runnable without external services.

| Sampler | Purpose | Main result behavior |
| :-- | :-- | :-- |
| [`ExactSampler.Optimizer`](@ref) | Exhaustive enumeration for small models | returns every state |
| [`RandomSampler.Optimizer`](@ref) | Random baseline and smoke tests | returns `num_reads` random states |
| [`IdentitySampler.Optimizer`](@ref) | Warm-start and conversion checks | returns the provided start state |

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

## External Sampler Packages

Several JuliaQUBO packages implement the same sampler interface for external
libraries, heuristics, or services. Their source can be useful when building a
new wrapper.

| Project                                                                                   | Source Code                                                                                                                       |
| :---------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------- |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | [DWave](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/DWave.jl)                                                             |
| [DWaveNeal.jl](https://github.com/JuliaQUBO/DWaveNeal.jl)                                 | [DWaveNeal](https://github.com/JuliaQUBO/DWaveNeal.jl/blob/main/src/DWaveNeal.jl)                                                 |
| [IsingSolvers.jl](https://github.com/JuliaQUBO/IsingSolvers.jl)                           | [GreedyDescent](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/greedy_descent.jl)                             |
|                                                                                           | [ILP](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/ilp.jl)                                                  |
|                                                                                           | [MCMCRandom](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/mcmc_random.jl)                                   |
| [QuantumAnnealingInterface.jl](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl) | [QuantumAnnealingInterface](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl/blob/main/src/QuantumAnnealingInterface.jl) |
| [CIMOptimizer.jl](https://github.com/pedromxavier/CIMOptimizer.jl)                        | [CIMOptimizer](https://github.com/pedromxavier/CIMOptimizer.jl/blob/main/src/CIMOptimizer.jl)                                     |
