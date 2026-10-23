# ~ Currently, all models in this context are unconstrained by definition.
MOI.supports_constraint(
    ::AbstractSampler,
    ::Type{<:MOI.AbstractFunction},
    ::Type{<:MOI.AbstractSet},
) = false

# ~ Variable domain constraints (consult `supported_domains`)
MOI.supports_constraint(
    sampler::AbstractSampler{T},
    ::Type{VI},
    ::Type{MOI.ZeroOne},
) where {T} = supports_domain(sampler, :bool)

MOI.supports_constraint(
    sampler::AbstractSampler{T},
    ::Type{VI},
    ::Type{Spin},
) where {T} = supports_domain(sampler, :spin)

MOI.supports_constraint(
    sampler::AbstractSampler{T},
    ::Type{VI},
    ::Type{MOI.Integer},
) where {T} = _supports_nonbinary_domains(sampler)

MOI.supports_constraint(
    sampler::AbstractSampler{T},
    ::Type{VI},
    ::Type{<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}},
) where {T} = _supports_nonbinary_domains(sampler)

# ~ Support for fixing variables to specific values
MOI.supports_constraint(::AbstractSampler{T}, ::Type{VI}, ::Type{MOI.EqualTo{S}}) where {T,S<:Real} = true

# ~ Variable Attribute Support
MOI.supports(
    sampler::AbstractSampler,
    ::VariableEncodingSet,
    ::Type{VI},
) = supports_domain(sampler, :set)

function MOI.supports(
    sampler::AbstractSampler,
    attr::MOI.AbstractVariableAttribute,
    ::Type{VI},
)
    if _is_variable_encoding_set_attr(attr)
        return supports_domain(sampler, :set)
    end
    return false
end

# ~ Objective Function Support
MOI.supports(::AbstractSampler{T}, ::MOI.ObjectiveFunction{<:Any}) where {T} = false

MOI.supports(::AbstractSampler{T}, ::MOI.ObjectiveSense) where {T} = true

MOI.supports(
    ::AbstractSampler{T},
    ::MOI.ObjectiveFunction{<:Union{SQF{T},SAF{T},VI}},
) where {T} = true

MOI.supports(
    sampler::AbstractSampler{T},
    ::MOI.ObjectiveFunction{<:Union{MOI.ScalarNonlinearFunction,ScalarPolynomialFunction{T}}},
) where {T} = supports_polynomial_objective(sampler)

# By default, all samplers are their own raw solvers.
MOI.get(sampler::AbstractSampler{T}, ::MOI.RawSolver) where {T} = sampler

# Since problems are unconstrained, all available solutions are feasible.
function MOI.get(sampler::AbstractSampler{T}, ps::MOI.PrimalStatus) where {T}
    m = MOI.get(sampler, MOI.ResultCount())
    i = ps.result_index

    if 1 <= i <= m
        return MOI.FEASIBLE_POINT
    else
        return MOI.NO_SOLUTION
    end
end

# No constraints, no dual solutions
MOI.get(::AbstractSampler{T}, ::MOI.DualStatus) where {T} = MOI.NO_SOLUTION

const _MOI_VARIABLES_KEY = Symbol("QUBODrivers/moi_variables")
const _FIXED_VARIABLES_KEY = Symbol("QUBODrivers/fixed_variables")
const _POLYNOMIAL_OBJECTIVE_KEY = Symbol("QUBODrivers/polynomial_objective")
const _VARIABLE_DOMAINS_KEY = Symbol("QUBODrivers/variable_domains")
const _POLYNOMIAL_OBJECTIVE_FALLBACK = WeakKeyDict{AbstractSampler,Any}()
const _POLYNOMIAL_OBJECTIVE_LOCK = ReentrantLock()
const _VARIABLE_DOMAINS_FALLBACK = WeakKeyDict{AbstractSampler,Any}()
const _VARIABLE_DOMAINS_LOCK = ReentrantLock()
const _MAX_FINITE_DOMAIN_SIZE = 1_000_000

struct _FixedVariable{T}
    value::T
    int_value::Int
    set_type::DataType
end

function _FixedVariable{T}(value::T, set_type::DataType) where {T}
    return _FixedVariable{T}(value, round(Int, value), set_type)
end

struct _VariableDomain
    kind::Symbol
    values::Vector{Int}
    has_encoding_set::Bool
    has_integer_constraint::Bool
    lower_bound::Union{Nothing,Real}
    upper_bound::Union{Nothing,Real}
    bound_sets::Vector{MOI.AbstractScalarSet}
end

function _VariableDomain(
    kind::Symbol,
    values::Vector{Int},
    has_encoding_set::Bool,
    has_integer_constraint::Bool,
)
    return _VariableDomain(
        kind,
        values,
        has_encoding_set,
        has_integer_constraint,
        nothing,
        nothing,
        MOI.AbstractScalarSet[],
    )
end

struct _PolynomialObjective{T}
    polynomial::PolyType{T}
    variables::Vector{VI}
    sense::QUBOTools.Sense
    domain::Union{QUBOTools.Domain,Nothing}
    is_higher_order::Bool
    has_nonbinary_domains::Bool
end

function _is_exact_in(::Type{T}, val::Real)::Bool where {T<:Real}
    isnan(val) && return false
    if !isfinite(val)
        return T <: AbstractFloat
    end
    tval = try
        convert(T, val)
    catch
        return false
    end
    isfinite(tval) || return false
    if val isa Integer && T <: Integer
        return BigInt(tval) == BigInt(val)
    elseif val isa Integer || isinteger(val)
        return isinteger(tval) && BigInt(tval) == BigInt(val)
    else
        return Rational{BigInt}(tval) == Rational{BigInt}(val)
    end
end

function _convert_exact(
    ::Type{T},
    val::Real,
    context::AbstractString = "discrete value",
)::T where {T<:Real}
    if !_is_exact_in(T, val)
        throw(
            ArgumentError(
                "Value '$val' ($context) cannot be represented exactly in type $T.",
            ),
        )
    end
    return convert(T, val)
end

function _promote_state_for_polynomial_eval(::Type{T}, val::Real) where {T<:Real}
    if _is_exact_in(T, val)
        return val
    elseif _is_exact_in(Float64, val)
        return Float64(val)
    elseif val isa Integer
        return BigInt(val)
    else
        return BigFloat(val)
    end
end

_fixed_value(fixed_variables::AbstractDict{VI,T}, vi::VI) where {T<:Real} = fixed_variables[vi]
_fixed_value(fixed_variables::AbstractDict{VI,_FixedVariable{T}}, vi::VI) where {T} =
    _convert_exact(T, fixed_variables[vi].int_value, "fixed value for variable '$vi'")


# ~*~ :: MathOptInterface :: ~*~ #
function MOI.empty!(sampler::AbstractSampler{T}) where {T}
    QUBODrivers.set_model!(sampler, QUBOTools.Model{VI,T,Int}())
    _store_moi_variables!(sampler, VI[])
    _store_fixed_variables!(sampler, Dict{VI,_FixedVariable{T}}())
    _store_polynomial_objective!(sampler, nothing)
    _store_variable_domains!(sampler, Dict{VI,_VariableDomain}())

    return sampler
end

function MOI.is_empty(sampler::AbstractSampler{T}) where {T}
    return isempty(_get_moi_variables(sampler)) &&
           isempty(QUBOTools.solution(sampler)) &&
           iszero(QUBOTools.offset(sampler)) &&
           QUBOTools.sense(sampler) === QUBOTools.Min &&
           isnothing(_get_polynomial_objective(sampler))
end

function MOI.optimize!(sampler::AbstractSampler{T}) where {T}
    return _sample!(sampler)
end

function MOI.copy_to(sampler::AbstractSampler{T}, src::MOI.ModelLike) where {T}
    variables = collect(MOI.get(src, MOI.ListOfVariableIndices()))
    fixed_variables, var_domains, has_nonbinary_domains =
        _collect_variable_domains_and_fixed(T, sampler, src, variables)

    _store_moi_variables!(sampler, variables)
    _store_fixed_variables!(sampler, fixed_variables)
    _store_variable_domains!(sampler, var_domains)

    if supports_polynomial_objective(sampler) ||
       _supports_nonbinary_domains(sampler) ||
       has_nonbinary_domains
        model, poly_obj = _build_polynomial_sampler_model(
            T,
            src,
            variables,
            fixed_variables,
            var_domains;
            allow_polynomial_objective = supports_polynomial_objective(sampler),
            has_nonbinary_domains      = has_nonbinary_domains,
        )
        QUBODrivers.set_model!(sampler, model)
        _store_polynomial_objective!(sampler, poly_obj)
    else
        _store_polynomial_objective!(sampler, nothing)
        model = (isempty(fixed_variables) && (!isempty(variables) || MOI.is_empty(src))) ?
            QUBOTools.Model{T}(src) :
            _build_model_with_fixed_variables(T, src, variables, fixed_variables)
        QUBODrivers.set_model!(sampler, model)
    end

    # VariablePrimalStart is advisory; tolerate source models that reject it.
    if MOI.supports(src, MOI.VariablePrimalStart(), VI)
        try
            for v in variables
                if haskey(fixed_variables, v)
                    continue
                end

                x = MOI.get(src, MOI.VariablePrimalStart(), v)

                MOI.set(sampler, MOI.VariablePrimalStart(), v, x)
            end
        catch err
            if !(
                err isa Union{
                    MOI.GetAttributeNotAllowed{MOI.VariablePrimalStart},
                    MOI.UnsupportedAttribute{MOI.VariablePrimalStart},
                }
            )
                rethrow()
            end
        end
    end

    return _build_variable_constraint_index_map(src)
