function _test_automatic_interface(::Function, ::Type{S}) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "QUBODrivers (Automatic)" verbose = true begin
        Test.@test hasmethod(QUBODrivers.sample, (S,))
    end

    return nothing
end