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
    elseif _has_nonbinary_or_heterogeneous_domains(sampler)
        throw(
            ArgumentError(
                "Cannot extract a binary/spin QUBO or Ising form when variables have non-binary or heterogeneous domains; " *
                "use `QUBODrivers.polynomial_objective(sampler)` and `QUBODrivers.variable_domains(sampler)` instead.",
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

function QUBOTools.linear_form(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.linear_form(QUBOTools.backend(sampler))
end

function QUBOTools.quadratic_form(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.quadratic_form(QUBOTools.backend(sampler))
end

function QUBOTools.linear_terms(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.linear_terms(QUBOTools.backend(sampler))
end

function QUBOTools.quadratic_terms(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.quadratic_terms(QUBOTools.backend(sampler))
end

function QUBOTools.linear_size(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.linear_size(QUBOTools.backend(sampler))
end

function QUBOTools.quadratic_size(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.quadratic_size(QUBOTools.backend(sampler))
end

function QUBOTools.topology(sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.topology(QUBOTools.backend(sampler))
end

function QUBOTools.write_model(dst, sampler::AbstractSampler)
    _require_quadratic_objective(sampler)
    return QUBOTools.write_model(dst, QUBOTools.backend(sampler))
end

function QUBOTools.write_model(dst, sampler::AbstractSampler, fmt)
    _require_quadratic_objective(sampler)
    return QUBOTools.write_model(dst, QUBOTools.backend(sampler), fmt)
end

function QUBOTools.value(sampler::AbstractSampler, i::Integer)
    return QUBOTools.value(QUBOTools.backend(sampler), i)
end

function QUBOTools.value(
    sampler::AbstractSampler{T},
    ψ::AbstractVector{<:Real},
) where {T}
    if _has_higher_order_polynomial_objective(sampler) ||
       _has_nonbinary_or_heterogeneous_domains(sampler)
        poly_obj = _get_polynomial_objective(sampler)
        if !isnothing(poly_obj)
            n = length(poly_obj.variables)
            if length(ψ) != n
                throw(
                    DimensionMismatch(
                        "State vector length $(length(ψ)) does not match model dimension $n.",
                    ),
                )
            end
            p = poly_obj.polynomial
            vars = MP.variables(p)
            isempty(vars) && return convert(T, _constant_coefficient(p))
            active_vars = _active_polynomial_variables(p)
            has_inexact_active_state = false
            eval_vals = [
                if vars[i] in active_vars
                    if !_is_exact_in(T, ψ[i])
                        has_inexact_active_state = true
                    end
                    _promote_state_for_polynomial_eval(T, ψ[i])
                else
                    zero(T)
                end
                for i in eachindex(vars)
            ]
            raw_val = p(vars => eval_vals)
            if has_inexact_active_state && isinteger(raw_val) && !_is_exact_in(T, raw_val)
                _convert_exact(T, raw_val, "objective value at state")
            end
            return convert(T, raw_val)
        end
    end

    return QUBOTools.value(QUBOTools.backend(sampler), ψ)
end
