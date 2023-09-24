function _test_automatic_interface(::Function, ::Type{S}) where {S<:AbstractSampler}
    Test.@testset "QUBODrivers (Automatic)" verbose = true begin
        Test.@test hasmethod(QUBODrivers.sample, (S,))
    end
end