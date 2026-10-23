using GLPK

const MIP_SAF{T} = MOI.ScalarAffineFunction{T}
const MIP_SAT{T} = MOI.ScalarAffineTerm{T}
const MIP_SQF{T} = MOI.ScalarQuadraticFunction{T}
const MIP_SQT{T} = MOI.ScalarQuadraticTerm{T}

const MIP_TEST_OPTIMIZER = MOI.OptimizerWithAttributes(GLPK.Optimizer, MOI.Silent() => true)
const MIP_FAILING_OPTIMIZER = () -> error("test backend constructor failure")
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

struct MIPThrowingSupportsBackend end

MOI.supports(::MIPThrowingSupportsBackend, attr) = error("unsupported attribute: $(attr)")

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
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)) == expected_state
    @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ expected_value
    @test MOI.get(model, MOI.ObjectiveBound()) ≈ expected_value
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
                mip_bound = MOI.get(mip_model, MOI.ObjectiveBound())

                @test MOI.get(mip_model, MOI.TerminationStatus()) == MOI.OPTIMAL
                @test MOI.get(mip_model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
                @test mip_state == case.expected_state
                @test mip_value ≈ case.expected_value
                @test mip_bound ≈ case.expected_value
                @test mip_value ≈ _best_exact_value(exact_model)
            end
        end
    end

    return nothing
end

function _test_mip_sampler_unoptimized_status()
    @testset "Unoptimized status" begin
        model = MOI.instantiate(MIPSampler.Optimizer; with_bridge_type = Float64)

        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
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

function _test_mip_sampler_invalid_optimizer_factory()
    @testset "Invalid optimizer factory" begin
        model, x = _build_mip_test_model(Float64, 1; optimizer = MIP_FAILING_OPTIMIZER)

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

function _test_mip_sampler_zero_and_diagonal_quadratic_terms()
    @testset "Zero and diagonal quadratic terms" begin
        backend = MOI.instantiate(GLPK.Optimizer; with_bridge_type = Float64)
        x = MIPSampler._build_mip_model!(
            backend,
            2,
            Dict(1 => 0.0, 2 => -2.0),
            Dict((1, 1) => 3.0, (1, 2) => 0.0),
            1.0,
            0.5,
        )

        MOI.optimize!(backend)

        @test MOI.get(backend, MOI.TerminationStatus()) == MOI.OPTIMAL
        @test round.(Int, MOI.get.(backend, MOI.VariablePrimal(), x)) == [0, 1]
        @test MOI.get(backend, MOI.ObjectiveValue()) ≈ -1.5
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

function _test_mip_sampler_optional_attribute_and_metadata_fallbacks()
    @testset "Optional attributes and metadata fallbacks" begin
        model, x = _build_mip_test_model(Float64, 1)

        MOI.set(model, MOI.TimeLimitSec(), nothing)
        MOI.set(model, MOI.ObjectiveFunction{VI}(), x[1])

        MOI.optimize!(model)

        raw = MOI.get(model, MOI.RawSolver())
        metadata = QUBOTools.metadata(QUBOTools.solution(raw))

        _assert_sampler_metadata_schema(
            metadata;
            algorithm_name        = "MIP Sampler",
            execution_mode        = "mip_solve",
            number_of_reads       = 1,
            optimizer_evaluations = 1,
            final_number_of_reads = 1,
            status                = "OPTIMAL",
            termination_status    = MOI.OPTIMAL,
        )
        @test !("MOI.TimeLimitSec" in metadata["attributes"]["forwarded"])
        @test MIPSampler._backend_attribute(MOI.Utilities.Model{Float64}(), MOI.SolverName()) ===
              nothing
        @test !MIPSampler._supports_attribute(MIPThrowingSupportsBackend(), MOI.Silent())
    end

    return nothing
end

function test_mip_sampler()
    QUBODrivers.test(_config_mip_sampler!, MIPSampler.Optimizer)

    @testset "□ MIPSampler" verbose = true begin
        _test_mip_sampler_unoptimized_status()
        _test_mip_sampler_missing_optimizer()
        _test_mip_sampler_invalid_optimizer_factory()
        _test_mip_sampler_linear_only()
        _test_mip_sampler_plain_optimizer_factory()
        _test_mip_sampler_zero_and_diagonal_quadratic_terms()
        _test_mip_sampler_quadratic_only()
        _test_mip_sampler_mixed_quadratic_signs()
        _test_mip_sampler_attribute_forwarding()
        _test_mip_sampler_optional_attribute_and_metadata_fallbacks()
        _test_mip_sampler_exact_parity()
        _test_mip_sampler_controlled_outcomes()
        _test_mip_sampler_bound_normalization_matrix()
        _test_mip_sampler_state_invalidation()
    end

    return nothing
end

mutable struct MIPControlledBackend{T} <: MOI.AbstractOptimizer
    variables::Vector{VI}
    sense::MOI.OptimizationSense
    objective::Union{Nothing,MIP_SAF{T}}
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    primal_values::Union{Nothing,Vector{Float64}}
    objective_value::Any
    objective_bound::Any
    relative_gap::Any
    throw_on_optimize::Bool
    time_limit::Union{Nothing,Float64}
    threads::Union{Nothing,Int}
    silent::Bool
    rel_gap_tol::Union{Nothing,Float64}
    abs_gap_tol::Union{Nothing,Float64}

    function MIPControlledBackend{T}(;
        termination_status::MOI.TerminationStatusCode = MOI.OPTIMAL,
        primal_status::MOI.ResultStatusCode = MOI.FEASIBLE_POINT,
        primal_values::Union{Nothing,Vector{Float64}} = nothing,
        objective_value = :auto,
        objective_bound = 0.0,
        relative_gap = nothing,
        throw_on_optimize::Bool = false,
    ) where {T}
        return new{T}(
            VI[],
            MOI.MIN_SENSE,
            nothing,
            termination_status,
            primal_status,
            primal_values,
            objective_value,
            objective_bound,
            relative_gap,
            throw_on_optimize,
            nothing,
            nothing,
            false,
            nothing,
            nothing,
        )
    end
end

MIPControlledBackend(; kwargs...) = MIPControlledBackend{Float64}(; kwargs...)

MOI.is_empty(b::MIPControlledBackend) = isempty(b.variables) && isnothing(b.objective)
MOI.supports_incremental_interface(::MIPControlledBackend) = true
MOI.copy_to(dest::MIPControlledBackend, src::MOI.ModelLike) = MOIU.default_copy_to(dest, src)

function MOI.empty!(b::MIPControlledBackend)
    empty!(b.variables)
    b.sense = MOI.MIN_SENSE
    b.objective = nothing
    return b
end

MOI.get(::MIPControlledBackend, ::MOI.SolverName) = "ControlledMIPBackend"
MOI.get(::MIPControlledBackend, ::MOI.SolverVersion) = v"1.0.0"

MOI.supports(::MIPControlledBackend, ::MOI.Silent) = true
MOI.get(b::MIPControlledBackend, ::MOI.Silent) = b.silent
MOI.set(b::MIPControlledBackend, ::MOI.Silent, v::Bool) = (b.silent = v; nothing)

MOI.supports(::MIPControlledBackend, ::MOI.TimeLimitSec) = true
MOI.get(b::MIPControlledBackend, ::MOI.TimeLimitSec) = b.time_limit
MOI.set(b::MIPControlledBackend, ::MOI.TimeLimitSec, v::Union{Nothing,Real}) =
    (b.time_limit = isnothing(v) ? nothing : Float64(v); nothing)

MOI.supports(::MIPControlledBackend, ::MOI.NumberOfThreads) = true
MOI.get(b::MIPControlledBackend, ::MOI.NumberOfThreads) = b.threads
MOI.set(b::MIPControlledBackend, ::MOI.NumberOfThreads, v::Union{Nothing,Integer}) =
    (b.threads = isnothing(v) ? nothing : Int(v); nothing)

MOI.supports(::MIPControlledBackend, ::MOI.RelativeGapTolerance) = true
MOI.get(b::MIPControlledBackend, ::MOI.RelativeGapTolerance) = b.rel_gap_tol
MOI.set(b::MIPControlledBackend, ::MOI.RelativeGapTolerance, v::Union{Nothing,Real}) =
    (b.rel_gap_tol = isnothing(v) ? nothing : Float64(v); nothing)

MOI.supports(::MIPControlledBackend, ::MOI.AbsoluteGapTolerance) = true
MOI.get(b::MIPControlledBackend, ::MOI.AbsoluteGapTolerance) = b.abs_gap_tol
MOI.set(b::MIPControlledBackend, ::MOI.AbsoluteGapTolerance, v::Union{Nothing,Real}) =
    (b.abs_gap_tol = isnothing(v) ? nothing : Float64(v); nothing)

MOI.supports(::MIPControlledBackend, ::MOI.ObjectiveSense) = true
MOI.set(b::MIPControlledBackend, ::MOI.ObjectiveSense, s::MOI.OptimizationSense) =
    (b.sense = s; nothing)

MOI.supports(::MIPControlledBackend{T}, ::MOI.ObjectiveFunction{MIP_SAF{T}}) where {T} = true
MOI.set(b::MIPControlledBackend{T}, ::MOI.ObjectiveFunction{MIP_SAF{T}}, f::MIP_SAF{T}) where {T} =
    (b.objective = f; nothing)

MOI.supports_constraint(::MIPControlledBackend, ::Type{VI}, ::Type{MOI.ZeroOne}) = true
MOI.supports_constraint(
    ::MIPControlledBackend{T},
    ::Type{MIP_SAF{T}},
    ::Type{<:Union{MOI.GreaterThan{T},MOI.LessThan{T}}},
) where {T} = true

function MOI.add_variable(b::MIPControlledBackend)
    vi = VI(length(b.variables) + 1)
    push!(b.variables, vi)
    return vi
end

function MOI.add_constraint(::MIPControlledBackend, ::VI, ::MOI.ZeroOne)
    return MOI.ConstraintIndex{VI,MOI.ZeroOne}(1)
end

function MOI.add_constraint(
    ::MIPControlledBackend{T},
    ::MIP_SAF{T},
    ::S,
) where {T,S<:Union{MOI.GreaterThan{T},MOI.LessThan{T}}}
    return MOI.ConstraintIndex{MIP_SAF{T},S}(1)
end

function MOI.optimize!(b::MIPControlledBackend)
    b.throw_on_optimize && error("controlled backend optimize! failure")
    return nothing
end

MOI.get(b::MIPControlledBackend, ::MOI.TerminationStatus) = b.termination_status
MOI.get(b::MIPControlledBackend, ::MOI.PrimalStatus) = b.primal_status
MOI.get(::MIPControlledBackend, ::MOI.DualStatus) = MOI.NO_SOLUTION

function _eval_backend_affine(b::MIPControlledBackend{T}) where {T}
    f = b.objective
    isnothing(f) && return zero(T)
    acc = f.constant
    vals = b.primal_values
    for term in f.terms
        idx = term.variable.value
        v = if isnothing(vals)
            zero(T)
        elseif idx <= length(vals)
            convert(T, vals[idx])
        else
            zero(T)
        end
        acc += term.coefficient * v
    end
    return acc
end

function MOI.get(b::MIPControlledBackend{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    if !(b.primal_status == MOI.FEASIBLE_POINT || b.primal_status == MOI.NEARLY_FEASIBLE_POINT)
        throw(MOI.ResultIndexBoundsError(attr, 0))
    end
    vals = b.primal_values
    if isnothing(vals)
        return zero(T)
    elseif vi.value <= length(vals)
        return convert(T, vals[vi.value])
    else
        return zero(T)
    end
end

function MOI.get(b::MIPControlledBackend{T}, attr::MOI.ObjectiveValue) where {T}
    if b.objective_value === :unsupported
        throw(MOI.GetAttributeNotAllowed(attr, "ObjectiveValue unsupported"))
    elseif b.objective_value === :auto
        return _eval_backend_affine(b)
    elseif isnothing(b.objective_value)
        throw(MOI.GetAttributeNotAllowed(attr, "ObjectiveValue unavailable"))
    else
        return b.objective_value
    end
end

function MOI.get(b::MIPControlledBackend{T}, attr::MOI.ObjectiveBound) where {T}
    if b.objective_bound === :unsupported || isnothing(b.objective_bound)
        throw(MOI.GetAttributeNotAllowed(attr, "ObjectiveBound unavailable"))
    else
        return b.objective_bound
    end
end

function MOI.get(b::MIPControlledBackend{T}, attr::MOI.RelativeGap) where {T}
    if b.relative_gap === :unsupported || isnothing(b.relative_gap)
        throw(MOI.GetAttributeNotAllowed(attr, "RelativeGap unavailable"))
    else
        return b.relative_gap
    end
end

function _build_controlled_qubo_model(factory; sense = MOI.MIN_SENSE)
    model = MOI.instantiate(MIPSampler.Optimizer; with_bridge_type = Float64)
    MOI.set(model, MIPSampler.MIPOptimizer(), factory)
    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 2))
    f = MIP_SQF{Float64}(
        MIP_SQT{Float64}[MIP_SQT{Float64}(-2.0, x[1], x[2])],
        MIP_SAT{Float64}[MIP_SAT{Float64}(1.0, x[1]), MIP_SAT{Float64}(-3.0, x[2])],
        0.5,
    )
    MOI.set(model, MOI.ObjectiveSense(), sense)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    return model, x
end

function _test_mip_sampler_controlled_outcomes()
    @testset "Controlled MOI backend outcomes" begin
        # For f(x) = 1.0*x1 - 3.0*x2 - 2.0*x1*x2 + 0.5 on {0,1}^2:
        # x = [0, 0] ->  0.5
        # x = [1, 0] ->  1.5
        # x = [0, 1] -> -2.5
        # x = [1, 1] -> -3.5 (min), [1, 0] -> 1.5 (max)

        @testset "Optimal with incumbent, bound, and relative gap" begin
            factory = () -> MIPControlledBackend(
                termination_status = MOI.OPTIMAL,
                primal_status      = MOI.FEASIBLE_POINT,
                primal_values      = [1.0, 1.0],
                objective_bound    = -3.5,
                relative_gap       = 0.0,
            )
            model, x = _build_controlled_qubo_model(factory)
            MOI.set(model, MOI.RelativeGapTolerance(), 1e-4)
            MOI.set(model, MOI.AbsoluteGapTolerance(), 1e-6)
            MOI.optimize!(model)

            raw = MOI.get(model, MOI.RawSolver())
            metadata = QUBOTools.metadata(QUBOTools.solution(raw))

            @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(model, MOI.ResultCount()) == 1
            @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
            @test round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)) == [1, 1]
            @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ -3.5
            @test MOI.get(model, MOI.ObjectiveBound()) ≈ -3.5
            @test MOI.get(model, MOI.RelativeGap()) ≈ 0.0
            @test metadata["objective_bound"] ≈ -3.5
            @test metadata["relative_gap"] ≈ 0.0
            @test metadata["result_count"] == 1
            @test metadata["primal_status"] == MOI.FEASIBLE_POINT
            @test metadata["bound"]["value"] ≈ -3.5
            @test metadata["bound"]["provenance"] == "backend_reported_tolerance_dependent"
            @test metadata["bound"]["certified_exact"] === false
            @test metadata["bound"]["relative_gap_definition"] == "backend_solver_dependent"
            @test metadata["bound"]["relative_gap_tolerance"] ≈ 1e-4
            @test metadata["bound"]["absolute_gap_tolerance"] ≈ 1e-6
            @test "MOI.RelativeGapTolerance" in metadata["attributes"]["forwarded"]
            @test "MOI.AbsoluteGapTolerance" in metadata["attributes"]["forwarded"]
        end

        @testset "Time-limited with incumbent, relaxed bound, and solver-dependent gap" begin
            # Suboptimal rounded incumbent [0, 1] (value -2.5) with relaxed lower bound -5.0
            # and solver-reported relative gap 0.37 (distinct from |-2.5 - (-5.0)| / |-2.5| = 1.0).
            factory = () -> MIPControlledBackend(
                termination_status = MOI.TIME_LIMIT,
                primal_status      = MOI.NEARLY_FEASIBLE_POINT,
                primal_values      = [0.1, 0.9],
                objective_bound    = -5.0,
                relative_gap       = 0.37,
            )
            model, x = _build_controlled_qubo_model(factory)
            MOI.optimize!(model)

            raw = MOI.get(model, MOI.RawSolver())
            metadata = QUBOTools.metadata(QUBOTools.solution(raw))

            @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT
            @test MOI.get(model, MOI.ResultCount()) == 1
            @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
            @test round.(Int, MOI.get.(model, MOI.VariablePrimal(1), x)) == [0, 1]
            @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ -2.5
            @test MOI.get(model, MOI.ObjectiveBound()) ≈ -5.0
            @test MOI.get(model, MOI.RelativeGap()) ≈ 0.37
            @test metadata["termination_status"] == MOI.TIME_LIMIT
            @test metadata["objective_bound"] ≈ -5.0
            @test metadata["relative_gap"] ≈ 0.37

            # Small observed gap on TIME_LIMIT must NOT upgrade TerminationStatus to OPTIMAL
            zero_gap_factory = () -> MIPControlledBackend(
                termination_status = MOI.TIME_LIMIT,
                primal_status      = MOI.FEASIBLE_POINT,
                primal_values      = [1.0, 1.0],
                objective_bound    = -3.5,
                relative_gap       = 0.0,
            )
            MOI.set(model, MIPSampler.MIPOptimizer(), zero_gap_factory)
            MOI.optimize!(model)
            @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT
            @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ -3.5
            @test MOI.get(model, MOI.ObjectiveBound()) ≈ -3.5
            @test MOI.get(model, MOI.RelativeGap()) ≈ 0.0
        end

        @testset "Time-limited without incumbent but with a bound" begin
            for limit_status in (
                MOI.TIME_LIMIT,
                MOI.NODE_LIMIT,
                MOI.ITERATION_LIMIT,
                MOI.SOLUTION_LIMIT,
                MOI.INTERRUPTED,
            )
                factory = () -> MIPControlledBackend(
                    termination_status = limit_status,
                    primal_status      = MOI.NO_SOLUTION,
                    primal_values      = nothing,
                    objective_value    = nothing,
                    objective_bound    = -6.25,
                    relative_gap       = 0.15, # must be ignored because there is no incumbent
                )
                model, x = _build_controlled_qubo_model(factory; sense = MOI.MAX_SENSE)
                MOI.optimize!(model)

                raw = MOI.get(model, MOI.RawSolver())
                sampleset = QUBOTools.solution(raw)
                metadata = QUBOTools.metadata(sampleset)

                @test isempty(sampleset)
                @test MOI.get(model, MOI.TerminationStatus()) == limit_status
                @test MOI.get(model, MOI.ResultCount()) == 0
                @test MOI.get(model, MOI.PrimalStatus()) == MOI.NO_SOLUTION
                # In MAX_SENSE, raw MIP min bound -6.25 translates to upper bound +6.25
                @test MOI.get(model, MOI.ObjectiveBound()) ≈ 6.25
                @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())
                @test_throws Exception MOI.get(model, MOI.ObjectiveValue())
                @test_throws Exception MOI.get(model, MOI.ObjectiveValue(1))
                @test_throws Exception MOI.get(model, MOI.VariablePrimal(1), x[1])
                @test_throws Exception MOI.get(raw, QUBODrivers.QUBOTools_MOI.NumberOfReads(1))

                # Agreement with retained metadata and zero emitted counts
                @test metadata["termination_status"] == limit_status
                @test metadata["primal_status"] == MOI.NO_SOLUTION
                @test metadata["backend_primal_status"] == MOI.NO_SOLUTION
                @test metadata["result_count"] == 0
                @test metadata["objective_bound"] ≈ 6.25
                @test !haskey(metadata, "relative_gap")
                @test metadata["bound"]["value"] ≈ 6.25
                @test metadata["bound"]["raw_mip_min_bound"] ≈ -6.25
                @test metadata["bound"]["relative_gap"] === nothing
                @test metadata["bound"]["relative_gap_definition"] === nothing
                @test metadata["reads"]["number_of_reads"] == 0
                @test metadata["reads"]["final_number_of_reads"] == 0
                @test metadata["optimizer"]["evaluations"] == 0
                @test isempty(QUBODrivers.validate_metadata(sampleset))
                @test MOI.get(model, MOI.SolveTimeSec()) == metadata["time"]["effective"]
                @test metadata["time"]["effective"] >= 0.0
                @test metadata["time"]["total"] >= metadata["time"]["effective"]
            end
        end

        @testset "Unavailable bound never substitutes best sampled objective" begin
            for bound_spec in (:unsupported, -Inf)
                # With incumbent
                with_incumbent = () -> MIPControlledBackend(
                    termination_status = MOI.TIME_LIMIT,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [0.0, 1.0],
                    objective_bound    = bound_spec,
                    relative_gap       = 0.25,
                )
                model, x = _build_controlled_qubo_model(with_incumbent)
                MOI.optimize!(model)

                raw = MOI.get(model, MOI.RawSolver())
                metadata = QUBOTools.metadata(QUBOTools.solution(raw))

                @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT
                @test MOI.get(model, MOI.ResultCount()) == 1
                @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
                @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ -2.5
                @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())
                @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())
                @test !haskey(metadata, "objective_bound")
                @test !haskey(metadata, "relative_gap")
                @test metadata["bound"]["value"] === nothing

                # Without incumbent
                without_incumbent = () -> MIPControlledBackend(
                    termination_status = MOI.TIME_LIMIT,
                    primal_status      = MOI.NO_SOLUTION,
                    primal_values      = nothing,
                    objective_value    = nothing,
                    objective_bound    = bound_spec,
                )
                MOI.set(model, MIPSampler.MIPOptimizer(), without_incumbent)
                MOI.optimize!(model)

                metadata_empty = QUBOTools.metadata(QUBOTools.solution(raw))
                @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT
                @test MOI.get(model, MOI.ResultCount()) == 0
                @test MOI.get(model, MOI.PrimalStatus()) == MOI.NO_SOLUTION
                @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())
                @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())
                @test !haskey(metadata_empty, "objective_bound")
                @test metadata_empty["bound"]["value"] === nothing
            end
        end

        @testset "Numerical and error outcomes clear prior successful state" begin
            good_factory = () -> MIPControlledBackend(
                termination_status = MOI.OPTIMAL,
                primal_status      = MOI.FEASIBLE_POINT,
                primal_values      = [1.0, 1.0],
                objective_bound    = -3.5,
                relative_gap       = 0.0,
            )

            bad_factories = [
                "optimize! exception" => () -> MIPControlledBackend(throw_on_optimize = true),
                "NUMERICAL_ERROR" => () -> MIPControlledBackend(
                    termination_status = MOI.NUMERICAL_ERROR,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "INVALID_MODEL" => () -> MIPControlledBackend(
                    termination_status = MOI.INVALID_MODEL,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "INFEASIBLE" => () -> MIPControlledBackend(
                    termination_status = MOI.INFEASIBLE,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "DUAL_INFEASIBLE" => () -> MIPControlledBackend(
                    termination_status = MOI.DUAL_INFEASIBLE,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "OTHER_ERROR" => () -> MIPControlledBackend(
                    termination_status = MOI.OTHER_ERROR,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "OPTIMAL without primal" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.NO_SOLUTION,
                ),
                "TIME_LIMIT with INFEASIBLE_POINT" => () -> MIPControlledBackend(
                    termination_status = MOI.TIME_LIMIT,
                    primal_status      = MOI.INFEASIBLE_POINT,
                    primal_values      = [1.0, 1.0],
                ),
                "NaN ObjectiveBound" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [1.0, 1.0],
                    objective_bound    = NaN,
                ),
                "+Inf minimization ObjectiveBound" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [1.0, 1.0],
                    objective_bound    = Inf,
                ),
                "Inconsistent bound > incumbent" => () -> MIPControlledBackend(
                    termination_status = MOI.TIME_LIMIT,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [1.0, 1.0], # objective is -3.5
                    objective_bound    = -1.0,       # claims min >= -1.0 > -3.5
                ),
                "NaN VariablePrimal" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [NaN, 1.0],
                    objective_bound    = -3.5,
                ),
                "Out-of-range VariablePrimal" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [2.5, 1.0],
                    objective_bound    = -3.5,
                ),
                "NaN ObjectiveValue" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [1.0, 1.0],
                    objective_value    = NaN,
                    objective_bound    = -3.5,
                ),
                "Negative RelativeGap" => () -> MIPControlledBackend(
                    termination_status = MOI.OPTIMAL,
                    primal_status      = MOI.FEASIBLE_POINT,
                    primal_values      = [1.0, 1.0],
                    objective_bound    = -3.5,
                    relative_gap       = -0.1,
                ),
            ]

            for (label, bad_factory) in bad_factories
                @testset "$label" begin
                    model, x = _build_controlled_qubo_model(good_factory)
                    MOI.optimize!(model)
                    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL
                    @test MOI.get(model, MOI.ResultCount()) == 1
                    @test MOI.get(model, MOI.ObjectiveBound()) ≈ -3.5

                    MOI.set(model, MIPSampler.MIPOptimizer(), bad_factory)
                    @test_throws Exception MOI.optimize!(model)

                    raw = MOI.get(model, MOI.RawSolver())
                    @test MOI.get(model, MOI.ResultCount()) == 0
                    @test MOI.get(model, MOI.PrimalStatus()) == MOI.NO_SOLUTION
                    @test MOI.get(model, MOI.TerminationStatus()) != MOI.OPTIMAL
                    @test MOI.get(raw, MOI.TerminationStatus()) != MOI.OPTIMAL
                    @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())
                    @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())
                    @test_throws Exception MOI.get(model, MOI.ObjectiveValue(1))
                    @test_throws Exception MOI.get(model, MOI.VariablePrimal(1), x[1])
                end
            end
        end
    end

    return nothing
