# Samplers

## Utility Samplers

### Exact Sampler

```@docs
QUBODrivers.ExactSampler.Optimizer
```

### Random Sampler

```@docs
QUBODrivers.RandomSampler.Optimizer
```

### Identity Sampler

```@docs
QUBODrivers.IdentitySampler.Optimizer
```

## Showcase

Before explaining in detail how to use this package, it's good to list a few examples for the reader to grasp.
Below, there are links to the files containing the actual interface implementations.
These are mostly thin wrappers interfacing with common algorithms and heuristics written in Python, Julia or C/C++.

| Project                                                                                   | Source Code                                                                                                                       |
| :---------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------- |
| [DWave.jl](https://github.com/JuliaQUBO/DWave.jl)                                         | [DWave](https://github.com/JuliaQUBO/DWave.jl/blob/main/src/DWave.jl)                                                             |
| [DWaveNeal.jl](https://github.com/JuliaQUBO/DWaveNeal.jl)                                 | [DWaveNeal](https://github.com/JuliaQUBO/DWaveNeal.jl/blob/main/src/DWaveNeal.jl)                                                 |
| [IsingSolvers.jl](https://github.com/JuliaQUBO/IsingSolvers.jl)                           | [GreedyDescent](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/greedy_descent.jl)                             |
|                                                                                           | [ILP](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/ilp.jl)                                                  |
|                                                                                           | [MCMCRandom](https://github.com/JuliaQUBO/IsingSolvers.jl/blob/main/src/solvers/mcmc_random.jl)                                   |
| [QuantumAnnealingInterface.jl](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl) | [QuantumAnnealingInterface](https://github.com/JuliaQUBO/QuantumAnnealingInterface.jl/blob/main/src/QuantumAnnealingInterface.jl) |
| [CIMOptimizer.jl](https://github.com/pedromxavier/CIMOptimizer.jl) | [CIMOptimizer](https://github.com/pedromxavier/CIMOptimizer.jl/blob/main/src/CIMOptimizer.jl) |
