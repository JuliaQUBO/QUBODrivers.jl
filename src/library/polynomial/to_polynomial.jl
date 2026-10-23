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
    ToPolynomialBridge{T}

`ToPolynomialBridge` implements the following reformulations:

 * ``\min \{f(x)\}`` into ``\min\{p(x)\}``
 * ``\max \{f(x)\}`` into ``\max\{p(x)\}``

where ``f(x)`` is a scalar function and ``p(x)`` is a polynomial.

## Source node

`ToPolynomialBridge` supports:

 * `MOI.ObjectiveFunction{F}` where `F` is a `MOI.AbstractScalarFunction` for
   which `convert(::Type{QUBODrivers.ScalarPolynomialFunction{T,P}}, ::F)` is
   defined, such as `MOI.VariableIndex`, `MOI.ScalarAffineFunction{T}`,
   `MOI.ScalarQuadraticFunction{T}`, and `MOI.ScalarNonlinearFunction`.

## Target nodes

`ToPolynomialBridge` creates:

 * One objective node: `MOI.ObjectiveFunction{QUBODrivers.ScalarPolynomialFunction{T,P}}`
"""
struct ToPolynomialBridge{T} <: MOI.Bridges.Objective.AbstractBridge end

function MOI.Bridges.Objective.bridge_objective(
    ::Type{ToPolynomialBridge{T}},
    model::MOI.ModelLike,
    func::MOI.AbstractScalarFunction,
) where {T}
    F = FuncType{T}
    MOI.set(model, MOI.ObjectiveFunction{F}(), convert(F, func))
    return ToPolynomialBridge{T}()
end

function MOI.Bridges.Objective.supports_objective_function(
    ::Type{ToPolynomialBridge{T}},
    ::Type{F},
) where {T,F<:MOI.AbstractScalarFunction}
    return F === MOI.ScalarNonlinearFunction ||
           MOI.Utilities.is_coefficient_type(F, T)
end

function MOI.Bridges.added_constrained_variable_types(
    ::Type{<:ToPolynomialBridge},
)
    return Tuple{Type}[]
end

function MOI.Bridges.added_constraint_types(::Type{<:ToPolynomialBridge})
    return Tuple{Type,Type}[]
end

function MOI.Bridges.set_objective_function_type(
    ::Type{ToPolynomialBridge{T}},
) where {T}
    return FuncType{T}
end

# Attributes, Bridge acting as a model
MOI.get(::ToPolynomialBridge, ::MOI.NumberOfVariables)::Int64 = 0

function MOI.get(::ToPolynomialBridge, ::MOI.ListOfVariableIndices)
    return MOI.VariableIndex[]
end

# No variables or constraints are created in this bridge so there is nothing to
# delete.
MOI.delete(::MOI.ModelLike, ::ToPolynomialBridge) = nothing

function MOI.set(
    ::MOI.ModelLike,
    ::MOI.ObjectiveSense,
    ::ToPolynomialBridge,
    ::MOI.OptimizationSense,
)
    # `ToPolynomialBridge` is sense agnostic, therefore, we don't need to change
    # anything.
    return
end

function MOI.get(
    model::MOI.ModelLike,
    attr::MOI.Bridges.ObjectiveFunctionValue,
    ::ToPolynomialBridge{T},
) where {T}
    F = FuncType{T}
    attr_f = MOI.Bridges.ObjectiveFunctionValue{F}(attr.result_index)
    return MOI.get(model, attr_f)
end

function MOI.modify(
    model::MOI.ModelLike,
    ::ToPolynomialBridge{T},
    change::MOI.AbstractFunctionModification,
) where {T}
    F = FuncType{T}
    MOI.modify(model, MOI.ObjectiveFunction{F}(), change)
    return
end

