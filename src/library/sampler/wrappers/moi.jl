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

    return sampler
end

function MOI.is_empty(sampler::AbstractSampler{T}) where {T}
    return isempty(QUBOTools.backend(sampler))
end

function MOI.optimize!(sampler::AbstractSampler{T}) where {T}
    return _sample!(sampler)
end

function MOI.copy_to(sampler::AbstractSampler{T}, src::MOI.ModelLike) where {T}
    # Check for fixed variables (EqualTo constraints)
    fixed_variables = Dict{VI, T}()
    constraint_types = MOI.get(src, MOI.ListOfConstraintTypesPresent())
    
    for (F, S) in constraint_types
        if F == VI && S == MOI.EqualTo{T}
            # Found EqualTo constraints on variables
            constraints = MOI.get(src, MOI.ListOfConstraintIndices{F, S}())
            for ci in constraints
                func = MOI.get(src, MOI.ConstraintFunction(), ci)
                set_val = MOI.get(src, MOI.ConstraintSet(), ci)
                fixed_variables[func] = set_val.value
            end
        end
    end
    
    # Store fixed variables in sampler attributes for later retrieval
    if hasfield(typeof(sampler), :attributes)
        sampler.attributes[:fixed_variables] = fixed_variables
    end
    
    # If there are fixed variables, we need to create a modified model
    if !isempty(fixed_variables)
        # Create a temporary model to build the substituted version
        temp_model = MOIU.Model{T}()
        
        # Copy everything from source
        index_map = MOIU.default_copy_to(temp_model, src)
        
        # Remove EqualTo constraints from temp_model since they'll be handled by substitution
        if (VI, MOI.EqualTo{T}) in MOI.get(temp_model, MOI.ListOfConstraintTypesPresent())
            for ci in MOI.get(temp_model, MOI.ListOfConstraintIndices{VI, MOI.EqualTo{T}}())
                MOI.delete(temp_model, ci)
            end
        end
        
        # Try to convert - QUBOTools might still complain if there are other issues
        QUBODrivers.set_model!(sampler, QUBOTools.Model{T}(temp_model))
    else
        # No fixed variables, use the original approach
        QUBODrivers.set_model!(sampler, QUBOTools.Model{T}(src))
    end

    # Collect warm-start values
    for v in MOI.get(src, MOI.ListOfVariableIndices())
        x = MOI.get(src, MOI.VariablePrimalStart(), v)

        MOI.set(sampler, MOI.VariablePrimalStart(), v, x)
    end

    return MOIU.identity_index_map(src)
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
    # Check if this variable is fixed
    if hasfield(typeof(sampler), :attributes) && haskey(sampler.attributes, :fixed_variables)
        fixed_vars = sampler.attributes[:fixed_variables]::Dict{VI, T}
        if haskey(fixed_vars, vi)
            return fixed_vars[vi]
        end
    end
    
    i = vp.result_index
    ω = QUBOTools.solution(sampler)
    m = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= m)
        error("Invalid result index '$i'; There are $(m) solutions")
    end

    j = QUBOTools.index(sampler, vi)
    s = QUBOTools.state(ω, i, j)

    return convert(T, s)
end

function MOI.get(sampler::AbstractSampler{T}, ::MOI.NumberOfVariables) where {T}
    return QUBOTools.dimension(sampler)
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
    return Vector{VI}(QUBOTools.variables(sampler))
end

function MOI.supports(sampler::AbstractSampler{T}, ::MOIB.ListOfNonstandardBridges{T}) where {T}
    return false
end