end

function _build_variable_constraint_index_map(src::MOI.ModelLike)
    idx_map = MOIU.IndexMap()
    for x in MOI.get(src, MOI.ListOfVariableIndices())
        idx_map[x] = x
    end
    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        for c in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            if F === VI
                vi = MOI.get(src, MOI.ConstraintFunction(), c)
                idx_map[c] = MOI.ConstraintIndex{VI,S}(vi.value)
            else
                idx_map[c] = c
            end
        end
    end
    return idx_map
end

function _store_moi_variables!(sampler::AbstractSampler, variables::Vector{VI})
    if hasfield(typeof(sampler), :moi_variables)
        sampler.moi_variables = variables
    elseif hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[_MOI_VARIABLES_KEY] = variables
    end

    return nothing
end

function _get_moi_variables(sampler::AbstractSampler)
    if hasfield(typeof(sampler), :moi_variables)
        return sampler.moi_variables::Vector{VI}
    elseif hasfield(typeof(sampler), :attributes) &&
       isa(sampler.attributes, Dict) &&
       haskey(sampler.attributes, _MOI_VARIABLES_KEY)
        return sampler.attributes[_MOI_VARIABLES_KEY]::Vector{VI}
    end

    return Vector{VI}(QUBOTools.variables(sampler))
end

function _store_fixed_variables!(
    sampler::AbstractSampler{T},
    fixed_variables::Dict{VI,_FixedVariable{T}},
) where {T}
    if hasfield(typeof(sampler), :fixed_variables)
        sampler.fixed_variables = fixed_variables
    elseif hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[_FIXED_VARIABLES_KEY] = fixed_variables
    end
    return nothing
end

# Helper function to retrieve fixed variables from sampler
function _get_fixed_variables(sampler::AbstractSampler{T}) where {T}
    if hasfield(typeof(sampler), :fixed_variables)
        return sampler.fixed_variables::Dict{VI,_FixedVariable{T}}
    elseif hasfield(typeof(sampler), :attributes) &&
       isa(sampler.attributes, Dict) &&
       haskey(sampler.attributes, _FIXED_VARIABLES_KEY)
        return sampler.attributes[_FIXED_VARIABLES_KEY]::Dict{VI,_FixedVariable{T}}
    end

    return Dict{VI,_FixedVariable{T}}()
end

function _store_polynomial_objective!(
    sampler::AbstractSampler{T},
    poly_obj::Union{Nothing,_PolynomialObjective{T}},
) where {T}
    if hasfield(typeof(sampler), :polynomial_objective)
        sampler.polynomial_objective = poly_obj
    elseif hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[_POLYNOMIAL_OBJECTIVE_KEY] = poly_obj
    else
        @lock _POLYNOMIAL_OBJECTIVE_LOCK begin
            if isnothing(poly_obj)
                delete!(_POLYNOMIAL_OBJECTIVE_FALLBACK, sampler)
            else
                _POLYNOMIAL_OBJECTIVE_FALLBACK[sampler] = poly_obj
            end
        end
    end

    return nothing
end

function _get_polynomial_objective(
    sampler::AbstractSampler{T},
)::Union{Nothing,_PolynomialObjective{T}} where {T}
    if hasfield(typeof(sampler), :polynomial_objective)
        return sampler.polynomial_objective::Union{Nothing,_PolynomialObjective{T}}
    elseif hasfield(typeof(sampler), :attributes) &&
       isa(sampler.attributes, Dict) &&
       haskey(sampler.attributes, _POLYNOMIAL_OBJECTIVE_KEY)
        return sampler.attributes[_POLYNOMIAL_OBJECTIVE_KEY]::Union{Nothing,_PolynomialObjective{T}}
    end

    return @lock _POLYNOMIAL_OBJECTIVE_LOCK begin
        get(_POLYNOMIAL_OBJECTIVE_FALLBACK, sampler, nothing)::Union{Nothing,_PolynomialObjective{T}}
    end
end

function _store_variable_domains!(
    sampler::AbstractSampler,
    var_domains::Dict{VI,_VariableDomain},
)
    if hasfield(typeof(sampler), :variable_domains)
        sampler.variable_domains = var_domains
    elseif hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[_VARIABLE_DOMAINS_KEY] = var_domains
    else
        @lock _VARIABLE_DOMAINS_LOCK begin
            if isempty(var_domains)
                delete!(_VARIABLE_DOMAINS_FALLBACK, sampler)
            else
                _VARIABLE_DOMAINS_FALLBACK[sampler] = var_domains
            end
        end
    end

    return nothing
end

function _get_variable_domains(sampler::AbstractSampler)::Dict{VI,_VariableDomain}
    if hasfield(typeof(sampler), :variable_domains)
        return sampler.variable_domains::Dict{VI,_VariableDomain}
    elseif hasfield(typeof(sampler), :attributes) &&
           isa(sampler.attributes, Dict) &&
           haskey(sampler.attributes, _VARIABLE_DOMAINS_KEY)
        return sampler.attributes[_VARIABLE_DOMAINS_KEY]::Dict{VI,_VariableDomain}
    end

    return @lock _VARIABLE_DOMAINS_LOCK begin
        get(_VARIABLE_DOMAINS_FALLBACK, sampler, Dict{VI,_VariableDomain}())::Dict{VI,_VariableDomain}
    end
end

function _fallback_variable_domain(sampler::AbstractSampler)::_VariableDomain
    if QUBOTools.domain(sampler) === QUBOTools.SpinDomain
        return _VariableDomain(:spin, [-1, 1], false, false)
    else
        return _VariableDomain(:bool, [0, 1], false, false)
    end
end

function _variable_domain_record(sampler::AbstractSampler, vi::VI)::_VariableDomain
    vds = _get_variable_domains(sampler)
    if haskey(vds, vi)
        return vds[vi]
    elseif vi in _get_moi_variables(sampler) || QUBOTools.hasvariable(sampler, vi)
        return _fallback_variable_domain(sampler)
    else
        throw(ArgumentError("Variable '$vi' is not present in the sampler model."))
    end
end

function _has_higher_order_polynomial_objective(sampler::AbstractSampler)
    poly_obj = _get_polynomial_objective(sampler)
    return !isnothing(poly_obj) && poly_obj.is_higher_order
end

function _has_nonbinary_or_heterogeneous_domains(sampler::AbstractSampler)
    poly_obj = _get_polynomial_objective(sampler)
    if !isnothing(poly_obj) && poly_obj.has_nonbinary_domains
        return true
    end
    vds = _get_variable_domains(sampler)
    isempty(vds) && return false
    kinds = Set(vd.kind for vd in values(vds))
    return (:int in kinds) || (:set in kinds) || length(kinds) > 1
end

function _polynomial_objective_degree(sampler::AbstractSampler)
    poly_obj = _get_polynomial_objective(sampler)
    return isnothing(poly_obj) ? 0 : MP.maxdegree(poly_obj.polynomial)
end

@doc raw"""
    variable_domain(sampler::AbstractSampler, vi::MOI.VariableIndex)::Vector{Int}

Return the ordered finite integer domain `U_i ⊆ ℤ` for variable `vi`.
"""
function variable_domain(sampler::AbstractSampler, vi::VI)::Vector{Int}
    return copy(_variable_domain_record(sampler, vi).values)
end

@doc raw"""
    variable_domains(sampler::AbstractSampler)::Vector{Vector{Int}}

Return the ordered finite integer domains `[U_1, …, U_n]` for all free variables
of `sampler` in `QUBOTools.variables(sampler)` order.
"""
function variable_domains(sampler::AbstractSampler)::Vector{Vector{Int}}
    return Vector{Int}[
        variable_domain(sampler, vi) for vi in QUBOTools.variables(sampler)
    ]
end

@doc raw"""
    variable_bounds(sampler::AbstractSampler, vi::MOI.VariableIndex)::Tuple{Int,Int}

Return the `(lower, upper)` integer bounds `(minimum(U_i), maximum(U_i))` for
variable `vi`.
"""
function variable_bounds(sampler::AbstractSampler, vi::VI)::Tuple{Int,Int}
    vals = _variable_domain_record(sampler, vi).values
    return (minimum(vals), maximum(vals))
end

@doc raw"""
    variable_bounds(sampler::AbstractSampler)::Vector{Tuple{Int,Int}}

Return the `(lower, upper)` integer bounds for all free variables of `sampler`
in `QUBOTools.variables(sampler)` order.
"""
function variable_bounds(sampler::AbstractSampler)::Vector{Tuple{Int,Int}}
    return Tuple{Int,Int}[
        variable_bounds(sampler, vi) for vi in QUBOTools.variables(sampler)
    ]
end

