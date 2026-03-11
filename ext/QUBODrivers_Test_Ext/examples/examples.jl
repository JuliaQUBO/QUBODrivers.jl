include("basic.jl")
include("corner.jl")
include("fixed.jl")

function _test_examples(
    config!::Function,
    sampler::Type{S},
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "→ Examples" begin
        _test_basic_examples(config!, sampler)
        _test_corner_examples(config!, sampler)
        _test_fixed_variables(config!, sampler)
    end
    
    return nothing
end