end

function _enumerate_qubo_values(domain::Symbol, scale::Float64, offset::Float64, l1::Float64, l2::Float64, q12::Float64, fixed::Dict{Int,Float64})
    vals_domain = domain === :bool ? (0.0, 1.0) : (-1.0, 1.0)
    xs1 = haskey(fixed, 1) ? (fixed[1],) : vals_domain
    xs2 = haskey(fixed, 2) ? (fixed[2],) : vals_domain
    out = Float64[]
    for a in xs1, b in xs2
        push!(out, scale * (l1 * a + l2 * b + q12 * a * b + offset))
    end
    return out
end

function _test_mip_sampler_bound_normalization_matrix()
    @testset "Bound direction and normalization across senses, domains, scales, constants, and fixed variables" begin
        for sense in (MOI.MIN_SENSE, MOI.MAX_SENSE),
            domain in (:bool, :spin),
            scale in (1.0, 2.5, -1.5),
            offset in (0.0, 3.25, -4.5),
            fixed_mode in (:none, :partial, :all),
            constant_only in (false, true)

            l1 = constant_only ? 0.0 : 1.5
            l2 = constant_only ? 0.0 : -2.0
            q12 = constant_only ? 0.0 : -3.0

            val_hi = domain === :bool ? 1.0 : 1.0
            val_lo = domain === :bool ? 0.0 : -1.0
            fixed = if fixed_mode === :none
                Dict{Int,Float64}()
            elseif fixed_mode === :partial
                Dict(1 => val_hi)
            else
                Dict(1 => val_hi, 2 => val_lo)
            end

            all_vals = _enumerate_qubo_values(domain, scale, offset, l1, l2, q12, fixed)
            exact_opt = sense == MOI.MIN_SENSE ? minimum(all_vals) : maximum(all_vals)
            raw_min_opt = sense == MOI.MIN_SENSE ? exact_opt : -exact_opt

            # Build via MOI source model when scale == 1.0, and via QUBOTools.Model for general signed scale
            sampler = MIPSampler.Optimizer{Float64}()
            if scale == 1.0
                src = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
                set = domain === :bool ? MOI.ZeroOne() : QUBODrivers.Spin()
                x, _ = MOI.add_constrained_variables(src, fill(set, 2))
                for (idx, fval) in fixed
                    MOI.add_constraint(src, x[idx], MOI.EqualTo(fval))
                end
                MOI.set(src, MOI.ObjectiveSense(), sense)
                f = MIP_SQF{Float64}(
                    MIP_SQT{Float64}[MIP_SQT{Float64}(q12, x[1], x[2])],
                    MIP_SAT{Float64}[MIP_SAT{Float64}(l1, x[1]), MIP_SAT{Float64}(l2, x[2])],
                    offset,
                )
                MOI.set(src, MOI.ObjectiveFunction{typeof(f)}(), f)
                MOI.copy_to(sampler, src)
            else
                vi1, vi2 = VI(1), VI(2)
                free_vars = Set{VI}()
                L_dict = Dict{VI,Float64}()
                Q_dict = Dict{Tuple{VI,VI},Float64}()
                eff_offset = offset

                if haskey(fixed, 1) && haskey(fixed, 2)
                    eff_offset += l1 * fixed[1] + l2 * fixed[2] + q12 * fixed[1] * fixed[2]
                elseif haskey(fixed, 1)
                    push!(free_vars, vi2)
                    eff_offset += l1 * fixed[1]
                    L_dict[vi2] = l2 + q12 * fixed[1]
                else
                    push!(free_vars, vi1, vi2)
                    L_dict[vi1] = l1
                    L_dict[vi2] = l2
                    Q_dict[(vi1, vi2)] = q12
                end

                qt_model = QUBOTools.Model{VI,Float64,Int}(
                    free_vars,
                    L_dict,
                    Q_dict;
                    scale  = scale,
                    offset = eff_offset,
                    sense  = sense == MOI.MIN_SENSE ? :min : :max,
                    domain = domain,
                )
                QUBODrivers.set_model!(sampler, qt_model)
                QUBODrivers._store_moi_variables!(sampler, [vi1, vi2])
                QUBODrivers._store_fixed_variables!(
                    sampler,
                    Dict{VI,QUBODrivers._FixedVariable{Float64}}(
                        VI(k) => QUBODrivers._FixedVariable{Float64}(v, Float64) for (k, v) in fixed
                    ),
                )
            end

            # 1. Exact solve with GLPK
            MOI.set(sampler, MIPSampler.MIPOptimizer(), MIP_TEST_OPTIMIZER)
            MOI.optimize!(sampler)
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(sampler, MOI.ResultCount()) == 1
            @test MOI.get(sampler, MOI.ObjectiveValue(1)) ≈ exact_opt
            @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ exact_opt

            # 2. Controlled relaxed bound without incumbent (gap of 1.75 in raw min space)
            delta = 1.75
            relaxed_raw_bound = raw_min_opt - delta
            expected_caller_bound = sense == MOI.MIN_SENSE ? (exact_opt - delta) : (exact_opt + delta)

            MOI.set(
                sampler,
                MIPSampler.MIPOptimizer(),
                () -> MIPControlledBackend(
                    termination_status = MOI.TIME_LIMIT,
                    primal_status      = MOI.NO_SOLUTION,
                    primal_values      = nothing,
                    objective_value    = nothing,
                    objective_bound    = relaxed_raw_bound,
                ),
            )
            MOI.optimize!(sampler)
            metadata = QUBOTools.metadata(QUBOTools.solution(sampler))

            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.TIME_LIMIT
            @test MOI.get(sampler, MOI.ResultCount()) == 0
            @test MOI.get(sampler, MOI.PrimalStatus()) == MOI.NO_SOLUTION
            @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ expected_caller_bound
            @test metadata["objective_bound"] ≈ expected_caller_bound
            if sense == MOI.MIN_SENSE
                @test MOI.get(sampler, MOI.ObjectiveBound()) <= exact_opt
            else
                @test MOI.get(sampler, MOI.ObjectiveBound()) >= exact_opt
            end
            expected_scope = isempty(fixed) ? "supplied_qubo" : "supplied_qubo_conditioned_on_fixed_variables"
            @test metadata["bound"]["scope"] == expected_scope
            @test metadata["bound"]["fixed_variables"] == length(fixed)
        end
    end

    return nothing
