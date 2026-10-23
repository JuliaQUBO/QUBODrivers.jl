module MIPSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, VI, Sample, SampleSet, RawSamplerAttribute, @raw_attr_str

const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}

const _SOLVE_SCOPE_KEY = "__mip_solve_scope_signature__"

const _SOLVED_TERMINATION_STATUSES = (
    MOI.OPTIMAL,
    MOI.LOCALLY_SOLVED,
)

const _LIMIT_TERMINATION_STATUSES = (
    MOI.TIME_LIMIT,
    MOI.ITERATION_LIMIT,
    MOI.NODE_LIMIT,
    MOI.SOLUTION_LIMIT,
    MOI.MEMORY_LIMIT,
    MOI.OBJECTIVE_LIMIT,
    MOI.NORM_LIMIT,
    MOI.OTHER_LIMIT,
    MOI.INTERRUPTED,
)

@doc raw"""
    MIPSampler.Optimizer{T}

MOI-native exact baseline that linearizes a QUBO into a binary mixed-integer
linear model and solves it with a user-supplied MOI optimizer.

`MIPSampler` does not depend on any concrete MIP solver. Set
[`MIPOptimizer`](@ref) to a compatible optimizer factory, such as
`HiGHS.Optimizer`, `GLPK.Optimizer`, or
`MOI.OptimizerWithAttributes(HiGHS.Optimizer, MOI.Silent() => true)`.

The sampler introduces one binary auxiliary variable for each off-diagonal
quadratic term and enforces the product relation with the standard
Fortet/McCormick inequalities. This follows the usual linear reformulation
route for binary polynomial optimization; see also Elloumi, Sourour, and
Verchere, "Efficient linear reformulations for binary polynomial optimization
problems", Computers & Operations Research 155 (2023), 106240.

At most one best incumbent sample is returned, with its binary state rounded and
independently re-evaluated on the full QUBO objective. `MIPSampler` ignores
`QUBODrivers.FinalNumberOfReads`.

## Objective Bounds, Gaps, and Limit Terminations

- When the MIP backend reports a finite objective bound, `MIPSampler` translates
  it back to the caller's original objective sense (`MOI.MIN_SENSE` or
  `MOI.MAX_SENSE`), variable domain (`MOI.ZeroOne` or `QUBODrivers.Spin`),
  scaling, constant offset, and fixed-variable (`MOI.EqualTo`) conditioning, and
  exposes it via `MOI.ObjectiveBound()` as well as `metadata["objective_bound"]`
  and `metadata["bound"]`.
- **Scope:** The bound applies to the supplied QUBO/Ising objective, possibly
  conditioned on any fixed variables in the model. A bound on a penalized QUBO
  relaxation is not automatically a valid bound on an original constrained
  problem unless the penalty parameter has been independently certified.
- **Numerical provenance:** Bounds and relative gaps are **backend-reported,
  tolerance-dependent** quantities, not exact-arithmetic certificates. Do not
  treat them as exact proofs in certified preprocessing without a separate
  verification layer, and do not infer global optimality from a small observed
  gap when `MOI.TerminationStatus()` is not `MOI.OPTIMAL`.
- **Relative gap:** When an incumbent and a bound are both present and the
  backend reports `MOI.RelativeGap()`, `MIPSampler` exposes that solver-dependent
  value through `MOI.RelativeGap()` and `metadata["relative_gap"]` (labeled
  `"backend_solver_dependent"` in `metadata["bound"]["relative_gap_definition"]`).
  It is not interchangeable with a gap recomputed from the rounded incumbent,
  and a primal-free result has no finite incumbent gap.
- **Primal-free limit terminations:** If the backend stops on a normal limit or
  interruption (`MOI.TIME_LIMIT`, `MOI.NODE_LIMIT`, `MOI.ITERATION_LIMIT`,
  `MOI.SOLUTION_LIMIT`, `MOI.MEMORY_LIMIT`, `MOI.OBJECTIVE_LIMIT`,
  `MOI.NORM_LIMIT`, `MOI.OTHER_LIMIT`, or `MOI.INTERRUPTED`) without a feasible
  incumbent, `MIPSampler` returns an empty `SampleSet` (`MOI.ResultCount() == 0`,
  `MOI.PrimalStatus() == MOI.NO_SOLUTION`) while preserving
  `MOI.TerminationStatus()`, `MOI.ObjectiveBound()` (when available), and solve
  timing metadata.

## Attributes
- `MIPOptimizer`, `"mip_optimizer"`: MOI-compatible optimizer factory used to
  solve the generated binary MIP.
"""
QUBODrivers.@setup Optimizer begin
    name       = "MIP Sampler"
    version    = QUBODrivers.__version__()
    attributes = begin
        MIPOptimizer["mip_optimizer"]::Any = nothing
    end
