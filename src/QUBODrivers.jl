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

include("library/sampler/wrappers/moi.jl")
include("library/sampler/wrappers/qubotools.jl")

include("library/setup/error.jl")
include("library/setup/specs.jl")
include("library/setup/parse.jl")
include("library/setup/quote.jl")
include("library/setup/macro.jl")

export AbstractSampler
export ExactSampler, IdentitySampler, RandomSampler

include("library/drivers/ExactSampler.jl")
include("library/drivers/IdentitySampler.jl")
include("library/drivers/RandomSampler.jl")

end # module QUBODrivers
