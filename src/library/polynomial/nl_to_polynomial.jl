# Copyright (c) 2016: Christopher Coey, Robin Deits, Joey Huchette, Benoît Legat, Amelia Perry, and contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Adapted from PolyJuMP.jl (https://github.com/jump-dev/PolyJuMP.jl).

@doc raw"""
    NLToPolynomial{T,M<:MOI.ModelLike} <: MOI.AbstractOptimizer

Optimizer wrapper that rewrites nonlinear polynomial expressions into
[`ScalarPolynomialFunction`](@ref) objectives and constraints.
"""
mutable struct NLToPolynomial{T,M<:MOI.ModelLike} <: MOI.AbstractOptimizer
    model::M
    constraint_indices::Vector{MOI.ConstraintIndex{FuncType{T}}}
    invalid::Union{Nothing,String}
    function NLToPolynomial{T}(model::M) where {T,M}
        return new{T,M}(model, MOI.ConstraintIndex{FuncType{T}}[], nothing)
    end
end

@doc raw"""
    InvalidNLExpression <: Exception

Exception thrown when a nonlinear expression cannot be converted into a
polynomial (for example, when it uses a non-polynomial operator such as `sin`,
non-constant division `/`, or a non-integer or negative exponent in `^`).
"""
struct InvalidNLExpression <: Exception
    message::String
end

function Base.showerror(io::IO, err::InvalidNLExpression)
    print(io, "InvalidNLExpression: ", err.message)
    return nothing
end

_collect_expr_variables!(::Vector{MOI.VariableIndex}, ::Any) = nothing

function _collect_expr_variables!(
    vars::Vector{MOI.VariableIndex},
    vi::MOI.VariableIndex,
)
    push!(vars, vi)
    return nothing
end

function _collect_expr_variables!(
    vars::Vector{MOI.VariableIndex},
    f::MOI.ScalarAffineFunction,
)
    for t in f.terms
        push!(vars, t.variable)
    end
    return nothing
end

function _collect_expr_variables!(
    vars::Vector{MOI.VariableIndex},
    f::MOI.ScalarQuadraticFunction,
)
    for t in f.affine_terms
        push!(vars, t.variable)
    end
    for t in f.quadratic_terms
        push!(vars, t.variable_1)
        push!(vars, t.variable_2)
    end
    return nothing
end

function _collect_expr_variables!(
    vars::Vector{MOI.VariableIndex},
    f::MOI.ScalarNonlinearFunction,
)
    for arg in f.args
        _collect_expr_variables!(vars, arg)
    end
    return nothing
end

function _collect_expr_variables!(vars::Vector{MOI.VariableIndex}, expr::Expr)
    if _is_variable(expr)
        push!(vars, expr.args[2])
    elseif Base.Meta.isexpr(expr, :call)
        for arg in expr.args[2:end]
            _collect_expr_variables!(vars, arg)
        end
    end
    return nothing
end

function _to_polynomial!(d, ::Type, expr)
    return throw(
        InvalidNLExpression(
            "Unexpected expression type `$(typeof(expr))` of `$expr`",
        ),
    )
end

_to_polynomial!(d, ::Type{T}, x::T) where {T} = x
_to_polynomial!(d, ::Type{T}, x::Number) where {T} = convert(T, x)

function _is_operator(expr::Expr, sym)
    return Base.Meta.isexpr(expr, :call) && expr.args[1] === sym
end
_operands(expr::Expr) = expr.args[2:end]
function _is_variable(expr::Expr)
    return Base.Meta.isexpr(expr, :ref) &&
           expr.args[1] === :x &&
           expr.args[2] isa MOI.VariableIndex
end

function _is_operator(func::MOI.ScalarNonlinearFunction, sym)
    return func.head === sym
end
_operands(func::MOI.ScalarNonlinearFunction) = func.args
_is_variable(expr::MOI.ScalarNonlinearFunction) = false

function _operator_name(func::MOI.ScalarNonlinearFunction)
    return func.head
end

