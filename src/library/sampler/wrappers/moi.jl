# ~ Currently, all models in this context are unconstrained by definition.
MOI.supports_constraint(
    ::AbstractSampler,
    ::Type{<:MOI.AbstractFunction},
    ::Type{<:MOI.AbstractSet},
) = false

# ~ They are also binary
MOI.supports_constraint(::AbstractSampler{T}, ::Type{VI}, ::Type{MOI.ZeroOne}) where {T} = true

MOI.supports_constraint(::AbstractSampler{T}, ::Type{VI}, ::Type{Spin}) where {T} = true

# ~ Support for fixing variables to specific values
MOI.supports_constraint(::AbstractSampler{T}, ::Type{VI}, ::Type{MOI.EqualTo{S}}) where {T,S<:Real} = true

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
const _POLYNOMIAL_OBJECTIVE_FALLBACK = WeakKeyDict{AbstractSampler,Any}()
const _POLYNOMIAL_OBJECTIVE_LOCK = ReentrantLock()

struct _FixedVariable{T}
    value::T
    set_type::DataType
end

struct _PolynomialObjective{T}
    polynomial::PolyType{T}
    variables::Vector{VI}
    sense::QUBOTools.Sense
    domain::QUBOTools.Domain
    is_higher_order::Bool
end

_fixed_value(fixed_variables::AbstractDict{VI,T}, vi::VI) where {T<:Real} = fixed_variables[vi]
_fixed_value(fixed_variables::AbstractDict{VI,_FixedVariable{T}}, vi::VI) where {T} = fixed_variables[vi].value


# ~*~ :: MathOptInterface :: ~*~ #
function MOI.empty!(sampler::AbstractSampler{T}) where {T}
    QUBODrivers.set_model!(sampler, QUBOTools.Model{VI,T,Int}())
    _store_moi_variables!(sampler, VI[])
    _store_fixed_variables!(sampler, Dict{VI,_FixedVariable{T}}())
    _store_polynomial_objective!(sampler, nothing)

    return sampler
end

function MOI.is_empty(sampler::AbstractSampler{T}) where {T}
    return isempty(_get_moi_variables(sampler))
end

function MOI.optimize!(sampler::AbstractSampler{T}) where {T}
    return _sample!(sampler)
end

function MOI.copy_to(sampler::AbstractSampler{T}, src::MOI.ModelLike) where {T}
    variables = collect(MOI.get(src, MOI.ListOfVariableIndices()))
    fixed_variables = _collect_fixed_variables(src, T)

    _store_moi_variables!(sampler, variables)
    _store_fixed_variables!(sampler, fixed_variables)

    if supports_polynomial_objective(sampler)
        model, poly_obj = _build_polynomial_sampler_model(T, src, variables, fixed_variables)
        QUBODrivers.set_model!(sampler, model)
        _store_polynomial_objective!(sampler, poly_obj)
    else
        _store_polynomial_objective!(sampler, nothing)
        model = isempty(fixed_variables) ? QUBOTools.Model{T}(src) :
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

    return MOIU.identity_index_map(src)
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

function _has_higher_order_polynomial_objective(sampler::AbstractSampler)
    poly_obj = _get_polynomial_objective(sampler)
    return !isnothing(poly_obj) && poly_obj.is_higher_order
end

function _polynomial_objective_degree(sampler::AbstractSampler)
    poly_obj = _get_polynomial_objective(sampler)
    return isnothing(poly_obj) ? 0 : MP.maxdegree(poly_obj.polynomial)
end

@doc raw"""
    polynomial_objective(
        sampler::AbstractSampler{T};
        sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
        domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
    )::MP.AbstractPolynomial{T} where {T}

Return the objective polynomial stored on an opted-in `sampler` as a
`MultivariatePolynomials.AbstractPolynomial{T}` over the free variables in
`QUBOTools.variables(sampler)` order, preserving constant offset and fixed
variable reductions.

If `sense` (`:min` or `:max`) or `domain` (`:bool` or `:spin`) is provided, the
polynomial is cast to the requested optimization sense and variable domain.

Throws an `ArgumentError` if `supports_polynomial_objective(sampler)` is `false`.
"""
function polynomial_objective(
    sampler::AbstractSampler{T};
    sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
    domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
) where {T}
    if !supports_polynomial_objective(sampler)
        throw(
            ArgumentError(
                "Sampler `$(typeof(sampler))` does not opt into polynomial objectives; " *
                "define `QUBODrivers.supports_polynomial_objective(::Type{<:$(typeof(sampler))}) = true` " *
                "to enable polynomial objective support.",
            ),
        )
    end

    poly_obj = _get_polynomial_objective(sampler)
    isnothing(poly_obj) && return zero(PolyType{T})

    p = poly_obj.polynomial
    vars = MP.variables(p)
    zero_anchor = sum(zero(T) * v for v in vars; init = zero(PolyType{T}))

    if !isnothing(domain)
        target_domain = QUBOTools.domain(domain)
        if target_domain !== poly_obj.domain && !isempty(vars)
            if poly_obj.domain === QUBOTools.BoolDomain && target_domain === QUBOTools.SpinDomain
                subs_exprs = PolyType{T}[convert(PolyType{T}, (one(T) + v) / 2) for v in vars]
                p = convert(PolyType{T}, p(vars => subs_exprs)) + zero_anchor
            elseif poly_obj.domain === QUBOTools.SpinDomain && target_domain === QUBOTools.BoolDomain
                subs_exprs = PolyType{T}[convert(PolyType{T}, 2 * v - one(T)) for v in vars]
                p = convert(PolyType{T}, p(vars => subs_exprs)) + zero_anchor
            end
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

