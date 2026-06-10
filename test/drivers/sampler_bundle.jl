function _solution_metadata(model)
    raw = MOI.get(model, MOI.RawSolver())

    return QUBOTools.metadata(QUBOTools.solution(raw))
end

function _assert_sampler_metadata_schema(
    metadata;
    algorithm_name::String,
    execution_mode::String,
    final_number_of_reads::Integer,
    number_of_reads::Integer,
    optimizer_evaluations = nothing,
    status::String,
    termination_status,
)
    @test isempty(QUBODrivers.validate_metadata(metadata))
    @test metadata["origin"] isa String
    @test metadata["algorithm"]["name"] == algorithm_name
    @test haskey(metadata["backend"], "name")
    @test haskey(metadata["backend"], "version")
    @test metadata["execution"]["mode"] == execution_mode
    @test haskey(metadata["optimizer"], "iterations")
    @test metadata["optimizer"]["evaluations"] == optimizer_evaluations
    @test metadata["reads"]["number_of_reads"] == number_of_reads
    @test metadata["reads"]["final_number_of_reads"] == final_number_of_reads
    @test haskey(metadata, "seeds")
    @test metadata["time"]["total"] isa Real
    @test metadata["time"]["effective"] isa Real
    @test metadata["status"] == status
    @test metadata["termination_status"] == termination_status

    return nothing
end

include("exact_sampler.jl")
include("identity_sampler.jl")
include("mip_sampler.jl")
include("random_sampler.jl")
include("benchmark.jl")

function test_sampler_bundle()
    @testset "□ Utility Samplers Bundle" verbose = true begin
        test_exact_sampler()
        test_identiy_sampler()
        test_mip_sampler()
        test_random_sampler()
        test_benchmark_helper()
    end

    return nothing
end
