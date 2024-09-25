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
const QUBOTools_MOI = Base.get_extension(QUBOTools, :QUBOTools_MOI)
const Spin          = QUBOTools_MOI.Spin

import TOML

const __PROJECT__ = Ref{Union{String,Nothing}}(nothing)

function __project__()
    if isnothing(__PROJECT__[])
        proj_path = abspath(dirname(@__DIR__))
    
        @assert isdir(proj_path)
    
        __PROJECT__[] = proj_path
    end

    return __PROJECT__[]::String
end

const __VERSION__ = Ref{Union{VersionNumber,Nothing}}(nothing)

function __version__()::VersionNumber
    if isnothing(__VERSION__[])
        proj_file_path = abspath(__project__(), "Project.toml")

        @assert isfile(proj_file_path)

        proj_file_data = TOML.parsefile(proj_file_path)

        __VERSION__[] = VersionNumber(proj_file_data["version"])
    end

    return __VERSION__[]::VersionNumber
end

export MOI, Sample, SampleSet, Spin, ↓, ↑

include("interface/sampler.jl")
include("interface/attributes.jl")

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
