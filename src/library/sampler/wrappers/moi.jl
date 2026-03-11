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
MOI.supports_constraint(::AbstractSampler{T}, ::Type{VI}, ::Type{MOI.EqualTo{T}}) where {T} = true

# ~ Objective Function Support
MOI.supports(::AbstractSampler{T}, ::MOI.ObjectiveFunction{<:Any}) where {T} = false

MOI.supports(::AbstractSampler{T}, ::MOI.ObjectiveSense) where {T} = true

MOI.supports(
    ::AbstractSampler{T},
    ::MOI.ObjectiveFunction{<:Union{SQF{T},SAF{T},VI}},
) where {T} = true

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


# ~*~ :: MathOptInterface :: ~*~ #
function MOI.empty!(sampler::AbstractSampler{T}) where {T}
    QUBODrivers.set_model!(sampler, QUBOTools.Model{VI,T,Int}())
    _store_moi_variables!(sampler, VI[])
    _store_fixed_variables!(sampler, Dict{VI,T}())

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

    model = isempty(fixed_variables) ? QUBOTools.Model{T}(src) :
        _build_model_with_fixed_variables(T, src, variables, fixed_variables)
    QUBODrivers.set_model!(sampler, model)

    # Collect warm-start values
    for v in variables
        if haskey(fixed_variables, v)
            continue
        end

        x = MOI.get(src, MOI.VariablePrimalStart(), v)

        MOI.set(sampler, MOI.VariablePrimalStart(), v, x)
    end

    return MOIU.identity_index_map(src)
end

function _store_moi_variables!(sampler::AbstractSampler, variables::Vector{VI})
    if hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[:moi_variables] = variables
    end

    return nothing
end

function _get_moi_variables(sampler::AbstractSampler)
    if hasfield(typeof(sampler), :attributes) &&
       isa(sampler.attributes, Dict) &&
       haskey(sampler.attributes, :moi_variables)
        return sampler.attributes[:moi_variables]::Vector{VI}
    end

    return Vector{VI}(QUBOTools.variables(sampler))
end

function _store_fixed_variables!(sampler::AbstractSampler{T}, fixed_variables::Dict{VI, T}) where {T}
    if hasfield(typeof(sampler), :attributes) && isa(sampler.attributes, Dict)
        sampler.attributes[:fixed_variables] = fixed_variables
    end
    return nothing
end

# Helper function to retrieve fixed variables from sampler
function _get_fixed_variables(sampler::AbstractSampler{T}) where {T}
    if hasfield(typeof(sampler), :attributes) &&
       isa(sampler.attributes, Dict) &&
       haskey(sampler.attributes, :fixed_variables)
        return sampler.attributes[:fixed_variables]::Dict{VI, T}
    end

    return Dict{VI, T}()
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
    fixed_variables = Dict{VI,T}()

    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        if F != VI || !(S <: MOI.EqualTo)
            continue
        end

        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            vi = MOI.get(src, MOI.ConstraintFunction(), ci)
            value = convert(T, MOI.get(src, MOI.ConstraintSet(), ci).value)

            _validate_fixed_value(domain, vi, value)

            if haskey(fixed_variables, vi)
                fixed_variables[vi] == value ||
                    throw(ArgumentError("Conflicting fixed values for variable '$vi'"))
                continue
            end

            fixed_variables[vi] = value
        end
    end

    return fixed_variables
end

function _collect_fixed_variables(src::MOI.ModelLike, ::Type{T}) where {T}
    variables = Set{VI}(MOI.get(src, MOI.ListOfVariableIndices()))

    isempty(variables) && return Dict{VI,T}()

    return _collect_fixed_variables(T, src, _variable_domain(src, variables))
end

function _accumulate_affine_term!(
    linear_terms::Dict{VI,T},
    fixed_variables::Dict{VI,T},
    vi::VI,
    coefficient::T,
    offset::T,
) where {T}
    if haskey(fixed_variables, vi)
        return offset + coefficient * fixed_variables[vi]
    end

    linear_terms[vi] = get(linear_terms, vi, zero(T)) + coefficient

    return offset
end

function _accumulate_quadratic_term!(
    linear_terms::Dict{VI,T},
    quadratic_terms::Dict{Tuple{VI,VI},T},
    fixed_variables::Dict{VI,T},
    xi::VI,
    xj::VI,
    coefficient::T,
    offset::T,
) where {T}
    xi_fixed = haskey(fixed_variables, xi)
    xj_fixed = haskey(fixed_variables, xj)

    if xi_fixed && xj_fixed
        return offset + coefficient * fixed_variables[xi] * fixed_variables[xj]
    elseif xi_fixed
        return _accumulate_affine_term!(
            linear_terms,
            fixed_variables,
            xj,
            coefficient * fixed_variables[xi],
            offset,
        )
    elseif xj_fixed
        return _accumulate_affine_term!(
            linear_terms,
            fixed_variables,
            xi,
            coefficient * fixed_variables[xj],
            offset,
        )
    end

    quadratic_terms[xi, xj] = get(quadratic_terms, (xi, xj), zero(T)) + coefficient

    return offset
end

function _build_model_with_fixed_variables(
    ::Type{T},
    src::MOI.ModelLike,
    variables::Vector{VI},
    fixed_variables::Dict{VI,T},
) where {T}
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
    return QUBOTools.effective_time(QUBOTools.solution(sampler))
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
        return fixed_vars[vi]
    end

    j = QUBOTools.index(sampler, vi)
    s = QUBOTools.state(ω, i, j)

    return convert(T, s)
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfVariables) where {T}
    return length(_get_moi_variables(sampler))
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ListOfConstraintTypesPresent) where {T}
    if iszero(MOI.get(sampler, MOI.NumberOfVariables()))
        return []
    end

    if QUBOTools.domain(sampler) === QUBOTools.BoolDomain
        return [(VI, MOI.ZeroOne)]
    else # QUBOTools.domain(sampler) === QUBOTools.SpinDomain
        return [(VI, Spin)]
    end
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.ListOfVariableIndices) where {T}
    return copy(_get_moi_variables(sampler))
end

function MOI.supports(sampler::AbstractSampler{T}, ::MOIB.ListOfNonstandardBridges{T}) where {T}
    return false
end
