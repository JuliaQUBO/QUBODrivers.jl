# Samplers

QUBODrivers includes four utility samplers. They are intentionally simple:
their main role is to exercise the interface, provide small-instance baselines,
and make examples runnable without external services or fixed solver choices.

| Sampler | Purpose | Main result behavior |
| :-- | :-- | :-- |
| [`ExactSampler.Optimizer`](@ref) | Exhaustive enumeration for small models | returns every state |
| [`RandomSampler.Optimizer`](@ref) | Random baseline and smoke tests | returns `num_reads` random states |
| [`IdentitySampler.Optimizer`](@ref) | Warm-start and conversion checks | returns the provided start state |
| [`MIPSampler.Optimizer`](@ref) | Exact MIP-backed baseline using a user-supplied MOI optimizer | returns at most one best incumbent and preserves MIP objective bounds |

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
objective_bound(model)
```

When a time- or node-limited MIP solve stops early, `MIPSampler` preserves the
backend's `MOI.TerminationStatus()` and `MOI.ObjectiveBound()` (translated to the
caller's original objective sense, variable domain, scaling, constant offset, and
fixed-variable conditioning) separately from any incumbent:

- **Interrupted with an incumbent:** `result_count(model) == 1` and
  `primal_status(model) == MOI.FEASIBLE_POINT`. `objective_value(model)` returns
  the rounded binary state's re-evaluated QUBO objective. `objective_bound(model)`
  and `relative_gap(model)` return the backend-reported bound and relative gap
  when available, or throw `MOI.GetAttributeNotAllowed` if the backend did not
  report a finite value.
- **Interrupted without an incumbent:** `result_count(model) == 0` and
  `primal_status(model) == MOI.NO_SOLUTION`. `MIPSampler` returns an empty
  `SampleSet` (with zero emitted reads and the consumed solve time) rather than
  throwing, so callers can still inspect `termination_status(model)`,
  `solve_time(model)`, and `objective_bound(model)` (when the backend reported a
  finite bound). Querying `objective_value(model)` or `value.(x)` throws
  `MOI.ResultIndexBoundsError`, and querying `relative_gap(model)` throws
  `MOI.GetAttributeNotAllowed{MOI.RelativeGap}`.
- **Numerical or backend failures:** Unlike normal limit terminations, invalid
  numerical backend outputs (such as `NaN` or unrepresentable bounds, inconsistent
  `bound > incumbent`, or out-of-range binary primals) and backend solve errors
  throw an exception from `optimize!(model)`, clear any prior results
  (`result_count(model) == 0`, `primal_status(model) == MOI.NO_SOLUTION`), and
  set `termination_status(model)` to `MOI.NUMERICAL_ERROR` or `MOI.OTHER_ERROR`
  (or the backend's failure status).

```julia
using JuMP
using QUBODrivers
using QUBODrivers: QUBOTools
using GLPK

const MOI = JuMP.MOI

function solve_interrupted_qubo(stop_reason::Integer)
    model = Model(MIPSampler.Optimizer)
    set_silent(model)
    set_attribute(
        model,
        MIPSampler.MIPOptimizer(),
        () -> begin
            opt = GLPK.Optimizer()
            GLPK._set_callback(opt, cb_data -> begin
                if GLPK.glp_ios_reason(cb_data.tree) == stop_reason
                    GLPK.glp_ios_terminate(cb_data.tree)
                end
            end)
            return opt
        end,
    )

    @variable(model, x[1:3], Bin)
    @objective(
        model,
        Min,
        -1.25 * (x[1] + x[2] + x[3]) + 2.0 * (x[1] * x[2] + x[2] * x[3] + x[1] * x[3]),
    )

    try
        optimize!(model)
    catch err
        # Numerical validation or backend failure: prior results are cleared,
        # and `termination_status(model)` reflects `MOI.NUMERICAL_ERROR` or `MOI.OTHER_ERROR`.
        @warn "MIP solve failed" exception = err status = termination_status(model)
    end

    status = termination_status(model)
    bound = try
        objective_bound(model)
    catch err
        err isa MOI.GetAttributeNotAllowed ? nothing : rethrow()
    end
    raw_metadata = QUBOTools.metadata(QUBOTools.solution(unsafe_backend(model)))

    if result_count(model) > 0
        incumbent_val   = objective_value(model)
        incumbent_state = round.(Int, value.(x))
        gap = try
            relative_gap(model)
        catch err
            err isa MOI.GetAttributeNotAllowed ? nothing : rethrow()
        end
        return (;
            status,
            has_incumbent = true,
            bound,
            incumbent_val,
            incumbent_state,
            gap,
            solve_time = solve_time(model),
            bound_metadata = raw_metadata["bound"],
        )
    else
        # Primal-free limit termination (`primal_status(model) == MOI.NO_SOLUTION`) or failed solve:
        # `objective_value(model)` and `value.(x)` throw `MOI.ResultIndexBoundsError`, and
        # `relative_gap(model)` throws `MOI.GetAttributeNotAllowed`, while `bound` and timing remain available.
        return (;
            status,
            has_incumbent = false,
            bound,
            incumbent_val = nothing,
            incumbent_state = nothing,
            gap = nothing,
            solve_time = solve_time(model),
            bound_metadata = get(raw_metadata, "bound", nothing),
        )
    end
end

# 1. Interrupted at root branching before an integer incumbent is found (bound-only result):
bound_only = solve_interrupted_qubo(GLPK.GLP_IBRANCH)
# bound_only.status == MOI.INTERRUPTED, bound_only.has_incumbent == false, bound_only.bound == -1.875

# 2. Interrupted when the first integer incumbent is found (incumbent + bound result):
with_incumbent = solve_interrupted_qubo(GLPK.GLP_IBINGO)
# with_incumbent.status == MOI.INTERRUPTED, with_incumbent.has_incumbent == true,
# with_incumbent.incumbent_val == -1.25, with_incumbent.bound == -1.25
```

!!! note "Bound Scope and Numerical Provenance"
    Bounds and relative gaps exposed by `MIPSampler` are **backend-reported,
    tolerance-dependent** quantities for the supplied QUBO/Ising model (possibly
    conditioned on fixed variables), not independently verified exact-arithmetic
    certificates. A bound on a penalized QUBO relaxation is not automatically a
    bound on an original constrained formulation.

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