@doc raw"""
    variable_num_levels(sampler::AbstractSampler, vi::MOI.VariableIndex)::Int

Return the number of discrete levels `length(U_i)` in the finite domain of
variable `vi`.
"""
function variable_num_levels(sampler::AbstractSampler, vi::VI)::Int
    return length(_variable_domain_record(sampler, vi).values)
end

@doc raw"""
    variable_num_levels(sampler::AbstractSampler)::Vector{Int}

Return the number of discrete levels for each free variable of `sampler` in
`QUBOTools.variables(sampler)` order.
"""
function variable_num_levels(sampler::AbstractSampler)::Vector{Int}
    return Int[
        variable_num_levels(sampler, vi) for vi in QUBOTools.variables(sampler)
    ]
end

@doc raw"""
    levels_to_values(sampler::AbstractSampler, vi::MOI.VariableIndex, level::Integer)::Int
    levels_to_values(sampler::AbstractSampler, levels::AbstractVector{<:Integer})::Vector{Int}

Map zero-based level indices `k_i ∈ 0:(d_i - 1)` to variable domain values
`U_i[k_i + 1]`.
"""
function levels_to_values(sampler::AbstractSampler, vi::VI, level::Integer)::Int
    vals = _variable_domain_record(sampler, vi).values
    if !(0 <= level < length(vals))
        throw(
            ArgumentError(
                "Level $level for variable '$vi' is out of range 0:$(length(vals) - 1).",
            ),
        )
    end
    return vals[level + 1]
end

function levels_to_values(
    sampler::AbstractSampler,
    levels::AbstractVector{<:Integer},
)::Vector{Int}
    free_vars = QUBOTools.variables(sampler)
    n = length(free_vars)
    if length(levels) != n
        throw(
            DimensionMismatch(
                "Level vector length $(length(levels)) does not match model dimension $n.",
            ),
        )
    end
    return Int[levels_to_values(sampler, free_vars[i], levels[i]) for i in 1:n]
end

@doc raw"""
    values_to_levels(sampler::AbstractSampler, vi::MOI.VariableIndex, value::Real)::Int
    values_to_levels(sampler::AbstractSampler, values::AbstractVector{<:Real})::Vector{Int}

Invert variable domain values `v_i ∈ U_i` back to zero-based level indices
`k_i ∈ 0:(d_i - 1)`.
"""
function values_to_levels(sampler::AbstractSampler, vi::VI, value::Real)::Int
    vals = _variable_domain_record(sampler, vi).values
    if !(isfinite(value) && isinteger(value))
        throw(
            ArgumentError(
                "Value $value for variable '$vi' is not in domain $vals.",
            ),
        )
    end
    idx = findfirst(==(value), vals)
    if isnothing(idx)
        throw(
            ArgumentError(
                "Value $value for variable '$vi' is not in domain $vals.",
            ),
        )
    end
    return idx - 1
end

function values_to_levels(
    sampler::AbstractSampler,
    values::AbstractVector{<:Real},
)::Vector{Int}
    free_vars = QUBOTools.variables(sampler)
    n = length(free_vars)
    if length(values) != n
        throw(
            DimensionMismatch(
                "Value vector length $(length(values)) does not match model dimension $n.",
            ),
        )
    end
    return Int[values_to_levels(sampler, free_vars[i], values[i]) for i in 1:n]
end

@doc raw"""
    polynomial_objective(
        sampler::AbstractSampler{T};
        sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
        domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
        shift::Bool = false,
    )::MP.AbstractPolynomial{T} where {T}

Return the objective polynomial stored on an opted-in `sampler` as a
`MultivariatePolynomials.AbstractPolynomial{T}` over the free variables in
`QUBOTools.variables(sampler)` order, preserving constant offset and fixed
variable reductions.

If `sense` (`:min` or `:max`) or `domain` (`:bool` or `:spin`) is provided, the
polynomial is cast to the requested optimization sense and variable domain.
When `shift = true`, contiguous unit-step integer domains `{l_i, …, u_i}` are
shifted via $x_i \mapsto y_i + l_i$ to zero-based level coordinates
$y_i \in \{0, \dots, u_i - l_i\}$.

Throws an `ArgumentError` if neither `supports_polynomial_objective(sampler)`
nor non-binary domain support is enabled on `sampler`.
"""
function polynomial_objective(
    sampler::AbstractSampler{T};
    sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
    domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
    shift::Bool = false,
) where {T}
    if !(supports_polynomial_objective(sampler) || _supports_nonbinary_domains(sampler))
        throw(
            ArgumentError(
                "Sampler `$(typeof(sampler))` does not opt into polynomial objectives or non-binary variable domains; " *
                "define `QUBODrivers.supports_polynomial_objective(::Type{<:$(typeof(sampler))}) = true` " *
                "or extend `QUBODrivers.supported_domains`.",
            ),
        )
    end

    poly_obj = _get_polynomial_objective(sampler)
    isnothing(poly_obj) && return zero(PolyType{T})

    p = poly_obj.polynomial
    vars = MP.variables(p)
    zero_anchor = sum(zero(T) * v for v in vars; init = zero(PolyType{T}))

    active_domains = variable_domains(sampler)

    if !isnothing(domain)
        if _has_nonbinary_or_heterogeneous_domains(sampler) || isnothing(poly_obj.domain)
            throw(
                ArgumentError(
                    "Cannot cast `polynomial_objective` to domain `$domain` when variables have non-binary or heterogeneous domains; " *
                    "use `shift = true` for zero-based level coordinates on contiguous integer domains.",
                ),
            )
        end
        target_domain = QUBOTools.domain(domain)
        if target_domain !== poly_obj.domain && !isempty(vars)
            if poly_obj.domain === QUBOTools.BoolDomain && target_domain === QUBOTools.SpinDomain
                subs_exprs = PolyType{T}[convert(PolyType{T}, (one(T) + v) / 2) for v in vars]
                p = convert(PolyType{T}, p(vars => subs_exprs)) + zero_anchor
                active_domains = Vector{Int}[[-1, 1] for _ in vars]
            elseif poly_obj.domain === QUBOTools.SpinDomain && target_domain === QUBOTools.BoolDomain
                subs_exprs = PolyType{T}[convert(PolyType{T}, 2 * v - one(T)) for v in vars]
                p = convert(PolyType{T}, p(vars => subs_exprs)) + zero_anchor
                active_domains = Vector{Int}[[0, 1] for _ in vars]
            end
        end
    end

    if shift && !isempty(vars)
        for i in eachindex(vars)
            u_i = active_domains[i]
            if !_is_contiguous_integer_domain(u_i)
                throw(
                    ArgumentError(
                        "Cannot shift `polynomial_objective` (`shift = true`) because variable " *
                        "'$(poly_obj.variables[i])' has non-contiguous domain $u_i; " *
                        "`shift = true` requires contiguous unit-step integer domains `{l_i, ..., u_i}`.",
                    ),
                )
            end
        end
        if any(u -> !iszero(first(u)), active_domains)
            subs_exprs = PolyType{T}[
                convert(
                    PolyType{T},
                    vars[i] + _convert_exact(
                        T,
                        first(active_domains[i]),
                        "lower bound shift for variable '$(poly_obj.variables[i])'",
                    ),
                )
                for i in eachindex(vars)
            ]
            p = convert(PolyType{T}, p(vars => subs_exprs)) + zero_anchor
        end
    end

    if !isnothing(sense)
        target_sense = QUBOTools.sense(sense)
        if target_sense !== poly_obj.sense
            p = -p + zero_anchor
        end
    end

    return p
end

function _is_contiguous_integer_domain(U::Vector{Int})::Bool
    isempty(U) && return false
    for k in 2:length(U)
        widemul(U[k], 1) - widemul(U[k - 1], 1) == 1 || return false
    end
    return true
end

function polynomial_function(
    sampler::AbstractSampler{T};
    sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
    domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
    shift::Bool = false,
) where {T}
    p = polynomial_objective(sampler; sense, domain, shift)
    poly_obj = _get_polynomial_objective(sampler)
    vars = isnothing(poly_obj) ? VI[] : copy(poly_obj.variables)
    return ScalarPolynomialFunction{T,typeof(p)}(p, vars)
end

function _fixed_constraint_variables(sampler::AbstractSampler{T}, ::Type{S}) where {T,S<:Real}
    fixed_variables = _get_fixed_variables(sampler)

    return [
        vi for vi in _get_moi_variables(sampler) if
        haskey(fixed_variables, vi) && fixed_variables[vi].set_type == S
    ]
end

