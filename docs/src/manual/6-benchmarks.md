# Benchmarking

Benchmarking QUBO samplers is an important step for evaluating solver performance.
This section provides guidelines along with a practical example for comparing samplers using QUBODrivers.jl.

## Comparing Samplers

The built-in utility samplers (`ExactSampler`, `RandomSampler`) serve as useful baselines.
Since samplers return multiple results through MOI, you can collect objective values, solution vectors, and timing to compare across methods.

```julia
using JuMP
using QUBODrivers

Q = [
    -1.0  2.0  2.0
     2.0 -1.0  2.0
     2.0  2.0 -1.0
]

function benchmark_sampler(OptimizerType; kwargs...)
    model = Model(() -> OptimizerType(; kwargs...))

    @variable(model, x[1:3], Bin)
    @objective(model, Min, x' * Q * x)

    stats = @timed optimize!(model)

    results = [
        (value.(x; result=i), objective_value(model; result=i))
        for i in 1:result_count(model)
    ]

    best = minimum(r -> r[2], results)

    return (; time = stats.time, best, n_results = length(results))
end
```

```julia
# Exact enumeration (reference)
exact = benchmark_sampler(ExactSampler.Optimizer)

# Random sampling
random = benchmark_sampler(RandomSampler.Optimizer)
```

## Timing Information

Samplers store timing metadata in the sample set.
After solving, `MOI.get(model, MOI.SolveTimeSec())` returns the total solve time in seconds, which is useful for automated benchmarking scripts.

## Tips

- Always use `ExactSampler` on small instances to obtain the known optimum as a reference.
- For stochastic samplers, run multiple independent trials and report statistics (mean, standard deviation, best).
- Use [`BenchmarkTools.jl`](https://github.com/JuliaCI/BenchmarkTools.jl) for micro-benchmarks with `@benchmark` or `@btime`.
- Scale problem sizes gradually to understand how sampler performance degrades.
