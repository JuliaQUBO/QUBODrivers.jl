const _UNSET_FINAL_NUMBER_OF_READS = Symbol("unset_final_number_of_reads")

function _build_random_reads_model(;
    num_reads::Integer,
    final_num_reads = _UNSET_FINAL_NUMBER_OF_READS,
    seed::Integer = 1,
)
    model = MOI.instantiate(RandomSampler.Optimizer; with_bridge_type = Float64)
    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 2))
    f = MOI.ScalarAffineFunction{Float64}(
        MOI.ScalarAffineTerm{Float64}[
            MOI.ScalarAffineTerm{Float64}(-1.0, x[1]),
            MOI.ScalarAffineTerm{Float64}(2.0, x[2]),
        ],
        0.0,
    )

    MOI.set(model, MOI.RawOptimizerAttribute("num_reads"), num_reads)
    MOI.set(model, MOI.RawOptimizerAttribute("seed"), seed)

    if final_num_reads !== _UNSET_FINAL_NUMBER_OF_READS
        MOI.set(model, QUBODrivers.FinalNumberOfReads(), final_num_reads)
    end

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

    return model
end

function _random_total_reads(model)
    return sum(
        MOI.get(model, QUBODrivers.QUBOTools_MOI.NumberOfReads(i)) for
        i in 1:MOI.get(model, MOI.ResultCount());
        init = 0,
    )
end

function _random_solution_metadata(model)
    raw = MOI.get(model, MOI.RawSolver())

    return QUBOTools.metadata(QUBOTools.solution(raw))
end

function _test_random_sampler_final_number_of_reads_attribute()
    @testset "FinalNumberOfReads attribute" begin
        sampler = RandomSampler.Optimizer()

        @test MOI.supports(sampler, QUBODrivers.FinalNumberOfReads())
        @test MOI.supports(sampler, MOI.RawOptimizerAttribute("final_num_reads"))
        @test MOI.get(sampler, QUBODrivers.FinalNumberOfReads()) == 1_000
        @test MOI.get(sampler, MOI.RawOptimizerAttribute("final_num_reads")) == 1_000
        @test QUBODrivers.final_number_of_reads(sampler) == 1_000

        MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 7)
        @test MOI.get(sampler, QUBODrivers.FinalNumberOfReads()) == 7

        MOI.set(sampler, QUBODrivers.FinalNumberOfReads(), 3)
        @test MOI.get(sampler, QUBODrivers.FinalNumberOfReads()) == 3
        @test MOI.get(sampler, MOI.RawOptimizerAttribute("final_num_reads")) == 3

        MOI.set(sampler, MOI.RawOptimizerAttribute("final_num_reads"), nothing)
        @test MOI.get(sampler, QUBODrivers.FinalNumberOfReads()) == 7

        @test_throws ErrorException MOI.set(sampler, QUBODrivers.FinalNumberOfReads(), -1)
    end

    return nothing
end

function _test_random_sampler_final_number_of_reads_sampling()
    @testset "FinalNumberOfReads sampling" begin
        default_model = _build_random_reads_model(; num_reads = 7)

        MOI.optimize!(default_model)

        default_metadata = _random_solution_metadata(default_model)

        @test _random_total_reads(default_model) == 7
        @test default_metadata["reads"]["number_of_reads"] == 7
        @test default_metadata["reads"]["final_number_of_reads"] == 7
        @test default_metadata["algorithm"]["name"] == "Random Sampler"
        @test default_metadata["backend"]["name"] == "QUBODrivers.jl"
        @test default_metadata["execution"]["mode"] == "random_sampling"
        @test default_metadata["optimizer"]["evaluations"] == 7
        @test haskey(default_metadata, "seeds")
        @test default_metadata["termination_status"] == MOI.LOCALLY_SOLVED

        override_model = _build_random_reads_model(; num_reads = 7, final_num_reads = 3)

        MOI.optimize!(override_model)

        override_metadata = _random_solution_metadata(override_model)

        @test _random_total_reads(override_model) == 3
        @test override_metadata["reads"]["number_of_reads"] == 7
        @test override_metadata["reads"]["final_number_of_reads"] == 3
        @test override_metadata["optimizer"]["evaluations"] == 3
    end

    return nothing
end

function test_random_sampler()
    QUBODrivers.test(RandomSampler.Optimizer)

    @testset "□ RandomSampler" verbose = true begin
        _test_random_sampler_final_number_of_reads_attribute()
        _test_random_sampler_final_number_of_reads_sampling()
    end

    return nothing
end
