using GLPK

const MIP_SAF{T} = MOI.ScalarAffineFunction{T}
const MIP_SAT{T} = MOI.ScalarAffineTerm{T}
const MIP_SQF{T} = MOI.ScalarQuadraticFunction{T}
const MIP_SQT{T} = MOI.ScalarQuadraticTerm{T}

const MIP_TEST_OPTIMIZER = MOI.OptimizerWithAttributes(GLPK.Optimizer, MOI.Silent() => true)

function _config_mip_sampler!(model)
    MOI.set(model, MIPSampler.MIPOptimizer(), MIP_TEST_OPTIMIZER)

    return nothing
end

function _build_mip_test_model(::Type{T}, n::Integer) where {T}
    model = MOI.instantiate(MIPSampler.Optimizer; with_bridge_type = T)

    MOI.set(model, MIPSampler.MIPOptimizer(), MIP_TEST_OPTIMIZER)

    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    return model, x
end

function _assert_single_solution(model, x, expected_state, expected_value)
    @test MOI.get(model, MOI.ResultCount()) == 1
    @test round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)) == expected_state
    @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ expected_value
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL

    return nothing
end

function _test_mip_sampler_missing_optimizer()
    @testset "Missing MIP optimizer" begin
        model = MOI.instantiate(MIPSampler.Optimizer; with_bridge_type = Float64)
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 1))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{VI}(), x[1])

        @test_throws ArgumentError MOI.optimize!(model)
    end

    return nothing
end

function _test_mip_sampler_linear_only()
    @testset "Linear only" begin
        model, x = _build_mip_test_model(Float64, 3)
        f = MIP_SAF{Float64}(
            MIP_SAT{Float64}[
                MIP_SAT{Float64}(2.0, x[1]),
                MIP_SAT{Float64}(-3.0, x[2]),
                MIP_SAT{Float64}(1.0, x[3]),
            ],
            0.0,
        )

        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
        MOI.optimize!(model)

        _assert_single_solution(model, x, [0, 1, 0], -3.0)
    end

    return nothing
end

function _test_mip_sampler_quadratic_only()
    @testset "Quadratic only" begin
        model, x = _build_mip_test_model(Float64, 2)
        f = MIP_SQF{Float64}(
            MIP_SQT{Float64}[MIP_SQT{Float64}(-3.0, x[1], x[2])],
            MIP_SAT{Float64}[],
            0.0,
        )

        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
        MOI.optimize!(model)

        _assert_single_solution(model, x, [1, 1], -3.0)
    end

    return nothing
end

function _test_mip_sampler_mixed_quadratic_signs()
    @testset "Mixed quadratic signs" begin
        model, x = _build_mip_test_model(Float64, 3)
        f = MIP_SQF{Float64}(
            MIP_SQT{Float64}[
                MIP_SQT{Float64}(-2.0, x[1], x[3]),
                MIP_SQT{Float64}(3.0, x[2], x[3]),
                MIP_SQT{Float64}(-1.0, x[1], x[2]),
            ],
            MIP_SAT{Float64}[
                MIP_SAT{Float64}(1.0, x[1]),
                MIP_SAT{Float64}(1.0, x[2]),
            ],
            0.0,
        )

        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
        MOI.optimize!(model)

        _assert_single_solution(model, x, [1, 0, 1], -1.0)
    end

    return nothing
end

function _test_mip_sampler_attribute_forwarding()
    @testset "Attribute forwarding" begin
        model, x = _build_mip_test_model(Float64, 1)

        MOI.set(model, MOI.TimeLimitSec(), 10.0)
        MOI.set(model, MOI.NumberOfThreads(), 1)
        MOI.set(model, MOI.Silent(), true)
        MOI.set(model, MOI.ObjectiveFunction{VI}(), x[1])

        MOI.optimize!(model)

        raw = MOI.get(model, MOI.RawSolver())
        metadata = QUBOTools.metadata(QUBOTools.solution(raw))
        forwarded = metadata["attributes"]["forwarded"]

        @test "MOI.TimeLimitSec" in forwarded
        @test "MOI.Silent" in forwarded
    end

    return nothing
end

function test_mip_sampler()
    QUBODrivers.test(_config_mip_sampler!, MIPSampler.Optimizer)

    @testset "□ MIPSampler" verbose = true begin
        _test_mip_sampler_missing_optimizer()
        _test_mip_sampler_linear_only()
        _test_mip_sampler_quadratic_only()
        _test_mip_sampler_mixed_quadratic_signs()
        _test_mip_sampler_attribute_forwarding()
    end

    return nothing
end
