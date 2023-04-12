# ~*~ :: QUBOTools :: ~*~ #
function QUBOTools.backend(sampler::AutomaticSampler)
    return QUBOTools.cast(
        QUBOTools.sense(sampler.model),
        sampler.sense,
        QUBOTools.domain(sampler.model),
        sampler.domain,
        sampler.model
    )
end

# ~*~ :: MathOptInterface :: ~*~ #
function MOI.empty!(sampler::AutomaticSampler)
    sampler.model = nothing

    return sampler
end

function MOI.is_empty(sampler::AutomaticSampler)
    return isnothing(sampler.model)
end

function MOI.optimize!(sampler::AutomaticSampler)
    return _sample!(sampler)
end

function MOI.copy_to(sampler::AutomaticSampler{T}, model::MOI.ModelLike) where {T}
    MOI.empty!(sampler)

    # Collect warm-start values
    for vi in MOI.get(model, MOI.ListOfVariableIndices())
        xi = MOI.get(model, MOI.VariablePrimalStart(), vi)

        MOI.set(sampler, MOI.VariablePrimalStart(), vi, xi)
    end

    sampler.model = parse_model(T, model)::QUBOTools.Model{VI,T}

    return MOIU.identity_index_map(model)
end

# # function Base.show(io::IO, sampler::AutomaticSampler)
# #     print(
# #         io,
# #         """
# #         Solver: $(MOI.get(sampler, MOI.SolverName()))
# #         """,
# #     )
# # end

function MOI.get(
    sampler::AutomaticSampler,
    st::Union{MOI.PrimalStatus,MOI.DualStatus},
    ::VI,
)
    if !(1 <= st.result_index <= MOI.get(sampler, MOI.ResultCount()))
        return MOI.NO_SOLUTION
    else
        # This status is also not very accurate, but all points are feasible
        # in a general sense since these problems are unconstrained.
        return MOI.FEASIBLE_POINT
    end
end

function MOI.get(sampler::AutomaticSampler, ::MOI.RawStatusString)
    data = QUBOTools.metadata(QUBOTools.sampleset(sampler.model))

    if !haskey(data, "status")
        return ""
    else
        return data["status"]::String
    end
end

function MOI.get(sampler::AutomaticSampler, ::MOI.ResultCount)
    return length(QUBOTools.sampleset(sampler.model))
end

function MOI.get(sampler::AutomaticSampler, ::MOI.TerminationStatus)
    ω = QUBOTools.sampleset(sampler.model)

    if isempty(ω)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        # This one is a little bit tricky...
        # It is nice if samplers implement this method in order to give
        # more accurate information.
        return MOI.LOCALLY_SOLVED
    end
end

function MOI.get(sampler::AutomaticSampler{T}, ::MOI.ObjectiveSense) where {T}
    sense = QUBOTools.sense(sampler.model)

    if sense === QUBOTools.Min
        return MOI.MIN_SENSE
    else
        return MOI.MAX_SENSE
    end
end

function MOI.get(sampler::AutomaticSampler, ov::MOI.ObjectiveValue)
    ω = QUBOTools.sampleset(sampler.model)
    i = ov.result_index
    n = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= n)
        error("Invalid result index '$i'; There are $(n) solutions")
    end

    if MOI.get(sampler, MOI.ObjectiveSense()) === MOI.MAX_SENSE
        i = n - i + 1
    end

    return QUBOTools.value(ω, i)
end

function MOI.get(sampler::AutomaticSampler, ::MOI.SolveTimeSec)
    return QUBOTools.effective_time(QUBOTools.sampleset(sampler.model))
end

function MOI.get(sampler::AutomaticSampler{T}, vp::MOI.VariablePrimal, vi::VI) where {T}
    ω = QUBOTools.sampleset(sampler.model)
    n = length(ω)
    i = vp.result_index

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= n)
        error("Invalid result index '$i'; There are $(n) solutions")
    end

    variable_map = QUBOTools.variable_map(sampler.model)

    if !haskey(variable_map, vi)
        error("Variable index '$vi' not in model")
    end

    if MOI.get(sampler, MOI.ObjectiveSense()) === MOI.MAX_SENSE
        i = n - i + 1
    end

    j = variable_map[vi]::Integer
    s = QUBOTools.state(ω, i, j)

    return convert(T, s)