function _operator_name(expr::Expr)
    if Base.Meta.isexpr(expr, :call) && !isempty(expr.args)
        return expr.args[1]
    end
    return expr.head
end

function _to_polynomial!(d, ::Type{T}, vi::MOI.VariableIndex) where {T}
    if !haskey(d, vi)
        d[vi] = MP.similar_variable(VarType, Symbol("x[$(vi.value)]"))
    end
    return d[vi]
end

function _to_polynomial!(
    d,
    ::Type{T},
    f::MOI.ScalarAffineFunction,
) where {T}
    return foldl(
        +,
        (convert(T, t.coefficient) * _to_polynomial!(d, T, t.variable) for t in f.terms);
        init = convert(PolyType{T}, convert(T, f.constant)),
    )
end

function _to_polynomial!(
    d,
    ::Type{T},
    f::MOI.ScalarQuadraticFunction,
) where {T}
    poly = _to_polynomial!(d, T, MOI.ScalarAffineFunction(f.affine_terms, f.constant))
    for t in f.quadratic_terms
        coef = convert(T, t.variable_1 == t.variable_2 ? t.coefficient / 2 : t.coefficient)
        poly += coef * _to_polynomial!(d, T, t.variable_1) * _to_polynomial!(d, T, t.variable_2)
    end
    return poly
end

function _checked_power(expr, base, exponent)
    exp_val = if exponent isa MP.AbstractPolynomialLike
        if !MP.isconstant(exponent)
            throw(
                InvalidNLExpression(
                    "Cannot convert `$(expr)` into a polynomial: operator `^` requires a constant non-negative integer exponent, got non-constant exponent `$(exponent)`.",
                ),
            )
        end
        _constant_coefficient(exponent)
    else
        exponent
    end

    if !(exp_val isa Real && isfinite(exp_val) && isinteger(exp_val) && exp_val >= 0)
        throw(
            InvalidNLExpression(
                "Cannot convert `$(expr)` into a polynomial: operator `^` requires a non-negative integer exponent, got `$(exp_val)`.",
            ),
        )
    end

    return base^Int(exp_val)
end

function _to_polynomial!(
    d,
    ::Type{T},
    expr::Union{Expr,MOI.ScalarNonlinearFunction},
) where {T}
    operands = _operands(expr)
    if _is_operator(expr, :+)
        return foldl(
            +,
            (_to_polynomial!(d, T, arg) for arg in operands);
            init = zero(PolyType{T}),
        )
    elseif _is_operator(expr, :*)
        return foldl(
            *,
            (_to_polynomial!(d, T, arg) for arg in operands);
            init = one(PolyType{T}),
        )
    elseif _is_operator(expr, :-) && length(operands) == 1
        return -_to_polynomial!(d, T, operands[1])
    elseif _is_operator(expr, :-) && length(operands) == 2
        a, b = _to_polynomial!.(Ref(d), T, operands)
        return a - b
    elseif _is_operator(expr, :^) && length(operands) == 2
        a, b = _to_polynomial!.(Ref(d), T, operands)
        return _checked_power(expr, a, b)
    elseif _is_operator(expr, :/) && length(operands) == 2
        a, b = _to_polynomial!.(Ref(d), T, operands)
        return _checked_div(T, a, b)
    elseif _is_variable(expr)
        return _to_polynomial!(d, T, operands[1])
    else
        op = _operator_name(expr)
        throw(
            InvalidNLExpression(
                "Cannot convert `$(expr)` into a polynomial: unsupported operator `$(op)`.",
            ),
        )
    end
end

function _checked_div(::Type{T}, a::Number, b::Number) where {T}
    if iszero(b)
        throw(
            InvalidNLExpression(
                "Cannot convert `$(a) / $(b)` into a polynomial: division by zero in operator `/`.",
            ),
        )
    end
    return convert(T, a / b)
end

function _checked_div(::Type{T}, a::MP.AbstractPolynomialLike, b::Number) where {T}
    if iszero(b)
        throw(
            InvalidNLExpression(
                "Cannot convert `($(a)) / $(b)` into a polynomial: division by zero in operator `/`.",
            ),
        )
    end
    return convert(PolyType{T}, a / b)
