raw"""
    _test_corner_blanks(config!::Function, sampler::Type{S}) where {S<:AbstractSampler}

This test case probes problems with blanks in the objective function.
Some solvers will only return answers for variables present in the expression[^QUBODrivers#6].

```math
\begin{array}{rl}
\min          & x_1 + x_3         \\
\textrm{s.t.} & x_1 in \mathbb{B} \\
              & x_2 in \mathbb{B} \\
              & x_3 in \mathbb{B}
\end{array}
```

## Related Issues
[^QUBODrivers#6]: QUBODrivers.jl Issue [#6](https://github.com/psrenergy/QUBODrivers.jl/issues/6)

"""
function _test_corner_blanks(
    config!::Function,
    sampler::Type{S},
) where {T,S<:AbstractSampler{T}}
    @testset "Blanks" begin
        # Build Model
        model = MOI.instantiate(sampler; with_bridge_type = T)

        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{SAF{T}}(),
            SAF{T}(SAT{T}[SAT{T}(one(T), x[1]), SAT{T}(one(T), x[3])], zero(T)),
        )

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0
    end
end

function _test_corner_examples(
    config!::Function,
    sampler::Type{S},
) where {S<:AbstractSampler}
    Test.@testset "⊚ Corner cases ⊚" begin
        _test_corner_blanks(config!, sampler)
    end

    return nothing
end