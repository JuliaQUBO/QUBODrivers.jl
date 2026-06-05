module MIPSampler

import QUBOTools
import QUBODrivers
import QUBODrivers: MOI, Sample, SampleSet

const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}

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

Only one best incumbent sample is returned.
`MIPSampler` ignores `QUBODrivers.FinalNumberOfReads`.

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

@doc raw"""
    MIPOptimizer()

Optimizer attribute that stores the MOI-compatible MIP backend factory used by
[`MIPSampler.Optimizer`](@ref).
"""
MIPOptimizer

const _RawMIPOptimizer = QUBODrivers.RawSamplerAttribute{Symbol("mip_optimizer")}

MOI.Utilities.map_indices(_, ::MIPOptimizer, value) = value
MOI.Utilities.map_indices(_, ::_RawMIPOptimizer, value) = value

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

function _solution_state(backend, x)
    return Int[MOI.get(backend, MOI.VariablePrimal(), xi) >= 0.5 ? 1 : 0 for xi in x]
end

function _backend_attribute(backend, attr)
    try
        return MOI.get(backend, attr)
    catch
        return nothing
    end
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
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

    if !_has_primal_solution(primal_status)
        error(
            "MIP backend did not return a feasible primal solution " *
            "(termination_status = $(termination_status), primal_status = $(primal_status))",
        )
    end

    ψ = _solution_state(backend, x)
    λ = QUBOTools.value(ψ, L, Q, α, β)
    sample = Sample{T,Int}(ψ, λ)

    metadata = QUBODrivers._sampler_metadata(
        origin                = "MIP Sampler @ QUBODrivers.jl",
        algorithm_name        = "MIP Sampler",
        backend_name          = _backend_attribute(backend, MOI.SolverName()),
        backend_version       = _backend_attribute(backend, MOI.SolverVersion()),
        execution_mode        = "mip_solve",
        optimizer_evaluations = 1,
        final_number_of_reads = 1,
        status                = string(termination_status),
        termination_status    = termination_status,
    )
    metadata["time"] = Dict{String,Any}(
        "build"     => build_results.time,
        "effective" => solve_results.time,
    )
    metadata["primal_status"] = primal_status
    metadata["attributes"] = Dict{String,Any}("forwarded" => forwarded_attributes)

    return SampleSet{T}([sample], metadata; sense = :min, domain = :bool)
end

function MOI.get(sampler::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    ω = QUBOTools.solution(sampler)
    metadata = QUBOTools.metadata(ω)
    status = get(metadata, "termination_status", nothing)

    if status isa MOI.TerminationStatusCode
        return status
    elseif isempty(ω)
        return isempty(metadata) ? MOI.OPTIMIZE_NOT_CALLED : MOI.OTHER_ERROR
    else
        return MOI.LOCALLY_SOLVED
    end
end

end # module
