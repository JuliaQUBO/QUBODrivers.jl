include("basic.jl")
include("corner.jl")

function _test_examples(
    config!::Function,
    sampler::Type{S},
) where {S<:AbstractSampler}
    Test.@testset "→ Examples" begin
        _test_basic_examples(config!, sampler)
        _test_corner_examples(config!, sampler)
    end
    
    return nothing
end