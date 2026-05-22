# Benchmarking

Benchmarking QUBO samplers is partly about runtime and partly about solution
quality. QUBODrivers exposes both through standard JuMP/MOI result queries, so a
simple benchmark can collect elapsed time, number of returned states, objective
values, and the best state found.

## Comparing Samplers

The built-in utility samplers are useful baselines. `ExactSampler` gives a
complete reference on small instances, while `RandomSampler` provides a cheap
stochastic baseline.

```@example benchmarking
using JuMP
using QUBODrivers

Q = [
    -1.0  2.0  2.0
     2.0 -1.0  2.0
     2.0  2.0 -1.0
]

function benchmark_sampler(OptimizerType; attributes = Pair{String,Any}[])
    model = Model(OptimizerType)

    for (name, value) in attributes
        set_optimizer_attribute(model, name, value)
    end

    @variable(model, x[1:3], Bin)
    @objective(model, Min, x' * Q * x)

    solve = @timed optimize!(model)

    results = [
        (value.(x; result=i), objective_value(model; result=i))
        for i in 1:result_count(model)
    ]

    return (;
        time = solve.time,
        best = minimum(last, results),
        n_results = length(results),
    )
end
```

```@example benchmarking
exact = benchmark_sampler(ExactSampler.Optimizer)

random = benchmark_sampler(
    RandomSampler.Optimizer;
    attributes = ["num_reads" => 100, "seed" => 1],
)

(exact.best, random.best)
```

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

- Use `ExactSampler` on small instances to obtain a known optimum.
- Run multiple independent trials for stochastic samplers and report summary
  statistics.
- Keep model generation outside the timed region unless model construction is
  part of the benchmark.
- Use [`BenchmarkTools.jl`](https://github.com/JuliaCI/BenchmarkTools.jl) for
  micro-benchmarks with `@benchmark` or `@btime`.
- Scale problem sizes gradually to understand how sampler performance degrades.
