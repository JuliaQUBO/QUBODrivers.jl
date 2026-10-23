function MOI.get(sampler::AbstractSampler{T}, nr::QUBOTools_MOI.NumberOfReads) where {T}
    i = nr.result_index
    ω = QUBOTools.solution(sampler)
    m = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= m)
        error("Invalid result index '$i'; There are $(m) solutions")
    end

    return QUBOTools.reads(ω, i)
end

function _require_quadratic_objective(sampler::AbstractSampler)
    if _has_higher_order_polynomial_objective(sampler)
        deg = _polynomial_objective_degree(sampler)
        throw(
            ArgumentError(
                "Cannot extract a quadratic QUBO/Ising form from a degree-$deg polynomial objective; " *
                "use `QUBODrivers.polynomial_objective(sampler)` instead.",
            ),
        )
    end

    return nothing
end

function QUBOTools.form(sampler::AbstractSampler, args...; kws...)
    _require_quadratic_objective(sampler)
    return QUBOTools.form(QUBOTools.backend(sampler), args...; kws...)
end

function QUBOTools.qubo(sampler::AbstractSampler, args...; kws...)
    _require_quadratic_objective(sampler)
    return QUBOTools.qubo(QUBOTools.backend(sampler), args...; kws...)
end

function QUBOTools.ising(sampler::AbstractSampler, args...; kws...)
    _require_quadratic_objective(sampler)
    return QUBOTools.ising(QUBOTools.backend(sampler), args...; kws...)
end
