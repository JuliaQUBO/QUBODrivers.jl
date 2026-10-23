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

const VariableOrder =
    DynamicPolynomials.Commutative{DynamicPolynomials.CreationOrder}
const MonomialOrder = MP.Graded{MP.LexOrder}
const VarType = DynamicPolynomials.Variable{VariableOrder,MonomialOrder}
const PolyType{T} = DynamicPolynomials.Polynomial{VariableOrder,MonomialOrder,T}

@doc raw"""
    polynomial_type(::Type{MOI.VariableIndex})
    polynomial_type(::Type{MOI.VariableIndex}, ::Type{T}) where {T}
    polynomial_type(::Type{T} = Float64) where {T<:Number}

Return the concrete `DynamicPolynomials.Polynomial` type used by `QUBODrivers`
to represent MOI polynomial functions with coefficient type `T`.
"""
polynomial_type(::Type{MOI.VariableIndex}) = PolyType
polynomial_type(::Type{MOI.VariableIndex}, ::Type{T}) where {T} = PolyType{T}
polynomial_type(::Type{T} = Float64) where {T<:Number} = PolyType{T}

@doc raw"""
    struct ScalarPolynomialFunction{T,P<:MP.AbstractPolynomial{T}} <: MOI.AbstractScalarFunction
        polynomial::P
        variables::Vector{MOI.VariableIndex}
    end

Defines the polynomial function of the variables `variables` where the variable
`MultivariatePolynomials.variables(polynomial)[i]` corresponds to `variables[i]`.
"""
struct ScalarPolynomialFunction{T,P<:MP.AbstractPolynomial{T}} <:
       MOI.AbstractScalarFunction
    polynomial::P
    variables::Vector{MOI.VariableIndex}
end

function ScalarPolynomialFunction(
    polynomial::P,
) where {T,P<:MP.AbstractPolynomial{T}}
    variables = MOI.VariableIndex[
        MOI.VariableIndex(i) for i in 1:length(MP.variables(polynomial))
    ]
    return ScalarPolynomialFunction{T,P}(polynomial, variables)
end

const FuncType{T} = ScalarPolynomialFunction{T,PolyType{T}}

@doc raw"""
    polynomial_function(p::MP.AbstractPolynomial{T}, variables::Vector{MOI.VariableIndex}) where {T}
    polynomial_function(func::MOI.AbstractScalarFunction, ::Type{T} = Float64) where {T}
    polynomial_function(sampler::AbstractSampler{T}; sense = nothing, domain = nothing) where {T}

Construct or extract a [`ScalarPolynomialFunction`](@ref) representing a scalar
polynomial objective or constraint expression.
"""
function polynomial_function(
    p::MP.AbstractPolynomial{T},
    variables::Vector{MOI.VariableIndex} = MOI.VariableIndex[
        MOI.VariableIndex(i) for i in 1:length(MP.variables(p))
    ],
) where {T}
    return ScalarPolynomialFunction{T,typeof(p)}(p, variables)
end

function polynomial_function(
    func::MOI.AbstractScalarFunction,
    ::Type{T} = Float64,
) where {T}
    return convert(FuncType{T}, func)
end

function _constant_coefficient(p::MP.AbstractPolynomialLike)
    return MP.coefficient(p, MP.constant_monomial(p))
end

function MOI.constant(func::ScalarPolynomialFunction)
    return _constant_coefficient(func.polynomial)
end

function _polynomial_variable(::Type{P}, vi::MOI.VariableIndex) where {P}
    return MP.similar_variable(P, Symbol("x[$(vi.value)]"))
end

function Base.convert(
    ::Type{ScalarPolynomialFunction{T,P}},
    vi::MOI.VariableIndex,
) where {T,P}
    x = _polynomial_variable(P, vi)
    return ScalarPolynomialFunction{T,P}(MP.polynomial(x, T), [vi])
end

function _polynomial_variables!(::Type{P}, variables) where {P}
    sort!(variables, by = v -> v.value)
    unique!(variables)
    x = _polynomial_variable.(P, variables)
    if !issorted(x, rev = true)
        error("`$P` unsupported, use DynamicPolynomials instead")
    end
    d = Dict{MOI.VariableIndex,VarType}(
        variables[i] => x[i] for i in eachindex(variables)
    )
    return x, d
end

function _polynomial_with_variables(
    ::Type{P},
    func::MOI.ScalarAffineFunction{T},
    d,
) where {T,P}
    poly = foldl(
        +,
        (convert(T, t.coefficient) * d[t.variable] for t in func.terms);
        init = convert(P, convert(T, MOI.constant(func))),
    )
    return convert(P, poly)
end

function Base.convert(
    ::Type{ScalarPolynomialFunction{T,P}},
    func::MOI.ScalarAffineFunction{T},
) where {T,P}
    variables = MOI.VariableIndex[t.variable for t in func.terms]
    _, d = _polynomial_variables!(P, variables)
    poly = _polynomial_with_variables(P, func, d)
    return _scalar_polynomial(d, T, poly)