function _fixed_constraint_variable(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    fixed_constraint_variables = _fixed_constraint_variables(sampler, S)
    vi = VI(ci.value)

    if !(vi in fixed_constraint_variables)
        error("Invalid constraint index '$(ci.value)'; There are $(length(fixed_constraint_variables)) constraints")
    end

    return vi
end

function _domain_constraint_variables(sampler::AbstractSampler, kind::Symbol)
    vds = _get_variable_domains(sampler)
    vars = _get_moi_variables(sampler)
    if !isempty(vds)
        return VI[vi for vi in vars if haskey(vds, vi) && vds[vi].kind === kind]
    elseif kind === :bool && QUBOTools.domain(sampler) === QUBOTools.BoolDomain
        return copy(vars)
    elseif kind === :spin && QUBOTools.domain(sampler) === QUBOTools.SpinDomain
        return copy(vars)
    else
        return VI[]
    end
end

function _integer_constraint_variables(sampler::AbstractSampler)
    vds = _get_variable_domains(sampler)
    vars = _get_moi_variables(sampler)
    return VI[vi for vi in vars if haskey(vds, vi) && vds[vi].has_integer_constraint]
end

function _bound_constraint_variables(
    sampler::AbstractSampler,
    ::Type{B},
) where {B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    vds = _get_variable_domains(sampler)
    vars = _get_moi_variables(sampler)
    return VI[
        vi for vi in vars if
        haskey(vds, vi) && any(s -> typeof(s) === B, vds[vi].bound_sets)
    ]
end

function _domain_constraint_variable(sampler::AbstractSampler, i::Integer, kind::Symbol = :all)
    variables = if kind === :all
        _get_moi_variables(sampler)
    elseif kind === :integer_constraint
        _integer_constraint_variables(sampler)
    else
        _domain_constraint_variables(sampler, kind)
    end
    vi = VI(i)

    if !(vi in variables)
        error("Invalid constraint index '$i'; There are $(length(variables)) constraints")
    end

    return vi
end

function _get_variable_encoding_set(
    sampler::AbstractSampler,
    vi::VI,
)::Union{Vector{Int},Nothing}
    vds = _get_variable_domains(sampler)
    if haskey(vds, vi)
        vd = vds[vi]
        return vd.has_encoding_set ? copy(vd.values) : nothing
    elseif vi in _get_moi_variables(sampler) || QUBOTools.hasvariable(sampler, vi)
        return nothing
    else
        throw(ArgumentError("Variable '$vi' is not present in the sampler model."))
    end
end

function MOI.get(
    sampler::AbstractSampler,
    ::VariableEncodingSet,
    vi::VI,
)::Union{Vector{Int},Nothing}
    return _get_variable_encoding_set(sampler, vi)
end

function MOI.get_fallback(
    sampler::AbstractSampler,
    attr::MOI.AbstractVariableAttribute,
    vi::VI,
)
    if _is_variable_encoding_set_attr(attr)
        return _get_variable_encoding_set(sampler, vi)
    end
    return throw(
        MOI.GetAttributeNotAllowed(
            attr,
            "$(typeof(sampler)) does not support getting the attribute $(attr).",
        ),
    )
end

function MOI.get(sampler::AbstractSampler, ::MOI.ListOfVariableAttributesSet)
    attrs = MOI.AbstractVariableAttribute[]
    vds = _get_variable_domains(sampler)
    if any(vd -> vd.has_encoding_set, values(vds))
        push!(attrs, VariableEncodingSet())
    end
    return attrs
end

function _set_variable_encoding_set!(
    sampler::AbstractSampler,
    attr::MOI.AbstractVariableAttribute,
    vi::VI,
    value,
)
    supports_domain(sampler, :set) || throw(MOI.UnsupportedAttribute(attr))
    if !(vi in _get_moi_variables(sampler) || QUBOTools.hasvariable(sampler, vi))
        throw(ArgumentError("Variable '$vi' is not present in the sampler model."))
    end
    if isnothing(value)
        throw(
            ArgumentError(
                "Clearing `VariableEncodingSet` (`nothing`) on variable '$vi' is not supported after `copy_to`.",
            ),
        )
    end
    int_set = _parse_encoding_set(vi, value)
    vds = _get_variable_domains(sampler)
    if haskey(vds, vi)
        old_vd = vds[vi]
        if old_vd.kind === :bool
            throw(
                ArgumentError(
                    "Value sets (`VariableEncodingSet`) are not supported for boolean (`MOI.ZeroOne`) variables; found one on variable '$vi'.",
                ),
            )
        elseif old_vd.kind === :spin
            throw(
                ArgumentError(
                    "Value sets (`VariableEncodingSet`) are not supported for spin (`Spin`) variables; found one on variable '$vi'.",
                ),
            )
        end
        lo = old_vd.lower_bound
        up = old_vd.upper_bound
        if (!isnothing(lo) && any(v -> v < lo, int_set)) ||
           (!isnothing(up) && any(v -> v > up, int_set))
            throw(
                ArgumentError(
                    "Value set for variable '$vi' has entries outside its declared bounds " *
                    "[$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)].",
                ),
            )
        end
        new_vd = _VariableDomain(
            :set,
            int_set,
            true,
            old_vd.has_integer_constraint,
            lo,
            up,
            old_vd.bound_sets,
        )
    else
        new_vd = _VariableDomain(:set, int_set, true, false)
    end

    fixed_vars = _get_fixed_variables(sampler)
    if haskey(fixed_vars, vi)
        _validate_fixed_value(new_vd, vi, fixed_vars[vi].int_value)
    elseif QUBOTools.hasvariable(sampler, vi)
        s = QUBOTools.start(sampler, QUBOTools.index(sampler, vi))
        if !isnothing(s) && !(s in int_set)
            throw(
                ArgumentError(
                    "Value set for variable '$vi' excludes its warm-start value '$s'.",
                ),
            )
        end
    end

    vds_copy = copy(vds)
    vds_copy[vi] = new_vd
    _store_variable_domains!(sampler, vds_copy)
    return nothing
end

function MOI.set(
    sampler::AbstractSampler,
    attr::VariableEncodingSet,
    vi::VI,
    value,
)
    return _set_variable_encoding_set!(sampler, attr, vi, value)
end

function MOI.throw_set_error_fallback(
    sampler::AbstractSampler,
    attr::MOI.AbstractVariableAttribute,
    vi::VI,
    value;
    error_if_supported = MOI.SetAttributeNotAllowed(attr),
)
    if _is_variable_encoding_set_attr(attr)
        return _set_variable_encoding_set!(sampler, attr, vi, value)
    end
    if MOI.supports(sampler, attr, VI)
        throw(error_if_supported)
    else
        throw(MOI.UnsupportedAttribute(attr))
    end
end

function _get_variable_primal_start(sampler::AbstractSampler{T}, vi::VI) where {T}
    fixed_variables = _get_fixed_variables(sampler)

    if haskey(fixed_variables, vi)
        return fixed_variables[vi].int_value
    end

    i = QUBOTools.index(sampler, vi)

    return QUBOTools.start(sampler, i)
end

function _set_variable_primal_start!(sampler::AbstractSampler{T}, vi::VI, value) where {T}
    if !(isnothing(value) || value isa Real)
        error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")
    end

    fixed_variables = _get_fixed_variables(sampler)

    if haskey(fixed_variables, vi)
        fixed_value = fixed_variables[vi].int_value

        if !isnothing(value)
            if !(value isa Real && isfinite(value) && isinteger(value))
                error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")
            end
            val_big = value isa Integer ? BigInt(value) : BigInt(value)
            if val_big != BigInt(fixed_value)
                error("Value for 'MOI.VariablePrimalStart' must match the fixed value '$fixed_value'")
            end
        end

        return nothing
    end

    int_val = nothing
    if !isnothing(value)
        if !(value isa Real && isfinite(value) && isinteger(value))
            error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")
        end
        val_big = value isa Integer ? BigInt(value) : BigInt(value)
        if !(typemin(Int) <= val_big <= typemax(Int))
            error("Value for 'MOI.VariablePrimalStart' overflows Int")
        end
        int_val = Int(val_big)

        vds = _get_variable_domains(sampler)
        if haskey(vds, vi)
            vd = vds[vi]
            if vd.kind === :bool && !(int_val == 0 || int_val == 1)
                error("Integer value for 'MOI.VariablePrimalStart' must be either '0' or '1'")
            elseif vd.kind === :spin && !(int_val == -1 || int_val == 1)
                error("Integer value for 'MOI.VariablePrimalStart' must be either '-1' or '1'")
            elseif !(int_val in vd.values)
                error("Integer value '$value' for 'MOI.VariablePrimalStart' must belong to domain $(vd.values)")
            end
        else
            X = QUBOTools.domain(sampler)

            if X === QUBOTools.BoolDomain && !(int_val == 0 || int_val == 1)
                error("Integer value for 'MOI.VariablePrimalStart' must be either '0' or '1'")
            elseif X === QUBOTools.SpinDomain && !(int_val == -1 || int_val == 1)
                error("Integer value for 'MOI.VariablePrimalStart' must be either '-1' or '1'")
            end
        end
    end

    QUBOTools.attach!(sampler, vi => int_val)

    return nothing
end

function _variable_domain(src::MOI.ModelLike, variables::Set{VI})
    bool_variables = Set{VI}()
    spin_variables = Set{VI}()

    if MOI.supports_constraint(src, VI, MOI.ZeroOne)
        for ci in MOI.get(src, MOI.ListOfConstraintIndices{VI,MOI.ZeroOne}())
            push!(bool_variables, MOI.get(src, MOI.ConstraintFunction(), ci))
        end
    end

    if MOI.supports_constraint(src, VI, Spin)
        for ci in MOI.get(src, MOI.ListOfConstraintIndices{VI,Spin}())
            push!(spin_variables, MOI.get(src, MOI.ConstraintFunction(), ci))
        end
    end

    if !isempty(bool_variables) && !isempty(spin_variables)
        error("The given model contains both boolean and spin variables.")
    elseif isempty(spin_variables)
        bool_variables == variables || error("Not all variables in the given model are boolean.")

        return :bool
    else
        spin_variables == variables || error("Not all variables in the given model are spin.")

        return :spin
    end
end

function _parse_fixed_integer_value(vi::VI, raw_val)::Int
    if !(raw_val isa Real && isfinite(raw_val) && isinteger(raw_val))
        throw(
            ArgumentError(
                "Invalid non-integer fixed value '$raw_val' for variable '$vi'.",
            ),
        )
    end
    val_big = raw_val isa Integer ? BigInt(raw_val) : BigInt(raw_val)
    if !(typemin(Int) <= val_big <= typemax(Int))
        throw(
            ArgumentError(
                "Fixed value '$raw_val' for variable '$vi' overflows Int.",
            ),
        )
    end
    return Int(val_big)
end

function _validate_fixed_value(domain::Symbol, vi::VI, value::Real)
    if domain === :bool
        if !(value == zero(value) || value == one(value))
            throw(ArgumentError("Invalid fixed value '$value' for boolean variable '$vi'"))
        end
    elseif domain === :spin
        if !(value == -one(value) || value == one(value))
            throw(ArgumentError("Invalid fixed value '$value' for spin variable '$vi'"))
        end
    end

    return nothing
end

function _validate_fixed_value(vd::_VariableDomain, vi::VI, value::Real)
    if vd.kind === :bool
        if !(value == zero(value) || value == one(value))
            throw(ArgumentError("Invalid fixed value '$value' for boolean variable '$vi'"))
        end
    elseif vd.kind === :spin
        if !(value == -one(value) || value == one(value))
            throw(ArgumentError("Invalid fixed value '$value' for spin variable '$vi'"))
        end
    else
        if !(isfinite(value) && isinteger(value) && any(v -> v == value, vd.values))
            throw(
                ArgumentError(
                    "Invalid fixed value '$value' for variable '$vi' with domain $(vd.values)",
                ),
            )
        end
    end

    return nothing
end

function _parse_encoding_set(vi::VI, raw_set)::Vector{Int}
    raw_set isa AbstractVector || throw(
        ArgumentError(
            "Value set (`VariableEncodingSet`) for variable '$vi' must be a vector, got $(typeof(raw_set)).",
        ),
    )
    isempty(raw_set) && throw(
        ArgumentError("Value set for variable '$vi' is empty."),
    )
    length(raw_set) <= _MAX_FINITE_DOMAIN_SIZE || throw(
        ArgumentError(
            "Value set for variable '$vi' has $(length(raw_set)) entries, exceeding maximum finite domain size $_MAX_FINITE_DOMAIN_SIZE.",
        ),
    )

    int_set = Vector{Int}(undef, length(raw_set))
    for (idx, val) in enumerate(raw_set)
        if !(val isa Real && isfinite(val) && isinteger(val))
            throw(
                ArgumentError(
                    "Value set for variable '$vi' must contain only finite integer values, got '$val'.",
                ),
            )
        end
        val_big = val isa Integer ? BigInt(val) : BigInt(val)
        if !(typemin(Int) <= val_big <= typemax(Int))
            throw(
                ArgumentError(
                    "Value set entry '$val' for variable '$vi' overflows Int.",
                ),
            )
        end
        int_set[idx] = Int(val_big)
    end

    allunique(int_set) || throw(
        ArgumentError("Value set for variable '$vi' contains duplicate entries."),
    )

    return int_set
end

function _collect_encoding_sets(src::MOI.ModelLike, variables::Vector{VI})
    encoding_sets = Dict{VI,Vector{Int}}()
    var_attrs = try
        MOI.get(src, MOI.ListOfVariableAttributesSet())
    catch err
        if err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed}
            MOI.AbstractVariableAttribute[]
        else
            rethrow()
        end
    end

    for attr in var_attrs
        _is_variable_encoding_set_attr(attr) || continue
        for vi in variables
            raw_set = try
                MOI.get(src, attr, vi)
            catch err
                if err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed}
                    nothing
                else
                    rethrow()
                end
            end
            isnothing(raw_set) && continue

            int_set = _parse_encoding_set(vi, raw_set)

            if haskey(encoding_sets, vi) && encoding_sets[vi] != int_set
                throw(
                    ArgumentError(
                        "Conflicting `VariableEncodingSet` attributes for variable '$vi'.",
                    ),
                )
            end
            encoding_sets[vi] = int_set
        end
    end

    return encoding_sets