end

QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = false

@doc raw"""
    MIPOptimizer()

Optimizer attribute that stores the MOI-compatible MIP backend factory used by
[`MIPSampler.Optimizer`](@ref).
"""
MIPOptimizer

const _RawMIPOptimizer = QUBODrivers.RawSamplerAttribute{Symbol("mip_optimizer")}

MOI.Utilities.map_indices(_, ::MIPOptimizer, value) = value
MOI.Utilities.map_indices(_, ::_RawMIPOptimizer, value) = value

# MOI.RelativeGapTolerance & MOI.AbsoluteGapTolerance support
MOI.supports(
    ::Optimizer,
    ::Union{MOI.RelativeGapTolerance,raw_attr"moi/relativegaptolerance"},
) = true

QUBODrivers.default_raw_attr(::Optimizer, ::raw_attr"moi/relativegaptolerance") = nothing

function MOI.get(sampler::Optimizer, ::MOI.RelativeGapTolerance)
    return MOI.get(sampler, RawSamplerAttribute("moi/relativegaptolerance"))
end

function MOI.set(sampler::Optimizer, ::MOI.RelativeGapTolerance, value)
    return MOI.set(sampler, RawSamplerAttribute("moi/relativegaptolerance"), value)
end

function MOI.set(sampler::Optimizer, attr::raw_attr"moi/relativegaptolerance", value)
    if !(isnothing(value) || (value isa Real && isfinite(value) && value >= zero(value)))
        error("Value for 'MOI.RelativeGapTolerance' must be a non-negative finite number, or 'nothing'")
    end

    QUBODrivers.set_raw_attr!(sampler, attr, isnothing(value) ? nothing : Float64(value))

    return nothing
end

MOI.supports(
    ::Optimizer,
    ::Union{MOI.AbsoluteGapTolerance,raw_attr"moi/absolutegaptolerance"},
) = true

QUBODrivers.default_raw_attr(::Optimizer, ::raw_attr"moi/absolutegaptolerance") = nothing

function MOI.get(sampler::Optimizer, ::MOI.AbsoluteGapTolerance)
    return MOI.get(sampler, RawSamplerAttribute("moi/absolutegaptolerance"))
end

function MOI.set(sampler::Optimizer, ::MOI.AbsoluteGapTolerance, value)
    return MOI.set(sampler, RawSamplerAttribute("moi/absolutegaptolerance"), value)
end

function MOI.set(sampler::Optimizer, attr::raw_attr"moi/absolutegaptolerance", value)
    if !(isnothing(value) || (value isa Real && isfinite(value) && value >= zero(value)))
        error("Value for 'MOI.AbsoluteGapTolerance' must be a non-negative finite number, or 'nothing'")
    end

    QUBODrivers.set_raw_attr!(sampler, attr, isnothing(value) ? nothing : Float64(value))

    return nothing
end

function _solve_scope_signature(sampler::Optimizer{T})::UInt64 where {T}
    h = hash((
        objectid(QUBOTools.backend(sampler)),
        QUBOTools.sense(sampler),
        QUBOTools.domain(sampler),
        QUBOTools.scale(sampler),
        QUBOTools.offset(sampler),
        QUBOTools.variables(sampler),
        QUBODrivers._get_moi_variables(sampler),
    ))

    for item in QUBOTools.linear_terms(sampler)
        h = xor(h, hash((:linear, item)))
    end

    for item in QUBOTools.quadratic_terms(sampler)
        h = xor(h, hash((:quadratic, item)))
    end

    for (vi, fv) in QUBODrivers._get_fixed_variables(sampler)
        h = xor(h, hash((:fixed, vi, fv.value, fv.set_type)))
    end

    return h
end