function polynomial_function(
    sampler::AbstractSampler{T};
    sense::Union{Symbol,QUBOTools.Sense,Nothing} = nothing,
    domain::Union{Symbol,QUBOTools.Domain,Nothing} = nothing,
) where {T}
    p = polynomial_objective(sampler; sense, domain)
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
    i = ci.value
    n = length(fixed_constraint_variables)

    if !(1 <= i <= n)
        error("Invalid constraint index '$i'; There are $(n) constraints")
    end

    return fixed_constraint_variables[i]
end

function _domain_constraint_variable(sampler::AbstractSampler, i::Integer)
    variables = _get_moi_variables(sampler)
    n = length(variables)

    if !(1 <= i <= n)
        error("Invalid constraint index '$i'; There are $(n) constraints")
    end

    return variables[i]
end

function _get_variable_primal_start(sampler::AbstractSampler{T}, vi::VI) where {T}
    fixed_variables = _get_fixed_variables(sampler)

    if haskey(fixed_variables, vi)
        return fixed_variables[vi].value
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
        fixed_value = fixed_variables[vi].value

        if !isnothing(value) && value != fixed_value
            error("Value for 'MOI.VariablePrimalStart' must match the fixed value '$fixed_value'")
        end

        return nothing
    end

    if !isnothing(value)
        if !(value isa Real && isinteger(value))
            error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")
        end

        X = QUBOTools.domain(sampler)

        if X === QUBOTools.BoolDomain && !(value == zero(value) || value == one(value))
            error("Integer value for 'MOI.VariablePrimalStart' must be either '0' or '1'")
        elseif X === QUBOTools.SpinDomain && !(value == -one(value) || value == one(value))
            error("Integer value for 'MOI.VariablePrimalStart' must be either '-1' or '1'")
        end
    end

    QUBOTools.attach!(sampler, vi => convert(Union{Integer, Nothing}, value))

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

function _validate_fixed_value(domain::Symbol, vi::VI, value::T) where {T}
    if domain === :bool
        if !(value == zero(T) || value == one(T))
            throw(ArgumentError("Invalid fixed value '$value' for boolean variable '$vi'"))
        end
    elseif domain === :spin
        if !(value == -one(T) || value == one(T))
            throw(ArgumentError("Invalid fixed value '$value' for spin variable '$vi'"))
        end
    end

    return nothing
end

function _collect_fixed_variables(::Type{T}, src::MOI.ModelLike, domain::Symbol) where {T}
    fixed_variables = Dict{VI,_FixedVariable{T}}()

    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        if F != VI || !(S <: MOI.EqualTo)
            continue
        end

        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            vi = MOI.get(src, MOI.ConstraintFunction(), ci)
            value = convert(T, MOI.get(src, MOI.ConstraintSet(), ci).value)
            value_type = S.parameters[1]

            _validate_fixed_value(domain, vi, value)

            if haskey(fixed_variables, vi)
                fixed_variables[vi].value == value ||
                    throw(ArgumentError("Conflicting fixed values for variable '$vi'"))
                fixed_variables[vi].set_type == value_type ||
                    throw(ArgumentError("Conflicting fixed constraint types for variable '$vi'"))
                continue
            end

            fixed_variables[vi] = _FixedVariable{T}(value, value_type)
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
        if F === VI && (S ∈ (MOI.ZeroOne, Spin) || S <: MOI.EqualTo)
            continue
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

