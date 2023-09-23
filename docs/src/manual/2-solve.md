# Solving QUBO

## Solving Simple QUBO Model with QUBODrivers' [`RandomSampler.Optimizer`](@ref)

```@example simple-workflow
using JuMP
using QUBODrivers

model = Model(RandomSampler.Optimizer)

Q = [
    -1.0  2.0  2.0
     2.0 -1.0  2.0
     2.0  2.0 -1.0
]

@variable(model, x[1:3], Bin)
@objective(model, Min, x' * Q * x)

optimize!(model)
```

### Recover Results

```@example simple-workflow
for i = 1:result_count(model)
    xi = value.(x; result=i)              # Solution vector
    yi = objective_value(model; result=i) # Energy

    println("f($xi) = $(yi)")
end
```
