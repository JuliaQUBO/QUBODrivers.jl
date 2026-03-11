function _test_moi_interface(config!::Function, ::Type{S}) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "MOI" verbose = true begin
        Test.@testset "`optimize!` Interface" begin
            # Emptiness
            Test.@test hasmethod(MOI.empty!, (S,))
            Test.@test hasmethod(MOI.is_empty, (S,))
            # Optimize! / Copy-To
            Test.@test hasmethod(MOI.optimize!, (S,)) && hasmethod(MOI.copy_to, (S, MOI.ModelLike)) ||
                       hasmethod(MOI.optimize!, (S, MOI.ModelLike))
        end

        _test_moi_interface_instantiate(config!, S)
        _test_moi_interface_attributes(config!, S)
        _test_moi_fixed_variable_contracts(config!, S)
        _test_fixed_variable_reduction_helpers()
    end

    return nothing
end

function _test_moi_interface_instantiate(config!::Function, ::Type{S}) where {T,S<:QUBODrivers.AbstractSampler{T}}
    let sampler = S()
        config!(sampler)

        Test.@test true
    end

    return nothing
end

function _test_moi_interface_attributes(config!::Function, ::Type{S}) where {T,S<:QUBODrivers.AbstractSampler{T}}
    Test.@testset "Attributes" begin
        # Basic Attributes
        Test.@test hasmethod(MOI.get, (S, MOI.SolverName))
        Test.@test hasmethod(MOI.get, (S, MOI.SolverVersion))
        Test.@test hasmethod(MOI.get, (S, MOI.RawSolver))

        Test.@testset "Attribute Access" begin
            let sampler = S()
                config!(sampler)
                
                Test.@test MOI.get(sampler, MOI.SolverName())    isa AbstractString
                Test.@test MOI.get(sampler, MOI.SolverVersion()) isa VersionNumber
            end
        end
    end

    return nothing
end