end

function _update_lower_bound!(lower_bounds::Dict{VI,Real}, vi::VI, bound::Real)
    isnan(bound) && throw(ArgumentError("Invalid NaN lower bound for variable '$vi'."))
    bound == -Inf && return nothing
    if haskey(lower_bounds, vi)
        lower_bounds[vi] = max(lower_bounds[vi], bound)
    else
        lower_bounds[vi] = bound
    end
    return nothing
end

function _update_upper_bound!(upper_bounds::Dict{VI,Real}, vi::VI, bound::Real)
    isnan(bound) && throw(ArgumentError("Invalid NaN upper bound for variable '$vi'."))
    bound == Inf && return nothing
    if haskey(upper_bounds, vi)
        upper_bounds[vi] = min(upper_bounds[vi], bound)
    else
        upper_bounds[vi] = bound
    end
    return nothing
end

function _compute_contiguous_integer_domain(vi::VI, lo::Real, up::Real)::Vector{Int}
    if !(isfinite(lo) && isfinite(up))
        throw(
            ArgumentError(
                "Integer variable '$vi' requires finite lower and upper bounds, got [$lo, $up].",
            ),
        )
    end
    lo_big = ceil(BigInt, lo)
    up_big = floor(BigInt, up)
    if lo_big > up_big
        throw(
            ArgumentError(
                "Integer variable '$vi' has an empty integer domain for bounds [$lo, $up].",
            ),
        )
    end
    if lo_big < typemin(Int) || up_big > typemax(Int)
        throw(
            ArgumentError(
                "Bounds [$lo, $up] for integer variable '$vi' overflow Int.",
            ),
        )
    end
    num_levels = up_big - lo_big + 1
    if num_levels > _MAX_FINITE_DOMAIN_SIZE
        throw(
            ArgumentError(
                "Integer variable '$vi' has $num_levels levels in [$lo_big, $up_big], exceeding maximum finite domain size $_MAX_FINITE_DOMAIN_SIZE.",
            ),
        )
    end
    return collect(Int(lo_big):Int(up_big))
end

