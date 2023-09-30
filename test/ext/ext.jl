include("MOI_PythonCall.jl")

function test_extensions()
    @testset "□ Extensions" verbose = true begin
        test_moi_pythoncall_ext()
    end

    return nothing
end