function _clear_stale_solution!(
    sampler::Optimizer{T};
    termination_status::MOI.TerminationStatusCode = MOI.OTHER_ERROR,
    status::String = "error",
) where {T}
    QUBOTools.attach!(
        sampler,
        SampleSet{T,Int}(;
            metadata = Dict{String,Any}(
                "status"             => status,
                "termination_status" => termination_status,
                "primal_status"      => MOI.NO_SOLUTION,
                "result_count"       => 0,
                _SOLVE_SCOPE_KEY     => _solve_scope_signature(sampler),
            ),
            sense  = QUBOTools.sense(sampler),
            domain = QUBOTools.domain(sampler),
        ),
    )

    return nothing
end

function _active_solution(sampler::Optimizer{T}) where {T}
    ω = QUBOTools.solution(sampler)
    metadata = QUBOTools.metadata(ω)

    if haskey(metadata, _SOLVE_SCOPE_KEY) &&
       metadata[_SOLVE_SCOPE_KEY] != _solve_scope_signature(sampler)
        QUBOTools.attach!(
            sampler,
            SampleSet{T,Int}(;
                sense  = QUBOTools.sense(sampler),
                domain = QUBOTools.domain(sampler),
            ),
        )
        return QUBOTools.solution(sampler)
    end

    return ω
end

function _is_post_sample_transformed(metadata::AbstractDict)
    postprocess = get(metadata, "postprocess", nothing)
    callback = postprocess isa AbstractDict ? get(postprocess, "callback", nothing) : nothing
    return callback isa AbstractDict && get(callback, "transformed", false) === true
end

function _sync_post_optimize_metadata!(sampler::Optimizer{T}) where {T}
    ω = QUBOTools.solution(sampler)
    metadata = QUBOTools.metadata(ω)
    metadata[_SOLVE_SCOPE_KEY] = _solve_scope_signature(sampler)
    metadata["result_count"] = length(ω)
    metadata["primal_status"] = isempty(ω) ? MOI.NO_SOLUTION : MOI.FEASIBLE_POINT

    bound_meta = get(metadata, "bound", nothing)

    if isempty(ω)
        reads = get(metadata, "reads", nothing)
        if reads isa AbstractDict
            reads["final_number_of_reads"] = 0
        end
        delete!(metadata, "relative_gap")
        if bound_meta isa AbstractDict
            bound_meta["relative_gap"] = nothing
            bound_meta["relative_gap_definition"] = nothing
        end
        if get(metadata, "termination_status", nothing) in _SOLVED_TERMINATION_STATUSES
            metadata["termination_status"] = MOI.OTHER_ERROR
        end
    elseif _is_post_sample_transformed(metadata)
        delete!(metadata, "relative_gap")
        if bound_meta isa AbstractDict
            bound_meta["relative_gap"] = nothing
            bound_meta["relative_gap_definition"] = nothing
        end
        if get(metadata, "termination_status", nothing) === MOI.OPTIMAL
            metadata["termination_status"] = MOI.LOCALLY_SOLVED
        end
    end

    return nothing
end

function MOI.copy_to(sampler::Optimizer{T}, src::MOI.ModelLike) where {T}
    MOI.empty!(sampler)
    return invoke(MOI.copy_to, Tuple{QUBODrivers.AbstractSampler{T},MOI.ModelLike}, sampler, src)
end

function MOI.optimize!(sampler::Optimizer{T}) where {T}
    _clear_stale_solution!(sampler)
    QUBODrivers._sample!(sampler)
    _sync_post_optimize_metadata!(sampler)

    return nothing
end

function _require_mip_optimizer(sampler::Optimizer)
    optimizer = MOI.get(sampler, MIPOptimizer())

    if isnothing(optimizer)
        throw(
            ArgumentError(
                "MIPSampler requires a MIP optimizer factory. Set " *
                "`MIPSampler.MIPOptimizer()` to an MOI-compatible optimizer, " *
                "for example `HiGHS.Optimizer`, `GLPK.Optimizer`, or " *
                "`MOI.OptimizerWithAttributes(HiGHS.Optimizer, MOI.Silent() => true)`.",
            ),
        )
    end

    return optimizer
end

function _instantiate_backend(optimizer, ::Type{T}) where {T}
    try
        return MOI.instantiate(optimizer; with_bridge_type = T)
    catch err
        msg = sprint(showerror, err)

        throw(ArgumentError("Could not instantiate MIP optimizer factory: $msg"))
    end