function _collect_variable_domains_and_fixed(
    ::Type{T},
    sampler::AbstractSampler{T},
    src::MOI.ModelLike,
    variables::Vector{VI},
) where {T}
    fixed_variables = Dict{VI,_FixedVariable{T}}()
    var_domains = Dict{VI,_VariableDomain}()

    if MOI.is_empty(src)
        return fixed_variables, var_domains, false
    end

    bool_vars = Set{VI}()
    spin_vars = Set{VI}()
    int_vars = Set{VI}()
    bounded_vars = Set{VI}()
    lower_bounds = Dict{VI,Real}()
    upper_bounds = Dict{VI,Real}()
    bound_sets_by_var = Dict{VI,Vector{MOI.AbstractScalarSet}}()

    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        if F !== VI
            QUBOTools_MOI.qubo_parsing_error("The provided model is not unconstrained.\n")
        end

        if S === MOI.ZeroOne
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                push!(bool_vars, MOI.get(src, MOI.ConstraintFunction(), ci))
            end
        elseif S === Spin
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                push!(spin_vars, MOI.get(src, MOI.ConstraintFunction(), ci))
            end
        elseif S === MOI.Integer
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                push!(int_vars, MOI.get(src, MOI.ConstraintFunction(), ci))
            end
        elseif S <: MOI.Interval
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                vi = MOI.get(src, MOI.ConstraintFunction(), ci)
                set = MOI.get(src, MOI.ConstraintSet(), ci)
                push!(bounded_vars, vi)
                push!(get!(bound_sets_by_var, vi, MOI.AbstractScalarSet[]), set)
                _update_lower_bound!(lower_bounds, vi, set.lower)
                _update_upper_bound!(upper_bounds, vi, set.upper)
            end
        elseif S <: MOI.GreaterThan
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                vi = MOI.get(src, MOI.ConstraintFunction(), ci)
                set = MOI.get(src, MOI.ConstraintSet(), ci)
                push!(bounded_vars, vi)
                push!(get!(bound_sets_by_var, vi, MOI.AbstractScalarSet[]), set)
                _update_lower_bound!(lower_bounds, vi, set.lower)
            end
        elseif S <: MOI.LessThan
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                vi = MOI.get(src, MOI.ConstraintFunction(), ci)
                set = MOI.get(src, MOI.ConstraintSet(), ci)
                push!(bounded_vars, vi)
                push!(get!(bound_sets_by_var, vi, MOI.AbstractScalarSet[]), set)
                _update_upper_bound!(upper_bounds, vi, set.upper)
            end
        elseif S <: MOI.EqualTo
            for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
                vi = MOI.get(src, MOI.ConstraintFunction(), ci)
                raw_val = MOI.get(src, MOI.ConstraintSet(), ci).value
                int_val = _parse_fixed_integer_value(vi, raw_val)
                value_type = S.parameters[1]

                if haskey(fixed_variables, vi)
                    fixed_variables[vi].int_value == int_val ||
                        throw(ArgumentError("Conflicting fixed values for variable '$vi'"))
                    fixed_variables[vi].set_type == value_type ||
                        throw(ArgumentError("Conflicting fixed constraint types for variable '$vi'"))
                    continue
                end

                fixed_variables[vi] = _FixedVariable{T}(convert(T, int_val), int_val, value_type)
            end
        else
            throw(
                ArgumentError(
                    "Unsupported variable constraint '$S' in sampler model; " *
                    "supported discrete domains are binary (`MOI.ZeroOne`), spin (`QUBODrivers.Spin`), " *
                    "bounded integer (`MOI.Integer` with bounds), and value sets (`QUBODrivers.VariableEncodingSet`).",
                ),
            )
        end
    end

    encoding_sets = _collect_encoding_sets(src, variables)

    for vi in variables
        is_bool = vi in bool_vars
        is_spin = vi in spin_vars
        is_int = vi in int_vars
        has_set = haskey(encoding_sets, vi)
        lo = get(lower_bounds, vi, nothing)
        up = get(upper_bounds, vi, nothing)
        v_bound_sets = get(bound_sets_by_var, vi, MOI.AbstractScalarSet[])

        if (is_bool + is_spin + is_int) > 1
            throw(
                ArgumentError(
                    "Variable '$vi' has conflicting domain constraints (cannot combine `MOI.ZeroOne`, `Spin`, and `MOI.Integer`).",
                ),
            )
        end

        if has_set
            if is_bool
                throw(
                    ArgumentError(
                        "Value sets (`VariableEncodingSet`) are not supported for binary (`MOI.ZeroOne`) variables; found one on variable '$vi'.",
                    ),
                )
            elseif is_spin
                throw(
                    ArgumentError(
                        "Value sets (`VariableEncodingSet`) are not supported for spin (`Spin`) variables; found one on variable '$vi'.",
                    ),
                )
            end

            if !supports_domain(sampler, :set)
                throw(
                    ArgumentError(
                        "Variable '$vi' has domain `:set` (`VariableEncodingSet`), which is not supported by sampler " *
                        "`$(typeof(sampler))` (supported domains: `$(supported_domains(sampler))`).",
                    ),
                )
            end

            vals = encoding_sets[vi]
            if (!isnothing(lo) && any(v -> v < lo, vals)) ||
               (!isnothing(up) && any(v -> v > up, vals))
                throw(
                    ArgumentError(
                        "Value set for variable '$vi' has entries outside its declared bounds " *
                        "[$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)].",
                    ),
                )
            end

            var_domains[vi] = _VariableDomain(:set, vals, true, is_int, lo, up, v_bound_sets)
        elseif is_bool
            if !supports_domain(sampler, :bool)
                throw(
                    ArgumentError(
                        "Variable '$vi' has domain `:bool` (`MOI.ZeroOne`), which is not supported by sampler " *
                        "`$(typeof(sampler))` (supported domains: `$(supported_domains(sampler))`).",
                    ),
                )
            end
            if vi in bounded_vars &&
               ((!isnothing(lo) && lo > 0) || (!isnothing(up) && up < 1))
                throw(
                    ArgumentError(
                        "Bounds [$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)] on binary variable '$vi' exclude 0 or 1; " *
                        "use `MOI.EqualTo` to fix a binary variable.",
                    ),
                )
            end
            var_domains[vi] = _VariableDomain(:bool, [0, 1], false, false, lo, up, v_bound_sets)
        elseif is_spin
            if !supports_domain(sampler, :spin)
                throw(
                    ArgumentError(
                        "Variable '$vi' has domain `:spin` (`Spin`), which is not supported by sampler " *
                        "`$(typeof(sampler))` (supported domains: `$(supported_domains(sampler))`).",
                    ),
                )
            end
            if vi in bounded_vars &&
               ((!isnothing(lo) && lo > -1) || (!isnothing(up) && up < 1))
                throw(
                    ArgumentError(
                        "Bounds [$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)] on spin variable '$vi' exclude -1 or 1; " *
                        "use `MOI.EqualTo` to fix a spin variable.",
                    ),
                )
            end
            var_domains[vi] = _VariableDomain(:spin, [-1, 1], false, false, lo, up, v_bound_sets)
        elseif is_int
            if !supports_domain(sampler, :int)
                throw(
                    ArgumentError(
                        "Variable '$vi' has domain `:int` (`MOI.Integer`), which is not supported by sampler " *
                        "`$(typeof(sampler))` (supported domains: `$(supported_domains(sampler))`).",
                    ),
                )
            end

            if haskey(fixed_variables, vi) && (isnothing(lo) || isnothing(up))
                fval = fixed_variables[vi].int_value
                if (!isnothing(lo) && fval < lo) || (!isnothing(up) && fval > up)
                    throw(
                        ArgumentError(
                            "Fixed value '$fval' for integer variable '$vi' lies outside its declared bounds " *
                            "[$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)].",
                        ),
                    )
                end
                var_domains[vi] = _VariableDomain(:int, [fval], false, true, lo, up, v_bound_sets)
            else
                if isnothing(lo) || isnothing(up)
                    throw(
                        ArgumentError(
                            "Integer variable '$vi' requires finite lower and upper bounds (or a `VariableEncodingSet`), " *
                            "got [$(isnothing(lo) ? "-∞" : lo), $(isnothing(up) ? "+∞" : up)].",
                        ),
                    )
                end
                vals = _compute_contiguous_integer_domain(vi, lo, up)
                var_domains[vi] = _VariableDomain(:int, vals, false, true, lo, up, v_bound_sets)
            end
        else
            throw(
                ArgumentError(
                    "Variable '$vi' has no discrete finite domain (expected `MOI.ZeroOne`, `QUBODrivers.Spin`, " *
                    "bounded `MOI.Integer`, or `QUBODrivers.VariableEncodingSet`); continuous variables cannot be sampled without relaxation.",
                ),
            )
        end

        if haskey(fixed_variables, vi)
            _validate_fixed_value(var_domains[vi], vi, fixed_variables[vi].int_value)
        end
    end

    kinds = Set(vd.kind for vd in values(var_domains))
    if (:bool in kinds && :spin in kinds) && !_supports_nonbinary_domains(sampler)
        error("The given model contains both boolean and spin variables.")
    end

    has_nonbinary_domains = (:int in kinds) || (:set in kinds) || length(kinds) > 1

    return fixed_variables, var_domains, has_nonbinary_domains
end

function _collect_fixed_variables(::Type{T}, src::MOI.ModelLike, domain::Symbol) where {T}
    fixed_variables = Dict{VI,_FixedVariable{T}}()

    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        if F != VI || !(S <: MOI.EqualTo)
            continue
        end

        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            vi = MOI.get(src, MOI.ConstraintFunction(), ci)
            raw_val = MOI.get(src, MOI.ConstraintSet(), ci).value
            _validate_fixed_value(domain, vi, raw_val)
            int_val = _parse_fixed_integer_value(vi, raw_val)
            value_type = S.parameters[1]

            if haskey(fixed_variables, vi)
                fixed_variables[vi].int_value == int_val ||
                    throw(ArgumentError("Conflicting fixed values for variable '$vi'"))
                fixed_variables[vi].set_type == value_type ||
                    throw(ArgumentError("Conflicting fixed constraint types for variable '$vi'"))
                continue
            end

            fixed_variables[vi] = _FixedVariable{T}(convert(T, int_val), int_val, value_type)
        end
    end

    return fixed_variables
end

function _collect_fixed_variables(src::MOI.ModelLike, ::Type{T}) where {T}
    variables = Set{VI}(MOI.get(src, MOI.ListOfVariableIndices()))

    isempty(variables) && return Dict{VI,_FixedVariable{T}}()

    return _collect_fixed_variables(T, src, _variable_domain(src, variables))
end

function _accumulate_affine_term!(
    linear_terms::Dict{VI,T},
    fixed_variables,
    vi::VI,
    coefficient::T,
    offset::T,
) where {T}
    if haskey(fixed_variables, vi)
        iszero(coefficient) && return offset
        return offset + coefficient * _fixed_value(fixed_variables, vi)
    end

    linear_terms[vi] = get(linear_terms, vi, zero(T)) + coefficient

    return offset
end

function _accumulate_quadratic_term!(
    linear_terms::Dict{VI,T},
    quadratic_terms::Dict{Tuple{VI,VI},T},
    fixed_variables,
    xi::VI,
    xj::VI,
    coefficient::T,
    offset::T,
) where {T}
    iszero(coefficient) && return offset
    xi_fixed = haskey(fixed_variables, xi)
    xj_fixed = haskey(fixed_variables, xj)

    if xi_fixed && xj_fixed
        return offset + coefficient * _fixed_value(fixed_variables, xi) * _fixed_value(fixed_variables, xj)
    elseif xi_fixed
        return _accumulate_affine_term!(
            linear_terms,
            fixed_variables,
            xj,
            coefficient * _fixed_value(fixed_variables, xi),
            offset,
        )
    elseif xj_fixed
        return _accumulate_affine_term!(
            linear_terms,
            fixed_variables,
            xi,
            coefficient * _fixed_value(fixed_variables, xj),
            offset,
        )
    end

    if xi.value > xj.value
        xi, xj = xj, xi
    end

    quadratic_terms[(xi, xj)] = get(quadratic_terms, (xi, xj), zero(T)) + coefficient

    return offset