end

function MOI.get(sampler::AutomaticSampler, ::MOI.NumberOfVariables)
    return QUBOTools.domain_size(sampler.model)
end

function QUBOTools.qubo(sampler::AutomaticSampler, type::Type = Dict)
    @assert !isnothing(sampler.model)

    n = QUBOTools.domain_size(sampler.model)

    L, Q, α, β = QUBOTools.cast(
        # domain
        QUBOTools.domain(sampler.model), # source
        sampler.domain,                  # target
        # model terms and coefficients
        QUBOTools.linear_terms(sampler.model),
        QUBOTools.quadratic_terms(sampler.model),
        QUBOTools.scale(sampler.model),
        QUBOTools.offset(sampler.model),
    )

    L, Q, α, β = QUBOTools.cast(
        # sense
        QUBOTools.sense(sampler.model), # source
        sampler.sense,                  # target
        # model terms and coefficients
        L, Q, α, β
    )
    
    return QUBOTools.qubo(type, n, L, Q, α, β)
end

function QUBOTools.ising(sampler::AutomaticSampler, type::Type = Dict)
    @assert !isnothing(sampler.model)

    n = QUBOTools.domain_size(sampler.model)

    L, Q, α, β = QUBOTools.cast(
        # domain
        QUBOTools.domain(sampler.model), # source
        sampler.domain,                  # target
        # model terms and coefficients
        QUBOTools.linear_terms(sampler.model),
        QUBOTools.quadratic_terms(sampler.model),
        QUBOTools.scale(sampler.model),
        QUBOTools.offset(sampler.model),
    )

    L, Q, α, β = QUBOTools.cast(
        # sense
        QUBOTools.sense(sampler.model), # source
        sampler.sense,                  # target
        # model terms and coefficients
        L, Q, α, β
    )
    
    return QUBOTools.ising(type, n, L, Q, α, β)
end

# ~*~ File IO: Base API ~*~ #
# function Base.write(
#     filename::AbstractString,
#     sampler::AutomaticSampler,
#     fmt::QUBOTools.AbstractFormat = QUBOTools.infer_format(filename),
# )
#     return QUBOTools.write_model(filename, sampler.model, fmt)
# end

# function Base.read!(
#     filename::AbstractString,
#     sampler::AutomaticSampler,
#     fmt::QUBOTools.AbstractFormat = QUBOTools.infer_format(filename),
# )
#     sampler.source = QUBOTools.read_model(filename, fmt)
#     sampler.target = QUBOTools.format(sampler, sampler.source)

#     return sampler
# end

source_domain(sampler::AutomaticSampler) = QUBOTools.domain(sampler.model)
target_domain(sampler::AutomaticSampler) = sampler.domain

function warm_start(sampler::AutomaticSampler{T}, i::Integer)::Union{T,Nothing} where {T}
    v = QUBOTools.variable_inv(sampler, i)
    x = MOI.get(sampler, MOI.VariablePrimalStart(), v)

    if isnothing(x)
        return nothing
    else
        # TODO: QUBOTools should know how to cast single integers?
        y = QUBOTools.cast(
            source_domain(sampler),
            target_domain(sampler),
            round.(Int, [x])
        )

        # TODO: This is not good...
        return convert(T, y[])
    end
end

function warm_start(sampler::AutomaticSampler{T})::Union{T,Nothing} where {T}
    n = MOI.get(sampler, MOI.NumberOfVariables())
    s = sizehint!(Dict{Int,Union{T,Nothing}}(), n)

    for i = 1:n
        v = QUBOTools.variable_inv(sampler, i)
        x = MOI.get(sampler, MOI.VariablePrimalStart(), v)

        if isnothing(x)
            s[i] = nothing
        else
            # TODO: QUBOTools should know how to cast single integers?
            y = QUBOTools.cast(
                source_domain(sampler),
                target_domain(sampler),
                round.(Int, [x])
            )

            # TODO: This is not good...
            s[i] = convert(T, y[])
        end
    end

    return s
end