end

function _supports_attribute(backend, attr)::Bool
    try
        return MOI.supports(backend, attr)
    catch
        return false
    end
end

function _has_sampler_attribute(sampler::Optimizer, raw_name::String)
    return haskey(sampler.attributes, Symbol(raw_name))
end

function _forward_attribute!(
    forwarded::Vector{String},
    backend,
    sampler::Optimizer,
    attr,
    raw_name::String,
    label::String;
    skip_nothing::Bool = false,
)
    _has_sampler_attribute(sampler, raw_name) || return nothing
    _supports_attribute(backend, attr) || return nothing

    value = MOI.get(sampler, attr)

    if skip_nothing && isnothing(value)
        return nothing
    end

    MOI.set(backend, attr, value)
    push!(forwarded, label)

    return nothing
end

function _forward_common_attributes!(backend, sampler::Optimizer)
    forwarded = String[]

    _forward_attribute!(
        forwarded,
        backend,
        sampler,
        MOI.TimeLimitSec(),
        "moi/timelimitsec",
        "MOI.TimeLimitSec";
        skip_nothing = true,
    )
    _forward_attribute!(
        forwarded,
        backend,
        sampler,
        MOI.NumberOfThreads(),
        "moi/numberofthreads",
        "MOI.NumberOfThreads",
    )
    _forward_attribute!(
        forwarded,
        backend,
        sampler,
        MOI.Silent(),
        "moi/silent",
        "MOI.Silent",
    )
    _forward_attribute!(
        forwarded,
        backend,
        sampler,
        MOI.RelativeGapTolerance(),
        "moi/relativegaptolerance",
        "MOI.RelativeGapTolerance";
        skip_nothing = true,
    )
    _forward_attribute!(
        forwarded,
        backend,
        sampler,
        MOI.AbsoluteGapTolerance(),
        "moi/absolutegaptolerance",
        "MOI.AbsoluteGapTolerance";
        skip_nothing = true,
    )

    return forwarded
end

_affine(::Type{T}, terms::Vector{SAT{T}}, constant::T = zero(T)) where {T} =
    SAF{T}(terms, constant)

function _add_binary_variable(backend)
    x = MOI.add_variable(backend)

    MOI.add_constraint(backend, x, MOI.ZeroOne())

    return x
end

function _add_product_variable!(
    objective_terms::Vector{SAT{T}},
    backend,
    x,
    i::Integer,
    j::Integer,
    coefficient::T,
) where {T}
    y = _add_binary_variable(backend)

    MOI.add_constraint(
        backend,
        _affine(
            T,
            SAT{T}[SAT{T}(one(T), y), SAT{T}(-one(T), x[i]), SAT{T}(-one(T), x[j])],
        ),
        MOI.GreaterThan(-one(T)),
    )
    MOI.add_constraint(
        backend,
        _affine(T, SAT{T}[SAT{T}(one(T), y), SAT{T}(-one(T), x[i])]),
        MOI.LessThan(zero(T)),
    )
    MOI.add_constraint(
        backend,
        _affine(T, SAT{T}[SAT{T}(one(T), y), SAT{T}(-one(T), x[j])]),
        MOI.LessThan(zero(T)),
    )

    push!(objective_terms, SAT{T}(coefficient, y))

    return y
end

