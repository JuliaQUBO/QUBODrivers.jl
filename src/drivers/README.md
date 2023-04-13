# QUBODrivers.jl - QUBO Samplers

To setup your own QUBO sampling system, one must implement some `MathOptInterface` and `QUBODrivers` API requirements.

## `MathOptInterface`

| Method              | Return Type | `get` | `set` | `supports` |
| :------------------ | :---------- | :---: | :---: | :--------: |
| `MOI.SolverName`    | `String`    |   ⚠️   |   -   |     -      |
| `MOI.SolverVersion` | `String`    |   ⚠️   |   -   |     -      |
| `MOI.RawSolver`     | `String`    |   ⚠️   |   -   |     -      |

## `QUBODrivers`

### `struct Optimizer{T} <: QUBODrivers.AbstractSampler{T}`

### `QUBODrivers.sample(::Optimizer{T})`


```julia
QUBODrivers.@setup begin
    NumberOfReads::Int = 1_000
end
```