function _build_polynomial_sampler_model(
    ::Type{T},
    src::MOI.ModelLike,
    variables::Vector{VI},
    fixed_variables,
) where {T}
    if MOI.is_empty(src)
        model = QUBOTools.Model{VI,T,Int}(; sense = :min, domain = :bool)
        poly_obj = _PolynomialObjective{T}(
            zero(PolyType{T}),
            VI[],
            QUBOTools.Min,
            QUBOTools.BoolDomain,
            false,
        )
        return model, poly_obj
    end

    _validate_unconstrained_moi_model(src; allow_polynomial_objective = true)

    variable_set = Set{VI}(variables)
    domain_sym = _variable_domain(src, variable_set)
    sense_qt = QUBOTools.sense(MOI.get(src, MOI.ObjectiveSense()))
    domain_qt = QUBOTools.domain(domain_sym)

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
    spf = f isa ScalarPolynomialFunction ? f : convert(FuncType{T}, f)

    subs_targets = PolyType{T}[
        haskey(fixed_variables, vi) ?
            convert(PolyType{T}, _fixed_value(fixed_variables, vi)) :
            convert(PolyType{T}, free_var_map[vi])
        for vi in spf.variables
    ]
    raw_poly = isempty(spf.variables) ?
        convert(PolyType{T}, spf.polynomial) :
        convert(PolyType{T}, spf.polynomial(MP.variables(spf.polynomial) => subs_targets))
    zero_anchor = sum(zero(T) * pv for pv in poly_vars; init = zero(PolyType{T}))
    poly = raw_poly + zero_anchor

    if F <: Union{VI,SAF,SQF}
        model = isempty(fixed_variables) ? QUBOTools.Model{T}(src) :
            _build_model_with_fixed_variables(T, src, variables, fixed_variables)
        is_higher_order = false
    elseif MP.maxdegree(poly) <= 2
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
        is_higher_order = true
    end

    poly_obj = _PolynomialObjective{T}(
        poly,
        free_variables,
        sense_qt,
        domain_qt,
        is_higher_order,
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
        return fixed_vars[vi].value
    end

    j = QUBOTools.index(sampler, vi)
    s = QUBOTools.state(ω, i, j)

    return convert(T, s)
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
    return QUBOTools.domain(sampler) === QUBOTools.BoolDomain ? length(_get_moi_variables(sampler)) : 0
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfConstraints{VI,Spin}) where {T}
    return QUBOTools.domain(sampler) === QUBOTools.SpinDomain ? length(_get_moi_variables(sampler)) : 0
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ListOfConstraintTypesPresent) where {T}
    if iszero(MOI.get(sampler, MOI.NumberOfVariables()))
        return Tuple{Type,Type}[]
    end

    constraint_types = Tuple{Type,Type}[]

    if QUBOTools.domain(sampler) === QUBOTools.BoolDomain
        push!(constraint_types, (VI, MOI.ZeroOne))
    else # QUBOTools.domain(sampler) === QUBOTools.SpinDomain
        push!(constraint_types, (VI, Spin))
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
    if QUBOTools.domain(sampler) !== QUBOTools.BoolDomain
        return MOI.ConstraintIndex{VI,MOI.ZeroOne}[]
    end

    return MOI.ConstraintIndex{VI,MOI.ZeroOne}[
        MOI.ConstraintIndex{VI,MOI.ZeroOne}(i) for i in 1:length(_get_moi_variables(sampler))
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,Spin},
) where {T}
    if QUBOTools.domain(sampler) !== QUBOTools.SpinDomain
        return MOI.ConstraintIndex{VI,Spin}[]
    end

    return MOI.ConstraintIndex{VI,Spin}[
        MOI.ConstraintIndex{VI,Spin}(i) for i in 1:length(_get_moi_variables(sampler))
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ListOfConstraintIndices{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return MOI.ConstraintIndex{VI,MOI.EqualTo{S}}[
        MOI.ConstraintIndex{VI,MOI.EqualTo{S}}(i) for
        i in 1:length(_fixed_constraint_variables(sampler, S))
    ]
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    return _domain_constraint_variable(sampler, ci.value)
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{VI,Spin},
) where {T}
    return _domain_constraint_variable(sampler, ci.value)
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
    ::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    return MOI.ZeroOne()
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ::MOI.ConstraintIndex{VI,Spin},
) where {T}
    return Spin()
end

function MOI.get(
    sampler::AbstractSampler{T},
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    vi = _fixed_constraint_variable(sampler, ci)

    return MOI.EqualTo(convert(S, _get_fixed_variables(sampler)[vi].value))
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.ZeroOne},
) where {T}
    return QUBOTools.domain(sampler) === QUBOTools.BoolDomain &&
           1 <= ci.value <= length(_get_moi_variables(sampler))
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,Spin},
) where {T}
    return QUBOTools.domain(sampler) === QUBOTools.SpinDomain &&
           1 <= ci.value <= length(_get_moi_variables(sampler))
end

function MOI.is_valid(
    sampler::AbstractSampler{T},
    ci::MOI.ConstraintIndex{VI,MOI.EqualTo{S}},
) where {T,S<:Real}
    return 1 <= ci.value <= length(_fixed_constraint_variables(sampler, S))
end

function MOI.supports(::AbstractSampler{T}, ::MOIB.ListOfNonstandardBridges{S}) where {T,S}
    return false
end