end

function _validate_unconstrained_moi_model(
    src::MOI.ModelLike;
    allow_polynomial_objective::Bool = false,
    allow_nonbinary_domains::Bool = false,
)
    sense = MOI.get(src, MOI.ObjectiveSense())
    if !(sense === MOI.MIN_SENSE || sense === MOI.MAX_SENSE)
        QUBOTools_MOI.qubo_parsing_error(
            """
            The provided model has an invalid optimization sense.
            It should be either minimization or maximization.
            """,
        )
    end

    F_obj = MOI.get(src, MOI.ObjectiveFunctionType())
    is_quadratic = (F_obj <: SQF || F_obj <: SAF || F_obj <: VI)
    is_polynomial = is_quadratic ||
        (F_obj <: MOI.ScalarNonlinearFunction || F_obj <: ScalarPolynomialFunction)

    if !(allow_polynomial_objective ? is_polynomial : is_quadratic)
        QUBOTools_MOI.qubo_parsing_error(
            "The provided model's objective function is not a quadratic polynomial.\n",
        )
    end

    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        if F === VI
            if S ∈ (MOI.ZeroOne, Spin) || S <: MOI.EqualTo
                continue
            elseif allow_nonbinary_domains &&
                   (S === MOI.Integer || S <: Union{MOI.Interval,MOI.GreaterThan,MOI.LessThan})
                continue
            end
        end
        QUBOTools_MOI.qubo_parsing_error("The provided model is not unconstrained.\n")
    end

    return nothing
end

function _variable_symbol(src::MOI.ModelLike, vi::VI)
    name = try
        MOI.get(src, MOI.VariableName(), vi)
    catch err
        if err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed}
            ""
        else
            rethrow()
        end
    end

    return isempty(name) ? Symbol("x[$(vi.value)]") : Symbol(name)
end

function _build_quadratic_model_from_polynomial(
    ::Type{T},
    poly::PolyType{T},
    free_variables::Vector{VI},
    poly_vars::Vector{VarType};
    sense::QUBOTools.Sense,
    domain::Symbol,
) where {T}
    var_lookup = Dict{VarType,VI}(poly_vars[i] => free_variables[i] for i in eachindex(free_variables))
    linear_terms = Dict{VI,T}(vi => zero(T) for vi in free_variables)
    quadratic_terms = Dict{Tuple{VI,VI},T}()
    offset = zero(T)

    for term in MP.terms(poly)
        coef = convert(T, MP.coefficient(term))
        iszero(coef) && continue
        mono = MP.monomial(term)
        deg = MP.degree(mono)

        if deg == 0
            offset += coef
        elseif deg == 1
            for (pv, exp) in MP.powers(mono)
                if exp == 1
                    vi = var_lookup[pv]
                    linear_terms[vi] = get(linear_terms, vi, zero(T)) + coef
                end
            end
        elseif deg == 2
            active = Tuple{VI,Int}[
                (var_lookup[pv], exp) for (pv, exp) in MP.powers(mono) if exp > 0
            ]
            if length(active) == 1
                vi, _ = only(active)
                if domain === :bool
                    linear_terms[vi] = get(linear_terms, vi, zero(T)) + coef
                else
                    offset += coef
                end
            else
                (xi, _), (xj, _) = active[1], active[2]
                if xi.value > xj.value
                    xi, xj = xj, xi
                end
                quadratic_terms[(xi, xj)] = get(quadratic_terms, (xi, xj), zero(T)) + coef
            end
        else
            error("Expected polynomial degree <= 2, got degree $deg")
        end
    end

    return QUBOTools.Model{VI,T,Int}(
        Set{VI}(free_variables),
        linear_terms,
        quadratic_terms;
        offset = offset,
        sense  = sense,
        domain = domain,
    )
end

function _uniform_binary_or_spin_domain(var_domains::Dict{VI,_VariableDomain})::Union{Symbol,Nothing}
    isempty(var_domains) && return :bool
    kinds = Set(vd.kind for vd in values(var_domains))
    length(kinds) == 1 || return nothing
    kind = only(kinds)
    return (kind === :bool || kind === :spin) ? kind : nothing
end

function _active_polynomial_variables(p::MP.AbstractPolynomialLike)::Set{VarType}
    active = Set{VarType}()
    for term in MP.terms(p)
        iszero(MP.coefficient(term)) && continue
        for (pv, exp) in MP.powers(MP.monomial(term))
            exp > 0 && push!(active, pv)
        end
    end
    return active
end

function _build_polynomial_sampler_model(
    ::Type{T},
    src::MOI.ModelLike,
    variables::Vector{VI},
    fixed_variables,
    var_domains::Dict{VI,_VariableDomain} = Dict{VI,_VariableDomain}();
    allow_polynomial_objective::Bool = true,
    has_nonbinary_domains::Bool = false,
) where {T}
    if MOI.is_empty(src)
        model = QUBOTools.Model{VI,T,Int}(; sense = :min, domain = :bool)
        return model, nothing
    end

    _validate_unconstrained_moi_model(
        src;
        allow_polynomial_objective = allow_polynomial_objective,
        allow_nonbinary_domains    = true,
    )

    uniform_domain = if isempty(var_domains)
        _variable_domain(src, Set{VI}(variables))
    else
        _uniform_binary_or_spin_domain(var_domains)
    end
    domain_sym = isnothing(uniform_domain) ? :bool : uniform_domain
    sense_qt = QUBOTools.sense(MOI.get(src, MOI.ObjectiveSense()))
    domain_qt = isnothing(uniform_domain) ? nothing : QUBOTools.domain(uniform_domain)

    free_variables = sort!(
        VI[v for v in variables if !haskey(fixed_variables, v)];
        by = v -> v.value,
    )
    poly_vars = VarType[
        MP.similar_variable(VarType, _variable_symbol(src, vi)) for vi in free_variables
    ]
    free_var_map = Dict{VI,VarType}(
        free_variables[i] => poly_vars[i] for i in eachindex(free_variables)
    )

    F = MOI.get(src, MOI.ObjectiveFunctionType())
    f = MOI.get(src, MOI.ObjectiveFunction{F}())
    spf = f isa FuncType{T} ? f : convert(FuncType{T}, f)

    spf_poly_vars = MP.variables(spf.polynomial)
    active_spf_vars = _active_polynomial_variables(spf.polynomial)
    subs_targets = PolyType{T}[
        let vi = spf.variables[j]
            if haskey(fixed_variables, vi)
                (j <= length(spf_poly_vars) && spf_poly_vars[j] in active_spf_vars) ?
                    convert(PolyType{T}, _fixed_value(fixed_variables, vi)) :
                    zero(PolyType{T})
            else
                convert(PolyType{T}, free_var_map[vi])
            end
        end
        for j in eachindex(spf.variables)
    ]
    raw_poly = isempty(spf.variables) ?
        convert(PolyType{T}, spf.polynomial) :
        convert(PolyType{T}, spf.polynomial(spf_poly_vars => subs_targets))
    zero_anchor = sum(zero(T) * pv for pv in poly_vars; init = zero(PolyType{T}))
    poly = raw_poly + zero_anchor

    if !has_nonbinary_domains && MP.maxdegree(poly) <= 2
        model = _build_quadratic_model_from_polynomial(
            T,
            poly,
            free_variables,
            poly_vars;
            sense  = sense_qt,
            domain = domain_sym,
        )
        is_higher_order = false
    else
        linear_terms = Dict{VI,T}(vi => zero(T) for vi in free_variables)
        quadratic_terms = Dict{Tuple{VI,VI},T}()
        offset = convert(T, _constant_coefficient(poly))
        model = QUBOTools.Model{VI,T,Int}(
            Set{VI}(free_variables),
            linear_terms,
            quadratic_terms;
            offset = offset,
            sense  = sense_qt,
            domain = domain_sym,
        )
        is_higher_order = MP.maxdegree(poly) > 2
    end

    poly_obj = _PolynomialObjective{T}(
        poly,
        free_variables,
        sense_qt,
        domain_qt,
        is_higher_order,
        has_nonbinary_domains,
    )

    return model, poly_obj
end

