raw"""
"""
function _test_fixed_variables(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "Fixed Variables" begin
        Test.@testset "Enforced Assignment" begin
            model = MOI.instantiate(sampler; with_bridge_type = T)

            Q    = T[1 2 3; 0 4 5; 0 0 6]
            x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

            MOI.add_constraint(model, x[2], MOI.EqualTo(one(T)))

            config!(model)
            MOI.optimize!(model)

            result_count = MOI.get(model, MOI.ResultCount())
            Test.@test result_count > 0

            for ri = 1:result_count
                values = T[MOI.get(model, MOI.VariablePrimal(ri), xi) for xi in x]

                Test.@test values[2] |> isone
                Test.@test MOI.get(model, MOI.ObjectiveValue(ri)) ≈ values' * Q * values
            end

            Test.@test_throws Exception MOI.get(model, MOI.VariablePrimal(result_count + 1), x[2])
        end

        Test.@testset "Invalid Fixed Values" begin
            model = MOI.instantiate(sampler; with_bridge_type = T)

            Q    = T[1 2; 0 3]
            x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 2))

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

            MOI.add_constraint(model, x[1], MOI.EqualTo(T(2)))

            config!(model)

            Test.@test_throws ArgumentError MOI.optimize!(model)
        end

        Test.@testset "Invalid Spin Fixed Values" begin
            model = MOI.instantiate(sampler; with_bridge_type = T)

            s, _ = MOI.add_constrained_variables(model, fill(Spin(), 2))

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                model,
                MOI.ObjectiveFunction{SQF{T}}(),
                SQF{T}(SQT{T}[], SAT{T}[SAT{T}(one(T), si) for si in s], zero(T)),
            )

            MOI.add_constraint(model, s[1], MOI.EqualTo(zero(T)))

            config!(model)

            Test.@test_throws ArgumentError MOI.optimize!(model)
        end
    end

    return nothing
end
