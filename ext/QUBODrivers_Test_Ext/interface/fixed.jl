function _test_fixed_variable_reduction_helpers()
    Test.@testset "Fixed Variable Reduction Helpers" begin
        let vi = VI(1), linear_terms = Dict{VI,Float64}()
            offset = QUBODrivers._accumulate_affine_term!(
                linear_terms,
                Dict{VI,Float64}(),
                vi,
                3.0,
                1.0,
            )

            Test.@test offset == 1.0
            Test.@test linear_terms == Dict(vi => 3.0)
        end

        let vi = VI(1), linear_terms = Dict{VI,Float64}()
            offset = QUBODrivers._accumulate_affine_term!(
                linear_terms,
                Dict(vi => 1.0),
                vi,
                3.0,
                1.0,
            )

            Test.@test offset == 4.0
            Test.@test isempty(linear_terms)
        end

        let xi = VI(1), xj = VI(2)
            linear_terms = Dict{VI,Float64}()
            quadratic_terms = Dict{Tuple{VI,VI},Float64}()

            offset = QUBODrivers._accumulate_quadratic_term!(
                linear_terms,
                quadratic_terms,
                Dict{VI,Float64}(),
                xi,
                xj,
                5.0,
                2.0,
            )

            Test.@test offset == 2.0
            Test.@test isempty(linear_terms)
            Test.@test quadratic_terms == Dict((xi, xj) => 5.0)

            offset = QUBODrivers._accumulate_quadratic_term!(
                linear_terms,
                quadratic_terms,
                Dict{VI,Float64}(),
                xj,
                xi,
                3.0,
                offset,
            )

            Test.@test offset == 2.0
            Test.@test quadratic_terms == Dict((xi, xj) => 8.0)
        end

        let xi = VI(1), xj = VI(2)
            linear_terms = Dict{VI,Float64}()
            quadratic_terms = Dict{Tuple{VI,VI},Float64}()

            offset = QUBODrivers._accumulate_quadratic_term!(
                linear_terms,
                quadratic_terms,
                Dict(xi => -1.0),
                xi,
                xj,
                5.0,
                2.0,
            )

            Test.@test offset == 2.0
            Test.@test linear_terms == Dict(xj => -5.0)
            Test.@test isempty(quadratic_terms)
        end

        let xi = VI(1), xj = VI(2)
            linear_terms = Dict{VI,Float64}()
            quadratic_terms = Dict{Tuple{VI,VI},Float64}()

            offset = QUBODrivers._accumulate_quadratic_term!(
                linear_terms,
                quadratic_terms,
                Dict(xi => -1.0, xj => 1.0),
                xi,
                xj,
                5.0,
                2.0,
            )

            Test.@test offset == -3.0
            Test.@test isempty(linear_terms)
            Test.@test isempty(quadratic_terms)
        end
    end

    return nothing
end

function _test_moi_fixed_variable_contracts(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "Fixed Variable Contracts" begin
        model = MOI.instantiate(sampler; with_bridge_type = T)

        Q    = T[1 2 0; 0 3 4; 0 0 5]
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

        MOI.add_constraint(model, x[2], MOI.EqualTo(one(T)))

        config!(model)
        MOI.optimize!(model)

        optimizer = MOI.get(model, MOI.RawSolver())

        Test.@test MOI.get(optimizer, MOI.NumberOfVariables()) == length(x)
        Test.@test MOI.get(optimizer, MOI.ListOfVariableIndices()) == x
        Test.@test (VI, MOI.ZeroOne) in MOI.get(optimizer, MOI.ListOfConstraintTypesPresent())
        Test.@test (VI, MOI.EqualTo{T}) in MOI.get(optimizer, MOI.ListOfConstraintTypesPresent())
        Test.@test MOI.get(optimizer, MOI.NumberOfConstraints{VI,MOI.EqualTo{T}}()) == 1

        fixed_constraint_indices = MOI.get(optimizer, MOI.ListOfConstraintIndices{VI,MOI.EqualTo{T}}())

        Test.@test length(fixed_constraint_indices) == 1
        Test.@test MOI.is_valid(optimizer, only(fixed_constraint_indices))
        Test.@test MOI.get(optimizer, MOI.ConstraintFunction(), only(fixed_constraint_indices)) == x[2]
        Test.@test MOI.get(optimizer, MOI.ConstraintSet(), only(fixed_constraint_indices)) == MOI.EqualTo(one(T))
        Test.@test MOI.get(optimizer, MOI.VariablePrimalStart(), x[2]) == one(T)
        Test.@test MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], one(T)) === nothing
        Test.@test MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], nothing) === nothing
        Test.@test_throws Exception MOI.set(optimizer, MOI.VariablePrimalStart(), x[2], zero(T))
        Test.@test MOI.set(optimizer, MOI.RawOptimizerAttribute("fixed_variables"), :user_fixed) === nothing
        Test.@test MOI.set(optimizer, MOI.RawOptimizerAttribute("moi_variables"), :user_variables) === nothing
        Test.@test MOI.get(optimizer, MOI.RawOptimizerAttribute("fixed_variables")) == :user_fixed
        Test.@test MOI.get(optimizer, MOI.RawOptimizerAttribute("moi_variables")) == :user_variables
        Test.@test MOI.get(optimizer, MOI.NumberOfVariables()) == length(x)
        Test.@test MOI.get(optimizer, MOI.ListOfVariableIndices()) == x
        Test.@test MOI.get(optimizer, MOI.VariablePrimalStart(), x[2]) == one(T)

        MOI.empty!(optimizer)

        Test.@test MOI.is_empty(optimizer)
        Test.@test MOI.get(optimizer, MOI.NumberOfVariables()) == 0
        Test.@test isempty(MOI.get(optimizer, MOI.ListOfVariableIndices()))
        Test.@test isempty(MOI.get(optimizer, MOI.ListOfConstraintTypesPresent()))
    end

    return nothing
end

function _test_moi_fixed_variable_constraint_types(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "Fixed Variable Constraint Types" begin
        optimizer = sampler()

        Test.@test MOI.supports_constraint(optimizer, VI, MOI.EqualTo{Int})

        model = MOI.instantiate(sampler; with_bridge_type = T)

        Q    = T[2 -3; 0 4]
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 2))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

        MOI.add_constraint(model, x[1], MOI.EqualTo(1))

        config!(model)
        MOI.optimize!(model)

        optimizer = MOI.get(model, MOI.RawSolver())
        result_count = MOI.get(model, MOI.ResultCount())
        fixed_constraint_indices = MOI.get(
            optimizer,
            MOI.ListOfConstraintIndices{VI,MOI.EqualTo{Int}}(),
        )

        Test.@test result_count > 0
        Test.@test MOI.get(optimizer, MOI.NumberOfConstraints{VI,MOI.EqualTo{Int}}()) == 1
        Test.@test length(fixed_constraint_indices) == 1
        Test.@test MOI.is_valid(optimizer, only(fixed_constraint_indices))
        Test.@test MOI.get(optimizer, MOI.ConstraintFunction(), only(fixed_constraint_indices)) == x[1]
        Test.@test MOI.get(optimizer, MOI.ConstraintSet(), only(fixed_constraint_indices)) == MOI.EqualTo(1)

        for ri = 1:result_count
            Test.@test MOI.get(model, MOI.VariablePrimal(ri), x[1]) == one(T)
        end
    end

    return nothing
end