function _build_mip_model!(backend, n::Integer, L, Q, α::T, β::T) where {T}
    x = [_add_binary_variable(backend) for _ in 1:n]
    objective_terms = SAT{T}[]

    for (i, value) in L
        coefficient = convert(T, α * value)

        if !iszero(coefficient)
            push!(objective_terms, SAT{T}(coefficient, x[i]))
        end
    end

    for ((i, j), value) in Q
        coefficient = convert(T, α * value)

        if iszero(coefficient)
            continue
        elseif i == j
            push!(objective_terms, SAT{T}(coefficient, x[i]))
        else
            _add_product_variable!(objective_terms, backend, x, i, j, coefficient)
        end
    end

    MOI.set(backend, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(
        backend,
        MOI.ObjectiveFunction{SAF{T}}(),
        _affine(T, objective_terms, convert(T, α * β)),
    )

    return x
end

function _has_primal_solution(status)
    return status == MOI.FEASIBLE_POINT || status == MOI.NEARLY_FEASIBLE_POINT
end

function _validate_termination_and_primal_status(
    termination_status::MOI.TerminationStatusCode,
    primal_status::MOI.ResultStatusCode,
)
    if termination_status in _SOLVED_TERMINATION_STATUSES
        _has_primal_solution(primal_status) || error(
            "MIP backend reported $(termination_status) without a feasible primal solution " *
            "(primal_status = $(primal_status))",
        )
        return true
    elseif termination_status in _LIMIT_TERMINATION_STATUSES
        if _has_primal_solution(primal_status)
            return true
        elseif primal_status == MOI.NO_SOLUTION
            return false
        else
            error(
                "MIP backend reported an invalid primal status on limit termination " *
                "(termination_status = $(termination_status), primal_status = $(primal_status))",
            )
        end
    else
        error(
            "MIP backend failed to solve the model " *
            "(termination_status = $(termination_status), primal_status = $(primal_status))",
        )
    end
end

function _solution_state(backend, x)
    state = Vector{Int}(undef, length(x))

    for (idx, xi) in enumerate(x)
        val = MOI.get(backend, MOI.VariablePrimal(), xi)
        if !(val isa Real && isfinite(val) && -0.5 <= val <= 1.5)
            error("MIP backend returned an invalid binary variable primal value: $(val)")
        end
        state[idx] = val >= 0.5 ? 1 : 0
    end

    return state
end

function _backend_attribute(backend, attr)
    try
        return MOI.get(backend, attr)
    catch
        return nothing
    end
end

function _extract_raw_min_bound(backend, n::Integer, ::Type{T})::Union{Nothing,T} where {T}
    raw_val = _backend_attribute(backend, MOI.ObjectiveBound())

    if isnothing(raw_val)
        return nothing
    elseif !(raw_val isa Real)
        error("MIP backend returned a non-numeric objective bound: $(raw_val)")
    elseif isnan(raw_val) || raw_val == Inf
        error("MIP backend reported an invalid minimization objective bound: $(raw_val)")
    elseif raw_val == -Inf
        if n == 0 && _backend_attribute(backend, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            dual_val = _backend_attribute(backend, MOI.DualObjectiveValue())
            if dual_val isa Real && isfinite(dual_val)
                b = convert(T, dual_val)
                return iszero(b) ? zero(T) : b
            end
        end
        return nothing
    else
        b = convert(T, raw_val)
        return iszero(b) ? zero(T) : b
    end
end

function _validate_bound_against_incumbent(raw_bound::T, λ_min::T) where {T}
    FT = float(T)
    b = FT(raw_bound)
    v = FT(λ_min)
    tol = max(FT(1e-5), sqrt(eps(FT))) * max(one(FT), abs(v), abs(b))

    if b > v + tol
        error(
            "MIP backend reported an inconsistent minimization objective bound " *
            "($(raw_bound)) exceeding the evaluated feasible objective ($(λ_min))",
        )
    end

    return nothing
end

function _translate_objective_bound(::Type{T}, raw_bound::T, sense::QUBOTools.Sense) where {T}
    bound = sense === QUBOTools.Min ? raw_bound : -raw_bound
    return iszero(bound) ? zero(T) : bound
end

function _extract_relative_gap(
    backend,
    has_incumbent::Bool,
    has_bound::Bool,
    ::Type{T},
)::Union{Nothing,T} where {T}
    has_incumbent || return nothing

    raw_gap = _backend_attribute(backend, MOI.RelativeGap())
    isnothing(raw_gap) && return nothing

    if !(raw_gap isa Real)
        error("MIP backend returned a non-numeric relative gap: $(raw_gap)")
    elseif isnan(raw_gap) || raw_gap < -1e-5
        error("MIP backend reported an invalid relative gap: $(raw_gap)")
    elseif !has_bound || !isfinite(raw_gap)
        return nothing
    end

    clamped = max(zero(raw_gap), raw_gap)
    gap = convert(T, clamped)
    return iszero(gap) ? zero(T) : gap
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    _clear_stale_solution!(sampler)
    optimizer = _require_mip_optimizer(sampler)
    n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min, domain = :bool)

    build_results = @timed begin
        backend = _instantiate_backend(optimizer, T)
        forwarded_attributes = _forward_common_attributes!(backend, sampler)
        x = _build_mip_model!(backend, n, L, Q, α, β)

        (backend, x, forwarded_attributes)
    end
    backend, x, forwarded_attributes = build_results.value

    solve_results = @timed MOI.optimize!(backend)
    termination_status = MOI.get(backend, MOI.TerminationStatus())
    primal_status = MOI.get(backend, MOI.PrimalStatus())

    has_incumbent = try
        _validate_termination_and_primal_status(termination_status, primal_status)
    catch err
        failed_status =
            termination_status in (_SOLVED_TERMINATION_STATUSES..., _LIMIT_TERMINATION_STATUSES...) ?
            MOI.OTHER_ERROR : termination_status
        _clear_stale_solution!(
            sampler;
            termination_status = failed_status,
            status             = string(termination_status),
        )
        rethrow(err)
    end

    samples = Sample{T,Int}[]
    λ_min = nothing

    try
        if has_incumbent
            raw_obj = _backend_attribute(backend, MOI.ObjectiveValue())
            if !isnothing(raw_obj) && !(raw_obj isa Real && isfinite(raw_obj))
                error("MIP backend reported a non-finite objective value: $(raw_obj)")
            end

            ψ = _solution_state(backend, x)
            λ = QUBOTools.value(ψ, L, Q, α, β)
            isfinite(λ) || error("Evaluated QUBO objective is non-finite: $(λ)")
            λ_min = λ
            push!(samples, Sample{T,Int}(ψ, λ))
        end

        raw_bound = _extract_raw_min_bound(backend, n, T)
        if !isnothing(raw_bound) && !isnothing(λ_min)
            _validate_bound_against_incumbent(raw_bound, λ_min)
        end

        caller_sense = QUBOTools.sense(sampler)
        objective_bound =
            isnothing(raw_bound) ? nothing : _translate_objective_bound(T, raw_bound, caller_sense)
        relative_gap =
            _extract_relative_gap(backend, has_incumbent, !isnothing(objective_bound), T)

        emitted_reads = has_incumbent ? 1 : 0
        metadata = QUBODrivers._sampler_metadata(
            origin                = "MIP Sampler @ QUBODrivers.jl",
            algorithm_name        = "MIP Sampler",
            backend_name          = _backend_attribute(backend, MOI.SolverName()),
            backend_version       = _backend_attribute(backend, MOI.SolverVersion()),
            execution_mode        = "mip_solve",
            optimizer_evaluations = emitted_reads,
            number_of_reads       = emitted_reads,
            final_number_of_reads = emitted_reads,
            status                = string(termination_status),
            termination_status    = termination_status,
        )
        metadata["time"] = Dict{String,Any}(
            "build"     => build_results.time,
            "effective" => solve_results.time,
        )
        metadata["primal_status"] = has_incumbent ? MOI.FEASIBLE_POINT : MOI.NO_SOLUTION
        metadata["backend_primal_status"] = primal_status
        metadata["result_count"] = emitted_reads
        metadata["attributes"] = Dict{String,Any}("forwarded" => forwarded_attributes)

        rel_gap_tol = _backend_attribute(backend, MOI.RelativeGapTolerance())
        if isnothing(rel_gap_tol)
            rel_gap_tol = MOI.get(sampler, MOI.RelativeGapTolerance())
        end
        abs_gap_tol = _backend_attribute(backend, MOI.AbsoluteGapTolerance())
        if isnothing(abs_gap_tol)
            abs_gap_tol = MOI.get(sampler, MOI.AbsoluteGapTolerance())
        end

        fixed_count = length(QUBODrivers._get_fixed_variables(sampler))
        metadata["bound"] = Dict{String,Any}(
            "value"                   => objective_bound,
            "raw_mip_min_bound"       => raw_bound,
            "sense"                   => String(caller_sense),
            "domain"                  => String(QUBOTools.domain(sampler)),
            "scope"                   => iszero(fixed_count) ?
                                         "supplied_qubo" :
                                         "supplied_qubo_conditioned_on_fixed_variables",
            "fixed_variables"         => fixed_count,
            "provenance"              => "backend_reported_tolerance_dependent",
            "certified_exact"         => false,
            "relative_gap"            => relative_gap,
            "relative_gap_definition" => isnothing(relative_gap) ? nothing : "backend_solver_dependent",
            "relative_gap_tolerance"  => rel_gap_tol,
            "absolute_gap_tolerance"  => abs_gap_tol,
        )

        if !isnothing(objective_bound)
            metadata["objective_bound"] = objective_bound
        end
        if !isnothing(relative_gap)
            metadata["relative_gap"] = relative_gap
        end

        metadata[_SOLVE_SCOPE_KEY] = _solve_scope_signature(sampler)

        return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
    catch err
        _clear_stale_solution!(
            sampler;
            termination_status = MOI.NUMERICAL_ERROR,
            status             = "NUMERICAL_ERROR",
        )
        rethrow(err)
    end
end

function MOI.get(sampler::Optimizer{T}, ::MOI.ResultCount) where {T}
    return length(_active_solution(sampler))
end

function MOI.get(sampler::Optimizer{T}, ::MOI.RawStatusString) where {T}
    _active_solution(sampler)
    return invoke(MOI.get, Tuple{QUBODrivers.AbstractSampler{T},MOI.RawStatusString}, sampler, MOI.RawStatusString())
end

function MOI.get(sampler::Optimizer{T}, ::MOI.SolveTimeSec) where {T}
    _active_solution(sampler)
    return invoke(MOI.get, Tuple{QUBODrivers.AbstractSampler{T},MOI.SolveTimeSec}, sampler, MOI.SolveTimeSec())
end

function MOI.get(sampler::Optimizer{T}, nr::QUBODrivers.QUBOTools_MOI.NumberOfReads) where {T}
    _active_solution(sampler)
    return invoke(
        MOI.get,
        Tuple{QUBODrivers.AbstractSampler{T},QUBODrivers.QUBOTools_MOI.NumberOfReads},
        sampler,
        nr,
    )
end

function MOI.get(sampler::Optimizer{T}, ps::MOI.PrimalStatus) where {T}
    _active_solution(sampler)
    return invoke(MOI.get, Tuple{QUBODrivers.AbstractSampler{T},MOI.PrimalStatus}, sampler, ps)
end

function MOI.get(sampler::Optimizer{T}, ov::MOI.ObjectiveValue) where {T}
    _active_solution(sampler)
    return invoke(MOI.get, Tuple{QUBODrivers.AbstractSampler{T},MOI.ObjectiveValue}, sampler, ov)
end

function MOI.get(sampler::Optimizer{T}, vp::MOI.VariablePrimal, vi::VI) where {T}
    _active_solution(sampler)
    return invoke(
        MOI.get,
        Tuple{QUBODrivers.AbstractSampler{T},MOI.VariablePrimal,VI},
        sampler,
        vp,
        vi,
    )
end

function MOI.get(sampler::Optimizer{T}, attr::MOI.ObjectiveBound) where {T}
    ω = _active_solution(sampler)
    metadata = QUBOTools.metadata(ω)
    bound = get(metadata, "objective_bound", nothing)

    if bound isa Real && isfinite(bound)
        return convert(T, bound)
    end

    throw(
        MOI.GetAttributeNotAllowed(
            attr,
            "MIP objective bound is not available for the current solve state.",
        ),
    )
end

function MOI.get(sampler::Optimizer{T}, attr::MOI.RelativeGap) where {T}
    ω = _active_solution(sampler)
    metadata = QUBOTools.metadata(ω)
    gap = !isempty(ω) ? get(metadata, "relative_gap", nothing) : nothing

    if gap isa Real && isfinite(gap)
        return convert(T, gap)
    end

    throw(
        MOI.GetAttributeNotAllowed(
            attr,
            "MIP relative gap is not available for the current solve state.",
        ),
    )
end

function MOI.get(sampler::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    ω = _active_solution(sampler)
    metadata = QUBOTools.metadata(ω)
    status = get(metadata, "termination_status", nothing)

    if status isa MOI.TerminationStatusCode
        if isempty(ω) && status in _SOLVED_TERMINATION_STATUSES
            return MOI.OTHER_ERROR
        elseif !isempty(ω) && status === MOI.OPTIMAL && _is_post_sample_transformed(metadata)
            return MOI.LOCALLY_SOLVED
        end
        return status
    elseif isempty(ω)
        return isempty(metadata) ? MOI.OPTIMIZE_NOT_CALLED : MOI.OTHER_ERROR
    else
        return MOI.LOCALLY_SOLVED
    end
end

end # module
