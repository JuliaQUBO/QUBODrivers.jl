# Benchmarking

Benchmarking QUBO samplers is partly about runtime and partly about solution
quality. QUBODrivers exposes both through standard JuMP/MOI result queries, so a
simple benchmark can collect elapsed time, number of returned states, objective
values, objective-value frequencies, and the best state found.

## Benchmark a JuMP Model

Build the problem once, then pass its MOI backend to `QUBODrivers.benchmark`.
The benchmark helper copies that model into each sampler, applies any sampler
configuration, runs `MOI.optimize!`, and returns timing and sample-quality
metadata.

```@example benchmarking-jump
using JuMP
using QUBODrivers

model = Model()
@variable(model, x[1:4], Bin)
@objective(model, Min, -x[1] - 2x[2] - x[3] + 2x[1] * x[2] + x[3] * x[4])

result = QUBODrivers.benchmark(RandomSampler.Optimizer, backend(model)) do sampler
    MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 100)
    MOI.set(sampler, MOI.RawOptimizerAttribute("seed"), 1)
end

(result.variables, result.result_count, result.objective_summary.minimum)
```

For large models, use stochastic samplers such as `RandomSampler` as the cheap
baseline. `ExactSampler` is useful for small reference instances and smoke
tests, but its exhaustive enumeration grows exponentially.

## Comparing Samplers

The built-in utility samplers are useful baselines. `ExactSampler` gives a
complete reference on small instances, while `RandomSampler` provides a cheap
stochastic baseline.

```@example benchmarking
using QUBODrivers

source = MOI.Utilities.Model{Float64}()
x, _ = MOI.add_constrained_variables(source, fill(MOI.ZeroOne(), 3))

Q = [
    -1.0  2.0  2.0
     2.0 -1.0  2.0
     2.0  2.0 -1.0
]

MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
MOI.set(
    source,
    MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
    MOI.ScalarQuadraticFunction{Float64}(
        MOI.ScalarQuadraticTerm{Float64}[
            MOI.ScalarQuadraticTerm{Float64}(Q[i, j], x[i], x[j])
            for i = 1:3 for j = 1:3 if i != j
        ],
        MOI.ScalarAffineTerm{Float64}[
            MOI.ScalarAffineTerm{Float64}(Q[i, i], x[i])
            for i = 1:3
        ],
        0.0,
    ),
)

exact = QUBODrivers.benchmark(ExactSampler.Optimizer, source)

random = QUBODrivers.benchmark(RandomSampler.Optimizer, source) do sampler
    MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 100)
    MOI.set(sampler, MOI.RawOptimizerAttribute("seed"), 1)
end

(exact.best_objective, random.best_objective)
```

`QUBODrivers.benchmark` copies a user-provided MOI model into the sampler and
returns a named tuple with solver metadata, objective values, result count, best
state, best objective value, objective summary, MOI solve time, wall-clock time
around `MOI.optimize!`, and status fields. `result.objective_summary` contains
`minimum`, `maximum`, `mean`, and a `histogram` mapping each observed objective
value to its frequency. The optional `do` block receives the raw sampler
optimizer after model copy and before optimization. If no model is provided,
`QUBODrivers.benchmark` falls back to a small built-in QUBO instance as a smoke
benchmark.

## Timing Information

Samplers store timing metadata in the returned sample set. After solving,
`MOI.get(backend(model), MOI.SolveTimeSec())` returns the effective solve time
reported through MOI. This can differ from wall-clock timing around
`optimize!`, especially for wrappers that separate model conversion, backend
submission, queue time, and sample decoding.

## What to Report

For stochastic or hardware-backed samplers, report enough context for the result
to be reproducible:

- package and backend versions;
- problem size and density;
- objective sense and variable domain;
- sampler attributes, especially seeds, number of reads, time limits, and
  threads;
- best objective value, distribution of objective values, and success rate if a
  reference optimum is known;
- wall-clock time and solver-reported timing metadata.

## Tips

- Use `QUBODrivers.benchmark` as a quick interface smoke benchmark for a new
  sampler wrapper.
- Use `ExactSampler` on small instances to obtain a known optimum.
- Run multiple independent trials for stochastic samplers and report summary
  statistics.
- Keep model generation outside the timed region unless model construction is
  part of the benchmark.
- Use [`BenchmarkTools.jl`](https://github.com/JuliaCI/BenchmarkTools.jl) for
  micro-benchmarks with `@benchmark` or `@btime`.
- Scale problem sizes gradually to understand how sampler performance degrades.

```@docs
QUBODrivers.benchmark
```