end

function _checked_div(::Type{T}, α::Number, p::MP.AbstractPolynomialLike) where {T}
    if !MP.isconstant(p)
        throw(
            InvalidNLExpression(
                "Cannot convert `$(α) / ($(p))` to a polynomial: non-constant denominator in operator `/`.",
            ),
        )
    end
    denom = _constant_coefficient(p)
    return _checked_div(T, α, denom)
end

function _checked_div(
    ::Type{T},
    a::MP.AbstractPolynomialLike,
    b::MP.AbstractPolynomialLike,
) where {T}
    poly_a = convert(PolyType{T}, a)
    poly_b = convert(PolyType{T}, b)
    if iszero(poly_b)
        throw(
            InvalidNLExpression(
                "Cannot convert `($(a)) / ($(b))` into a polynomial: division by zero in operator `/`.",
            ),
        )
    end
    if MP.isconstant(poly_b)
        return _checked_div(T, poly_a, _constant_coefficient(poly_b))
    end
    divisor, remainder = Base.divrem(poly_a, poly_b)
    if !iszero(remainder)
        throw(
            InvalidNLExpression(
                "Cannot convert `($(a)) / ($(b))` into a polynomial: operator `/` has a nonzero remainder `$(remainder)` (the divisor is `$(divisor)`).",
            ),
        )
    end
    return divisor
end

function _to_polynomial(expr, ::Type{T}) where {T}
    vars = MOI.VariableIndex[]
    _collect_expr_variables!(vars, expr)
    _, d = _polynomial_variables!(PolyType{T}, vars)
    poly = _to_polynomial!(d, T, expr)
    return _scalar_polynomial(d, T, poly)
end

function _scalar_polynomial(d::Dict{K,V}, ::Type{T}, poly) where {T,K,V}
    P = MP.polynomial_type(V, T)
    poly_p = convert(P, poly)
    var_set = Set(MP.variables(poly_p))
    variable_map = Tuple{K,V}[(k, v) for (k, v) in d if v in var_set]
    sort!(variable_map, by = x -> x[2], rev = true)
    variables = K[x[1] for x in variable_map]
    return ScalarPolynomialFunction{T,P}(poly_p, variables)
end

function _to_polynomial(model::NLToPolynomial{T}, expr) where {T}
    try
        return _to_polynomial(expr, T)
    catch err
        if err isa InvalidNLExpression
            model.invalid = string(
                "Cannot convert expression `$(expr)` into a polynomial: ",
                err.message,
                ".",
            )
            return
        else
            rethrow(err)
        end
    end
end