end

function Base.convert(
    ::Type{ScalarPolynomialFunction{T,P}},
    func::MOI.ScalarQuadraticFunction{T},
) where {T,P}
    linear_variables = MOI.VariableIndex[t.variable for t in func.affine_terms]
    quad_variables_1 = MOI.VariableIndex[t.variable_1 for t in func.quadratic_terms]
    quad_variables_2 = MOI.VariableIndex[t.variable_2 for t in func.quadratic_terms]
    variables = [linear_variables; quad_variables_1; quad_variables_2]
    _, d = _polynomial_variables!(P, variables)
    poly = _to_polynomial!(d, T, func)
    return _scalar_polynomial(d, T, poly)
end

function Base.convert(
    ::Type{ScalarPolynomialFunction{T,P}},
    func::MOI.ScalarNonlinearFunction,
) where {T,P}
    return _to_polynomial(func, T)
end

function Base.copy(func::ScalarPolynomialFunction)
    return ScalarPolynomialFunction(
        MA.copy_if_mutable(func.polynomial),
        copy(func.variables),
    )
end

function MOI.Utilities.canonicalize!(func::ScalarPolynomialFunction)
    return func
end

function _variables(aff::MOI.ScalarAffineFunction)
    return MOI.VariableIndex[t.variable for t in aff.terms]
end

function MOI.Utilities.substitute_variables(
    variable_map::Function,
    func::ScalarPolynomialFunction{T,P},
) where {T,P}
    isempty(func.variables) && return copy(func)
    new_aff =
        MOI.ScalarAffineFunction{T}[variable_map(var) for var in func.variables]
    variables = collect(Iterators.flatten(_variables(aff) for aff in new_aff))
    _, d = _polynomial_variables!(P, variables)
    new_polys = P[_polynomial_with_variables(P, aff, d) for aff in new_aff]
    new_poly = func.polynomial(MP.variables(func.polynomial) => new_polys)
    return _scalar_polynomial(d, T, new_poly)
end

function MOI.Utilities.is_coefficient_type(
    ::Type{<:ScalarPolynomialFunction{T}},
    ::Type{S},
) where {S,T}
    return S === T
end

# Placeholder for `promote_operation`
struct VectorPolynomialFunction{T,P<:MP.AbstractPolynomial{T}} <:
       MOI.AbstractVectorFunction end

function MOI.Utilities.scalar_type(
    ::Type{VectorPolynomialFunction{T,P}},
) where {T,P}
    return ScalarPolynomialFunction{T,P}
end

function MOI.Utilities.is_coefficient_type(
    ::Type{<:VectorPolynomialFunction{T}},
    ::Type{T},
) where {T}
    return true
end

function MOI.Utilities.is_coefficient_type(
    ::Type{<:VectorPolynomialFunction},
    ::Type,
)
    return false
end

function MOI.Utilities.promote_operation(
    ::typeof(-),
    ::Type{T},
    F::Type{
        <:Union{ScalarPolynomialFunction{T,P},VectorPolynomialFunction{T,P}},
    },
) where {T,P}
    return F
end

function MOI.Utilities.promote_operation(
    ::typeof(-),
    ::Type{T},
    F::Type{ScalarPolynomialFunction{T,P}},
    ::Type{<:Union{T,MOI.Utilities.ScalarLike{T}}},
) where {T,P}
    return F
end

function MOI.Utilities.promote_operation(
    ::typeof(-),
    ::Type{T},
    F::Type{VectorPolynomialFunction{T,P}},
    ::Type{<:Union{AbstractVector{T},MOI.Utilities.VectorLike{T}}},
) where {T,P}
    return F
end

function MOI.Utilities.promote_operation(
    ::typeof(vcat),
    ::Type{T},
    ::Type{ScalarPolynomialFunction{T,P}},
) where {T,P}
    return VectorPolynomialFunction{T,P}
end

function MOI.Utilities.operate(
    op::Union{typeof(+),typeof(-)},
    ::Type{T},
    p::ScalarPolynomialFunction{T,P},
    f::Union{T,MOI.AbstractScalarFunction},
) where {T,P}
    d = Dict{MOI.VariableIndex,VarType}(
        vi => v for (vi, v) in zip(p.variables, MP.variables(p.polynomial))
    )
    vars = MOI.VariableIndex[]
    _collect_expr_variables!(vars, f)
    sort!(vars, by = v -> v.value)
    unique!(vars)
    for vi in vars
        if !haskey(d, vi)
            d[vi] = _polynomial_variable(P, vi)
        end
    end
    poly = _to_polynomial!(d, T, f)
    return _scalar_polynomial(d, T, op(p.polynomial, poly))
end
