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

| Project                                                                                   | Source Code                                                                                                                       |
| :---------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------- |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | [DWave](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/DWave.jl)                                                             |
| [DWaveNeal.jl](https://github.com/JuliaQUBO/DWaveNeal.jl)                                 | [DWaveNeal](https://github.com/JuliaQUBO/DWaveNeal.jl/blob/main/src/DWaveNeal.jl)                                                 |
| [QuantumAnnealingInterface.jl](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl) | [QuantumAnnealingInterface](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl/blob/main/src/QuantumAnnealingInterface.jl) |
| [CIMOptimizer.jl](https://github.com/pedromxavier/CIMOptimizer.jl)                        | [CIMOptimizer](https://github.com/pedromxavier/CIMOptimizer.jl/blob/main/src/CIMOptimizer.jl)                                     |