function _build_model_with_fixed_variables(
    ::Type{T},
    src::MOI.ModelLike,
    variables::Vector{VI},
    fixed_variables,
) where {T}
    _validate_unconstrained_moi_model(src; allow_polynomial_objective = false)
    variable_set = Set{VI}(variables)
    free_variables = Set{VI}(filter(v -> !haskey(fixed_variables, v), variables))
    domain = _variable_domain(src, variable_set)

    linear_terms = Dict{VI,T}(vi => zero(T) for vi in free_variables)
    quadratic_terms = Dict{Tuple{VI,VI},T}()
    offset = zero(T)

    F = MOI.get(src, MOI.ObjectiveFunctionType())
    f = MOI.get(src, MOI.ObjectiveFunction{F}())

    if F <: VI
        offset = _accumulate_affine_term!(linear_terms, fixed_variables, f, one(T), offset)
    elseif F <: SAF
        for term in f.terms
            offset = _accumulate_affine_term!(
                linear_terms,
                fixed_variables,
                term.variable,
                term.coefficient,
                offset,
            )
        end

        offset += convert(T, f.constant)
    elseif F <: SQF
        for term in f.affine_terms
            offset = _accumulate_affine_term!(
                linear_terms,
                fixed_variables,
                term.variable,
                term.coefficient,
                offset,
            )
        end

        for term in f.quadratic_terms
            xi = term.variable_1
            xj = term.variable_2
            coefficient = term.coefficient

            if xi == xj
                # MOI uses a 1/2 x'Qx convention for quadratic objectives, so
                # diagonal terms contribute coefficient / 2 to x_i^2.
                if domain === :bool
                    offset = _accumulate_affine_term!(
                        linear_terms,
                        fixed_variables,
                        xi,
                        coefficient / 2,
                        offset,
                    )
                else
                    offset += coefficient / 2
                end
            else
                offset = _accumulate_quadratic_term!(
                    linear_terms,
                    quadratic_terms,
                    fixed_variables,
                    xi,
                    xj,
                    coefficient,
                    offset,
                )
            end
        end

        offset += convert(T, f.constant)
    end

    return QUBOTools.Model{VI,T,Int}(
        free_variables,
        linear_terms,
        quadratic_terms;
        offset = offset,
        sense  = QUBOTools.sense(MOI.get(src, MOI.ObjectiveSense())),
        domain = domain,
    )
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.RawStatusString) where {T}
    solution_metadata = QUBOTools.metadata(QUBOTools.solution(sampler))

    if !haskey(solution_metadata, "status")
        return ""
    else
        return solution_metadata["status"]::String
    end
end

MOI.supports(::AbstractSampler{T}, ::MOI.RawStatusString) where {T} = true

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ResultCount) where {T}
    return length(QUBOTools.solution(sampler))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.TerminationStatus) where {T}
    ω = QUBOTools.solution(sampler)

    if isempty(ω)
        if isempty(QUBOTools.metadata(ω))
            return MOI.OPTIMIZE_NOT_CALLED
        else
            return MOI.OTHER_ERROR
        end
    else
        # This one is a little bit tricky...
        # It is nice if samplers implement this method in order to give
        # more accurate information.
        return MOI.LOCALLY_SOLVED
    end
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ObjectiveSense) where {T}
    sense = QUBOTools.sense(sampler)

    if sense === QUBOTools.Min
        return MOI.MIN_SENSE
    else
        return MOI.MAX_SENSE
    end
end

function MOI.get(sampler::AbstractSampler{T}, ov::MOI.ObjectiveValue) where {T}
    i = ov.result_index
    ω = QUBOTools.solution(sampler)
    m = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= m)
        error("Invalid result index '$i'; There are $(m) solutions")
    end

    return QUBOTools.value(ω, i)
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.SolveTimeSec) where {T}
    return effective_time(sampler)
end

function MOI.get(sampler::AbstractSampler{T}, vp::MOI.VariablePrimal, vi::VI) where {T}
    i = vp.result_index
    ω = QUBOTools.solution(sampler)
    m = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= m)
        error("Invalid result index '$i'; There are $(m) solutions")
    end

    fixed_vars = _get_fixed_variables(sampler)
    if haskey(fixed_vars, vi)
        return _convert_exact(T, fixed_vars[vi].int_value, "fixed primal value for variable '$vi'")
    end

    j = QUBOTools.index(sampler, vi)
    s = QUBOTools.state(ω, i, j)

    return _convert_exact(T, s, "sampled primal value for variable '$vi'")
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfVariables) where {T}
    return length(_get_moi_variables(sampler))
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.NumberOfConstraints{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return length(_fixed_constraint_variables(sampler, S))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfConstraints{VI,MOI.ZeroOne}) where {T}
    return length(_domain_constraint_variables(sampler, :bool))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfConstraints{VI,Spin}) where {T}
    return length(_domain_constraint_variables(sampler, :spin))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfConstraints{VI,MOI.Integer}) where {T}
    return length(_integer_constraint_variables(sampler))
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.NumberOfConstraints{VI,B},
) where {T,B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    return length(_bound_constraint_variables(sampler, B))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ListOfConstraintTypesPresent) where {T}
    if iszero(MOI.get(sampler, MOI.NumberOfVariables()))
        return Tuple{Type,Type}[]
    end

    constraint_types = Tuple{Type,Type}[]

    if !isempty(_domain_constraint_variables(sampler, :bool))
        push!(constraint_types, (VI, MOI.ZeroOne))
    end
    if !isempty(_domain_constraint_variables(sampler, :spin))
        push!(constraint_types, (VI, Spin))
    end
    if !isempty(_integer_constraint_variables(sampler))
        push!(constraint_types, (VI, MOI.Integer))
    end

    vds = _get_variable_domains(sampler)
    bound_set_types = DataType[]
    for vi in _get_moi_variables(sampler)
        if haskey(vds, vi)
            for bset in vds[vi].bound_sets
                B = typeof(bset)
                B in bound_set_types || push!(bound_set_types, B)
            end
        end
    end
    for B in bound_set_types
        push!(constraint_types, (VI, B))
    end

    fixed_variables = _get_fixed_variables(sampler)
    equal_to_types = DataType[]

    for vi in _get_moi_variables(sampler)
        if haskey(fixed_variables, vi)
            S = fixed_variables[vi].set_type
            S in equal_to_types || push!(equal_to_types, S)
        end
    end

    for S in equal_to_types
        push!(constraint_types, (VI, MOI.EqualTo{S}))
    end

    return constraint_types
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ListOfVariableIndices) where {T}
    return copy(_get_moi_variables(sampler))
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,MOI.ZeroOne},
) where {T}
    return MOI.ConstraintIndex{VI,MOI.ZeroOne}[
        MOI.ConstraintIndex{VI,MOI.ZeroOne}(vi.value) for
        vi in _domain_constraint_variables(sampler, :bool)
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,Spin},
) where {T}
    return MOI.ConstraintIndex{VI,Spin}[
        MOI.ConstraintIndex{VI,Spin}(vi.value) for
        vi in _domain_constraint_variables(sampler, :spin)
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,MOI.Integer},
) where {T}
    return MOI.ConstraintIndex{VI,MOI.Integer}[
        MOI.ConstraintIndex{VI,MOI.Integer}(vi.value) for
        vi in _integer_constraint_variables(sampler)
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,B},
) where {T,B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    return MOI.ConstraintIndex{VI,B}[
        MOI.ConstraintIndex{VI,B}(vi.value) for
        vi in _bound_constraint_variables(sampler, B)
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return MOI.ConstraintIndex{VI,MOI.EqualTo{S}}[
        MOI.ConstraintIndex{VI,MOI.EqualTo{S}}(vi.value) for
        vi in _fixed_constraint_variables(sampler, S)
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    return _domain_constraint_variable(sampler, ci.value, :bool)
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,Spin},
) where {T}
    return _domain_constraint_variable(sampler, ci.value, :spin)
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,MOI.Integer},
) where {T}
    return _domain_constraint_variable(sampler, ci.value, :integer_constraint)
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,B},
) where {T,B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    vars = _bound_constraint_variables(sampler, B)
    vi = VI(ci.value)
    if !(vi in vars)
        error("Invalid constraint index '$(ci.value)'; There are $(length(vars)) constraints")
    end
    return vi
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return _fixed_constraint_variable(sampler, ci)
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    _domain_constraint_variable(sampler, ci.value, :bool)
    return MOI.ZeroOne()
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,Spin},
) where {T}
    _domain_constraint_variable(sampler, ci.value, :spin)
    return Spin()
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,MOI.Integer},
) where {T}
    _domain_constraint_variable(sampler, ci.value, :integer_constraint)
    return MOI.Integer()
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,B},
) where {T,B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    vds = _get_variable_domains(sampler)
    vi = VI(ci.value)
    if haskey(vds, vi) && vi in _get_moi_variables(sampler)
        for bset in vds[vi].bound_sets
            if typeof(bset) === B
                return bset::B
            end
        end
    end
    error("Invalid constraint index '$(ci.value)'; There are $(length(_bound_constraint_variables(sampler, B))) constraints")
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    vi = _fixed_constraint_variable(sampler, ci)

    return MOI.EqualTo(
        _convert_exact(
            S,
            _get_fixed_variables(sampler)[vi].int_value,
            "fixed constraint value for variable '$vi'",
        ),
    )
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    return VI(ci.value) in _domain_constraint_variables(sampler, :bool)
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,Spin},
) where {T}
    return VI(ci.value) in _domain_constraint_variables(sampler, :spin)
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.Integer},
) where {T}
    return VI(ci.value) in _integer_constraint_variables(sampler)
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,B},
) where {T,B<:Union{MOI.Interval{<:Real},MOI.GreaterThan{<:Real},MOI.LessThan{<:Real}}}
    return VI(ci.value) in _bound_constraint_variables(sampler, B)
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return VI(ci.value) in _fixed_constraint_variables(sampler, S)
end

function MOI.supports(::AbstractSampler{T}, ::MOIB.ListOfNonstandardBridges{S}) where {T,S}
    return false
end
