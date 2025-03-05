raw"""
"""
function _test_fixed_variables(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "Fixed Variables" begin
        model = MOI.instantiate(sampler; with_bridge_type = T)

        Q    = T[1 2 3; 0 4 5; 0 0 6]
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne, 3))

        MOI.set(
            model,
            MOI.ObjectiveSense(),
            MOI.MIN_SENSE,
        )

        MOI.set(
            model,
            MOI.ObjectiveFunction{SQF{T}}(),
            x' * Q * x,
        )

        MOI.add_constraint(model, x[2], MOI.EqualTo(one(T)))

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0

        for ri = 1:MOI.get(model, MOI.ResultCount())
            Test.@test MOI.get(model, MOI.VariablePrimal(ri)) |> isone
        end
    end

    return nothing
end
