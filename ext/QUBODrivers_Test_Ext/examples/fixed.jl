raw"""
"""
function _assert_fixed_state_objectives(
    returned::Dict{NTuple{3,T},T},
    oracle::Dict{NTuple{3,T},T},
) where {T}
    Test.@test length(returned) == length(oracle)

    for (state, objective) in oracle
        Test.@test haskey(returned, state)
        Test.@test returned[state] ≈ objective
    end

    return nothing
end

function _test_exact_fixed_variable_oracles(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    S <: QUBODrivers.ExactSampler.Optimizer || return nothing

    Test.@testset "Exact Reduction Oracle" begin
        Test.@testset "Bool" begin
            model = MOI.instantiate(sampler; with_bridge_type = T)

            Q    = T[3 -8 1; 0 2 -4; 0 0 5]
            x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

            MOI.add_constraint(model, x[2], MOI.EqualTo(one(T)))

            config!(model)
            MOI.optimize!(model)

            oracle = Dict{NTuple{3,T},T}()
            for x1 in (zero(T), one(T)), x3 in (zero(T), one(T))
                state = (x1, one(T), x3)
                values = T[state...]

                oracle[state] = values' * Q * values
            end

            returned = Dict{NTuple{3,T},T}()
            result_count = MOI.get(model, MOI.ResultCount())

            Test.@test result_count == length(oracle)

            for ri = 1:result_count
                state = ntuple(i -> MOI.get(model, MOI.VariablePrimal(ri), x[i]), 3)

                Test.@test state[2] == one(T)
                returned[state] = MOI.get(model, MOI.ObjectiveValue(ri))
            end

            _assert_fixed_state_objectives(returned, oracle)
        end

        Test.@testset "Spin" begin
            model = MOI.instantiate(sampler; with_bridge_type = T)

            h    = T[-2, 5, 1]
            J    = T[0 4 -3; 0 0 2; 0 0 0]
            s, _ = MOI.add_constrained_variables(model, fill(Spin(), 3))

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                model,
                MOI.ObjectiveFunction{SQF{T}}(),
                SQF{T}(
                    SQT{T}[SQT{T}(J[i, j], s[i], s[j]) for i = 1:3 for j = 1:3],
                    SAT{T}[SAT{T}(h[i], s[i]) for i = 1:3],
                    zero(T),
                ),
            )

            MOI.add_constraint(model, s[2], MOI.EqualTo(-one(T)))

            config!(model)
            MOI.optimize!(model)

            oracle = Dict{NTuple{3,T},T}()
            for s1 in (-one(T), one(T)), s3 in (-one(T), one(T))
                state = (s1, -one(T), s3)
                oracle[state] =
                    sum(J[i, j] * state[i] * state[j] for i = 1:3 for j = 1:3) +
                    sum(h[i] * state[i] for i = 1:3)
            end

            returned = Dict{NTuple{3,T},T}()
            result_count = MOI.get(model, MOI.ResultCount())

            Test.@test result_count == length(oracle)

            for ri = 1:result_count
                state = ntuple(i -> MOI.get(model, MOI.VariablePrimal(ri), s[i]), 3)

                Test.@test state[2] == -one(T)
                returned[state] = MOI.get(model, MOI.ObjectiveValue(ri))
            end

            _assert_fixed_state_objectives(returned, oracle)
        end
    end

    return nothing
end

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

            optimizer = MOI.get(model, MOI.RawSolver())
            Test.@test MOI.get(optimizer, MOI.VariablePrimalStart(), x[2]) == one(T)
            Test.@test MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], one(T)) === nothing
            Test.@test MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], nothing) === nothing
            Test.@test_throws Exception MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], zero(T))
            Test.@test_throws Exception MOI.get(model, MOI.VariablePrimal(result_count + 1), x[2])
        end

        _test_exact_fixed_variable_oracles(config!, sampler)

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
