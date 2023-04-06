module QUBODrivers

using Test
using MathOptInterface
const MOI    = MathOptInterface
const MOIU   = MOI.Utilities
const VI     = MOI.VariableIndex
const SAF{T} = MOI.ScalarAffineFunction{T}
const SAT{T} = MOI.ScalarAffineTerm{T}
const SQF{T} = MOI.ScalarQuadraticFunction{T}
const SQT{T} = MOI.ScalarQuadraticTerm{T}

import QUBOTools: QUBOTools, Sample, SampleSet, qubo, ising, ↑, ↓

export MOI, Sample, SampleSet, Spin, qubo, ising, ↑, ↓

include("abstract/interface.jl")
include("abstract/wrapper.jl")

include("automatic/interface.jl")
include("automatic/attributes.jl")
include("automatic/setup.jl")
include("automatic/sample.jl")
include("automatic/wrapper.jl")

include("test/test.jl")

export ExactSampler, IdentitySampler, RandomSampler

include("drivers/ExactSampler.jl")
include("drivers/IdentitySampler.jl")
include("drivers/RandomSampler.jl")

end # module QUBODrivers
