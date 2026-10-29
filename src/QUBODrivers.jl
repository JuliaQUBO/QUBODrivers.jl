@doc raw"""
    QUBODrivers

Common MathOptInterface-compatible tools for QUBO and Ising samplers.

`QUBODrivers` provides:

- an [`AbstractSampler`](@ref) optimizer interface for QUBO-oriented solvers;
- the [`@setup`](@ref) macro for declaring sampler optimizers and attributes;
- built-in utility samplers in `ExactSampler`, `RandomSampler`,
  `IdentitySampler`, and `MIPSampler`;
- result and model plumbing through MathOptInterface and QUBOTools;
- optional [`test`](@ref) and [`benchmark`](@ref) helpers for sampler
  implementations.
"""
module QUBODrivers

import TOML
import DynamicPolynomials
import MultivariatePolynomials as MP
import MutableArithmetics as MA
import MathOptInterface as MOI

const MOIU   = MOI.Utilities
const MOIB   = MOI.Bridges
const VI     = MOI.VariableIndex
const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}
const SQF{T} = MOI.ScalarQuadraticFunction{T}
const SQT{T} = MOI.ScalarQuadraticTerm{T}

using QUBOTools
const QUBOTools_MOI = Base.get_extension(QUBOTools, :QUBOTools_MOI)
const Spin          = QUBOTools_MOI.Spin

include("projectversion.jl")

export MOI, Sample, SampleSet, Spin, ↓, ↑

include("interface/sampler.jl")
include("interface/attributes.jl")
include("interface/test.jl")
include("interface/benchmark.jl")

include("library/polynomial/functions.jl")
include("library/polynomial/nl_to_polynomial.jl")
include("library/polynomial/to_polynomial.jl")

include("library/sampler/wrappers/moi.jl")
include("library/sampler/wrappers/qubotools.jl")

include("library/setup/error.jl")
include("library/setup/specs.jl")
include("library/setup/parse.jl")
include("library/setup/quote.jl")
include("library/setup/macro.jl")

export AbstractSampler, RandomSeed, random_seed
export FinalNumberOfReads, final_number_of_reads
export AutoConfigure, auto_configure, supports_auto_configure, has_explicit_raw_attr
export Preprocess, preprocess_rules
export PostSampleCallback, PostSampleTransform, post_sample_callback, post_sample_transform
export total_time, effective_time, validate_metadata
export supports_seed, honors_final_reads, enforces_time_limit
export supported_domains, supports_domain, VariableEncodingSet
export variable_domains, variable_domain, variable_bounds, variable_num_levels
export levels_to_values, values_to_levels
export supports_polynomial_objective, polynomial_objective, polynomial_function, polynomial_type
export ScalarPolynomialFunction, VectorPolynomialFunction, ToPolynomialBridge, NLToPolynomial, InvalidNLExpression
export ExactSampler, IdentitySampler, MIPSampler, RandomSampler

include("library/drivers/ExactSampler.jl")
include("library/drivers/IdentitySampler.jl")
include("library/drivers/MIPSampler.jl")
include("library/drivers/RandomSampler.jl")

end # module QUBODrivers