MOI.supports(::NLToPolynomial, ::MOI.NLPBlock) = true
function MOI.set(
    model::NLToPolynomial{T},
    ::MOI.NLPBlock,
    data::MOI.NLPBlockData,
) where {T}
    MOI.initialize(data.evaluator, [:ExprGraph])
    model.invalid = nothing
    if data.has_objective
        obj = _to_polynomial(model, MOI.objective_expr(data.evaluator))
        if isnothing(obj)
            return
        end
        MOI.set(model.model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    end
    model.constraint_indices = map(eachindex(data.constraint_bounds)) do i
        func, set = MOI.FileFormats.MOF.extract_function_and_set(
            MOI.constraint_expr(data.evaluator, i),
        )
        poly = _to_polynomial(model, func)
        if isnothing(poly)
            return
        end
        return MOI.add_constraint(model, poly, set)
    end
end

function MOI.get(model::NLToPolynomial, attr::MOI.NLPBlockDual)
    return map(model.constraint_indices) do ci
        return MOI.get(model.model, MOI.ConstraintDual(attr.result_index), ci)
    end
end

function MOI.empty!(model::NLToPolynomial)
    empty!(model.constraint_indices)
    MOI.empty!(model.model)
    model.invalid = nothing
    return
end

function MOI.is_empty(model::NLToPolynomial)
    return MOI.is_empty(model.model) && isnothing(model.invalid)
end

function MOI.optimize!(model::NLToPolynomial)
    if isnothing(model.invalid)
        MOI.optimize!(model.model)
    end
    return
end

_invalid_value(model::NLToPolynomial, ::MOI.RawStatusString) = model.invalid
_invalid_value(::NLToPolynomial, ::MOI.TerminationStatus) = MOI.INVALID_MODEL
_invalid_value(::NLToPolynomial, ::MOI.ResultCount) = 0
function _invalid_value(
    ::NLToPolynomial,
    ::Union{MOI.PrimalStatus,MOI.DualStatus},
)
    return MOI.NO_SOLUTION
end
function _invalid_value(
    ::NLToPolynomial,
    attr::Union{MOI.VariablePrimal,MOI.ConstraintDual,MOI.ConstraintPrimal},
)
    return throw(MOI.ResultIndexBoundsError(attr, 0))
end

function MOI.get(model::NLToPolynomial, attr::MOI.AbstractModelAttribute)
    if isnothing(model.invalid) || !MOI.is_set_by_optimize(attr)
        return MOI.get(model.model, attr)
    else
        return _invalid_value(model, attr)
    end
end

function MOI.get(
    model::NLToPolynomial,
    attr::MOI.AbstractVariableAttribute,
    vi::MOI.VariableIndex,
)
    if isnothing(model.invalid) || !MOI.is_set_by_optimize(attr)
        return MOI.get(model.model, attr, vi)
    else
        return _invalid_value(model, attr)
    end
end

function MOI.get(
    model::NLToPolynomial,
    attr::MOI.AbstractConstraintAttribute,
    ci::MOI.ConstraintIndex,
)
    if isnothing(model.invalid) || !MOI.is_set_by_optimize(attr)
        return MOI.get(model.model, attr, ci)
    else
        return _invalid_value(model, attr)
    end
end

function MOI.supports_incremental_interface(model::NLToPolynomial)
    return MOI.supports_incremental_interface(model.model)
end
function MOI.copy_to(dest::NLToPolynomial, src::MOI.ModelLike)
    return MOI.Utilities.default_copy_to(dest, src)
end

MOI.add_variable(model::NLToPolynomial) = MOI.add_variable(model.model)

function MOI.supports_constraint(
    model::NLToPolynomial,
    ::Type{F},
    ::Type{S},
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return MOI.supports_constraint(model.model, F, S)
end

function MOI.add_constraint(
    model::NLToPolynomial,
    func::MOI.AbstractFunction,
    set::MOI.AbstractSet,
)
    return MOI.add_constraint(model.model, func, set)
end

function MOI.supports(
    model::NLToPolynomial,
    attr::Union{MOI.AbstractOptimizerAttribute,MOI.AbstractModelAttribute},
)
    return MOI.supports(model.model, attr)
end

function MOI.get(model::NLToPolynomial, attr::MOI.AbstractOptimizerAttribute)
    return MOI.get(model.model, attr)
end

function MOI.set(
    model::NLToPolynomial,
    attr::Union{MOI.AbstractModelAttribute,MOI.AbstractOptimizerAttribute},
    value,
)
    return MOI.set(model.model, attr, value)
end

function MOI.supports(
    model::NLToPolynomial,
    attr::MOI.AbstractVariableAttribute,
    ::Type{MOI.VariableIndex},
)
    return MOI.supports(model.model, attr, MOI.VariableIndex)
end

function MOI.set(
    model::NLToPolynomial,
    attr::MOI.AbstractVariableAttribute,
    vi::MOI.VariableIndex,
    value,
)
    return MOI.set(model.model, attr, vi, value)
end

function MOI.supports(
    model::NLToPolynomial,
    attr::MOI.AbstractConstraintAttribute,
    ::Type{MOI.ConstraintIndex{F,S}},
) where {F,S}
    return MOI.supports(model.model, attr, MOI.ConstraintIndex{F,S})
end

function MOI.set(
    model::NLToPolynomial,
    attr::MOI.AbstractConstraintAttribute,
    ci::MOI.ConstraintIndex,
    value,
)
    return MOI.set(model.model, attr, ci, value)
end
