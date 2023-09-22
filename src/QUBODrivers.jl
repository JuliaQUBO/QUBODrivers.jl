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

using QUBOTools
const Spin = QUBOTools.__moi_spin_set()

export MOI, Sample, SampleSet, Spin, ↓, ↑

include("interface/sampler.jl")
include("interface/attributes.jl")

include("library/sampler/attributes.jl")
include("library/sampler/wrappers/moi.jl")
include("library/sampler/wrappers/qubotools.jl")

include("library/test/test.jl")

include("library/setup/error.jl")
include("library/setup/specs.jl")
include("library/setup/parse.jl")
include("library/setup/quote.jl")
include("library/setup/macro.jl")

export ExactSampler, IdentitySampler, RandomSampler

include("library/drivers/ExactSampler.jl")
include("library/drivers/IdentitySampler.jl")
include("library/drivers/RandomSampler.jl")

end # module QUBODrivers