end

function _test_mip_sampler_state_invalidation()
    @testset "State invalidation on second solve, empty!, model change, and fixed-variable change" begin
        # 1. Bridged MOI model invalidations
        model, x = _build_mip_test_model(Float64, 2)
        f1 = MIP_SAF{Float64}(
            MIP_SAT{Float64}[MIP_SAT{Float64}(-3.0, x[1]), MIP_SAT{Float64}(2.0, x[2])],
            1.0,
        )
        MOI.set(model, MOI.ObjectiveFunction{typeof(f1)}(), f1)
        MOI.optimize!(model)
        @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ -2.0
        @test MOI.get(model, MOI.ObjectiveBound()) ≈ -2.0

        # Changing fixed-variable scope invalidates prior incumbent and bound immediately
        c_fix = MOI.add_constraint(model, x[1], MOI.EqualTo(0.0))
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(model, MOI.ResultCount()) == 0
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())
        @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())

        # Re-solving uses the new fixed-variable scope (x[1] == 0 -> min is at x[2] = 0 -> 1.0)
        MOI.optimize!(model)
        @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ 1.0
        @test MOI.get(model, MOI.ObjectiveBound()) ≈ 1.0

        # Changing objective sense invalidates prior result immediately
        MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(model, MOI.ResultCount()) == 0
        @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())

        MOI.optimize!(model)
        @test MOI.get(model, MOI.ObjectiveValue(1)) ≈ 3.0
        @test MOI.get(model, MOI.ObjectiveBound()) ≈ 3.0

        # MOI.empty! clears all solve state
        MOI.empty!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(model, MOI.ResultCount()) == 0
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.ObjectiveBound())
        @test_throws MOI.GetAttributeNotAllowed MOI.get(model, MOI.RelativeGap())

        # 2. Direct MIPSampler.Optimizer invalidations (without CachingOptimizer)
        sampler = MIPSampler.Optimizer{Float64}()
        MOI.set(sampler, MIPSampler.MIPOptimizer(), MIP_TEST_OPTIMIZER)
        src = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        sx, _ = MOI.add_constrained_variables(src, fill(MOI.ZeroOne(), 2))
        MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        sf = MIP_SAF{Float64}(
            MIP_SAT{Float64}[MIP_SAT{Float64}(-4.0, sx[1]), MIP_SAT{Float64}(1.0, sx[2])],
            0.0,
        )
        MOI.set(src, MOI.ObjectiveFunction{typeof(sf)}(), sf)
        MOI.copy_to(sampler, src)
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
        @test MOI.get(sampler, MOI.ResultCount()) == 1
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0

        # Mutating fixed_variables in-place on direct sampler invalidates the earlier bound and incumbent
        sampler.fixed_variables[sx[1]] = QUBODrivers._FixedVariable{Float64}(0.0, Float64)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test MOI.get(sampler, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.ObjectiveBound())
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.RelativeGap())
        @test_throws Exception MOI.get(sampler, MOI.ObjectiveValue(1))

        # Re-solving and then replacing model via QUBODrivers.set_model!(sampler, copy(sampler.model))
        empty!(sampler.fixed_variables)
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0
        QUBODrivers.set_model!(sampler, copy(QUBOTools.backend(sampler)))
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.ObjectiveBound())

        # Failed MOI.copy_to on direct sampler also clears prior solution
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0
        bad_src = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        bx, _ = MOI.add_constrained_variables(bad_src, fill(MOI.ZeroOne(), 1))
        MOI.add_constraint(bad_src, bx[1], MOI.EqualTo(2.0)) # invalid fixed value for binary
        MOI.set(bad_src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(bad_src, MOI.ObjectiveFunction{VI}(), bx[1])
        @test_throws ArgumentError MOI.copy_to(sampler, bad_src)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.ObjectiveBound())

        # PostSampleCallback interactions with status, bound, and relative gap
        MOI.copy_to(sampler, src)
        MOI.set(
            sampler,
            MIPSampler.MIPOptimizer(),
            () -> MIPControlledBackend(
                termination_status = MOI.OPTIMAL,
                primal_status      = MOI.FEASIBLE_POINT,
                primal_values      = [1.0, 0.0],
                objective_bound    = -4.0,
                relative_gap       = 0.0,
            ),
        )
        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (ss, _) -> (QUBOTools.metadata(ss)["tag"] = "ok"; nothing))
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0
        @test MOI.get(sampler, MOI.RelativeGap()) ≈ 0.0

        # Transforming callback replacing the sample downgrades OPTIMAL -> LOCALLY_SOLVED and clears relative_gap
        MOI.set(sampler, QUBODrivers.PostSampleTransform(), true)
        MOI.set(
            sampler,
            QUBODrivers.PostSampleCallback(),
            (ss, _) -> SampleSet{Float64,Int}(
                [Sample{Float64,Int}([0, 1], 1.0, 1)];
                metadata = deepcopy(QUBOTools.metadata(ss)),
                sense    = QUBOTools.sense(ss),
                domain   = QUBOTools.domain(ss),
            ),
        )
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        @test MOI.get(sampler, MOI.ResultCount()) == 1
        @test MOI.get(sampler, MOI.ObjectiveValue(1)) ≈ 1.0
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.RelativeGap())

        # Transforming callback removing all samples downgrades OPTIMAL -> OTHER_ERROR and sets ResultCount == 0
        MOI.set(
            sampler,
            QUBODrivers.PostSampleCallback(),
            (ss, _) -> SampleSet{Float64,Int}(;
                metadata = deepcopy(QUBOTools.metadata(ss)),
                sense    = QUBOTools.sense(ss),
                domain   = QUBOTools.domain(ss),
            ),
        )
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OTHER_ERROR
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test MOI.get(sampler, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        @test MOI.get(sampler, MOI.ObjectiveBound()) ≈ -4.0
        @test_throws MOI.GetAttributeNotAllowed MOI.get(sampler, MOI.RelativeGap())
    end

    return nothing
end
