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

include("library/sampler/wrappers/moi.jl")
include("library/sampler/wrappers/qubotools.jl")

include("library/setup/error.jl")
include("library/setup/specs.jl")
include("library/setup/parse.jl")
include("library/setup/quote.jl")
include("library/setup/macro.jl")

export AbstractSampler, FinalNumberOfReads, final_number_of_reads
export ExactSampler, IdentitySampler, MIPSampler, RandomSampler

include("library/drivers/ExactSampler.jl")
include("library/drivers/IdentitySampler.jl")
include("library/drivers/MIPSampler.jl")
include("library/drivers/RandomSampler.jl")

end # module QUBODrivers
