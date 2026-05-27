using GLPK

const MIP_SAF{T} = MOI.ScalarAffineFunction{T}
const MIP_SAT{T} = MOI.ScalarAffineTerm{T}
const MIP_SQF{T} = MOI.ScalarQuadraticFunction{T}
const MIP_SQT{T} = MOI.ScalarQuadraticTerm{T}

const MIP_TEST_OPTIMIZER = MOI.OptimizerWithAttributes(GLPK.Optimizer, MOI.Silent() => true)
const MIP_PARITY_CASES = [
    (
        name = "bool linear",
        n = 3,
        domain = :bool,
        sense = MOI.MIN_SENSE,
        affine = [(2.0, 1), (-3.0, 2), (1.0, 3)],
        quadratic = Tuple{Float64,Int,Int}[],
        constant = 0.0,
        expected_state = [0, 1, 0],
        expected_value = -3.0,
    ),
    (
        name = "bool quadratic only",
        n = 2,
        domain = :bool,
        sense = MOI.MIN_SENSE,
        affine = Tuple{Float64,Int}[],
        quadratic = [(-3.0, 1, 2)],
        constant = 0.0,
        expected_state = [1, 1],
        expected_value = -3.0,
    ),
    (
        name = "bool mixed signs",
        n = 3,
        domain = :bool,
        sense = MOI.MIN_SENSE,
        affine = [(1.0, 1), (1.0, 2)],
        quadratic = [(-2.0, 1, 3), (3.0, 2, 3), (-1.0, 1, 2)],
        constant = 0.0,
        expected_state = [1, 0, 1],
        expected_value = -1.0,
    ),
    (
        name = "bool constant offset",
        n = 2,
        domain = :bool,
        sense = MOI.MIN_SENSE,
        affine = [(2.0, 1), (-3.0, 2)],
        quadratic = [(2.0, 1, 2)],
        constant = 4.5,
        expected_state = [0, 1],
        expected_value = 1.5,
    ),
    (
        name = "bool max sense",
        n = 2,
        domain = :bool,
        sense = MOI.MAX_SENSE,
        affine = [(-1.0, 1), (2.0, 2)],
        quadratic = [(3.0, 1, 2)],
        constant = 0.0,
        expected_state = [1, 1],
        expected_value = 4.0,
    ),
    (
        name = "spin affine quadratic",
        n = 2,
        domain = :spin,
        sense = MOI.MIN_SENSE,
        affine = [(1.0, 1), (-2.0, 2)],
        quadratic = [(1.5, 1, 2)],
        constant = -0.25,
        expected_state = [-1, 1],
        expected_value = -4.75,
    ),
]

function _config_mip_sampler!(model)
    MOI.set(model, MIPSampler.MIPOptimizer(), MIP_TEST_OPTIMIZER)

    return nothing
end

function _build_mip_test_model(::Type{T}, n::Integer; optimizer = MIP_TEST_OPTIMIZER) where {T}
    model = MOI.instantiate(MIPSampler.Optimizer; with_bridge_type = T)

    MOI.set(model, MIPSampler.MIPOptimizer(), optimizer)

    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    return model, x
end

function _add_mip_parity_variables(model, case)
    sets = if case.domain === :bool
        fill(MOI.ZeroOne(), case.n)
    else
        fill(QUBODrivers.Spin(), case.n)
    end

    x, _ = MOI.add_constrained_variables(model, sets)

    return x
end

function _set_mip_parity_objective!(model, x, case)
    affine_terms = MIP_SAT{Float64}[
        MIP_SAT{Float64}(coefficient, x[i]) for (coefficient, i) in case.affine
    ]

    if isempty(case.quadratic)
        f = MIP_SAF{Float64}(affine_terms, case.constant)
    else
        quadratic_terms = MIP_SQT{Float64}[
            MIP_SQT{Float64}(coefficient, x[i], x[j]) for
            (coefficient, i, j) in case.quadratic
        ]
        f = MIP_SQF{Float64}(quadratic_terms, affine_terms, case.constant)
    end

    MOI.set(model, MOI.ObjectiveSense(), case.sense)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

    return nothing
end

function _build_mip_parity_model(optimizer, case)
    model = MOI.instantiate(optimizer; with_bridge_type = Float64)

    if optimizer === MIPSampler.Optimizer
        MOI.set(model, MIPSampler.MIPOptimizer(), GLPK.Optimizer)
    end

    x = _add_mip_parity_variables(model, case)
    _set_mip_parity_objective!(model, x, case)

    return model, x
end

function _best_exact_value(model)
    values = [MOI.get(model, MOI.ObjectiveValue(i)) for i in 1:MOI.get(model, MOI.ResultCount())]

    return MOI.get(model, MOI.ObjectiveSense()) == MOI.MIN_SENSE ? minimum(values) :
           maximum(values)
end

function _assert_single_solution(model, x, expected_state, expected_value)
    @test MOI.get(model, MOI.ResultCount()) == 1
    @test round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)) == expected_state
    @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ expected_value
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL

    return nothing
end

function _test_mip_sampler_exact_parity()
    @testset "GLPK parity with ExactSampler" begin
        for case in MIP_PARITY_CASES
            @testset "$(case.name)" begin
                mip_model, mip_x = _build_mip_parity_model(MIPSampler.Optimizer, case)
                exact_model, _ = _build_mip_parity_model(ExactSampler.Optimizer, case)

                MOI.optimize!(mip_model)
                MOI.optimize!(exact_model)

                mip_state = round.(Int, MOI.get.(mip_model, MOI.VariablePrimal(1), mip_x))
                mip_value = MOI.get(mip_model, MOI.ObjectiveValue(1))

                @test MOI.get(mip_model, MOI.TerminationStatus()) == MOI.OPTIMAL
                @test mip_state == case.expected_state
                @test mip_value ≈ case.expected_value
                @test mip_value ≈ _best_exact_value(exact_model)
            end
        end
    end

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

function _test_mip_sampler_plain_optimizer_factory()
    @testset "Plain optimizer factory" begin
        model, x = _build_mip_test_model(Float64, 2; optimizer = GLPK.Optimizer)
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
        _test_mip_sampler_plain_optimizer_factory()
        _test_mip_sampler_quadratic_only()
        _test_mip_sampler_mixed_quadratic_signs()
        _test_mip_sampler_attribute_forwarding()
        _test_mip_sampler_exact_parity()
    end

    return nothing
end
