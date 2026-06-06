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

function _random_solution(model)
    raw = MOI.get(model, MOI.RawSolver())

    return QUBOTools.solution(raw)
end

function _objective_rows(sampleset::SampleSet{T,U}; offset::T = zero(T)) where {T,U}
    return [
        Dict{String,Any}(
            "rank"                  => i,
            "state"                 => copy(QUBOTools.state(sample)),
            "raw_value"             => QUBOTools.value(sample),
            "scaled_value"          => QUBOTools.value(sample),
            "offset_adjusted_value" => QUBOTools.value(sample) + offset,
            "scale"                 => one(T),
            "offset"                => offset,
            "sense"                 => String(QUBOTools.sense(sampleset)),
            "domain"                => String(QUBOTools.domain(sampleset)),
        ) for (i, sample) in enumerate(sampleset)
    ]
end

function _offset_sampleset_values(sampleset::SampleSet{T,U}, offset::T) where {T,U}
    samples = Sample{T,U}[
        Sample{T,U}(
            copy(QUBOTools.state(sample)),
            QUBOTools.value(sample) + offset,
            QUBOTools.reads(sample),
        ) for sample in sampleset
    ]
    metadata = QUBOTools.metadata(sampleset)
    objectives = get!(metadata, "objectives") do
        Dict{String,Any}()
    end
    objectives["shifted"] = _objective_rows(sampleset; offset)

    return SampleSet{T,U}(
        samples;
        metadata,
        sense  = QUBOTools.sense(sampleset),
        domain = QUBOTools.domain(sampleset),
    )
end

function _optimize_error(model)
    try
        MOI.optimize!(model)

        return nothing
    catch err
        return err
    end
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

        default_metadata = _solution_metadata(default_model)

        @test _random_total_reads(default_model) == 7
        @test !haskey(default_metadata, "postprocess")
        _assert_sampler_metadata_schema(
            default_metadata;
            algorithm_name        = "Random Sampler",
            execution_mode        = "random_sampling",
            number_of_reads       = 7,
            optimizer_evaluations = 7,
            final_number_of_reads = 7,
            status                = "locally_solved",
            termination_status    = MOI.LOCALLY_SOLVED,
        )

        override_model = _build_random_reads_model(; num_reads = 7, final_num_reads = 3)

        MOI.optimize!(override_model)

        override_metadata = _solution_metadata(override_model)

        @test _random_total_reads(override_model) == 3
        _assert_sampler_metadata_schema(
            override_metadata;
            algorithm_name        = "Random Sampler",
            execution_mode        = "random_sampling",
            number_of_reads       = 3,
            optimizer_evaluations = 3,
            final_number_of_reads = 3,
            status                = "locally_solved",
            termination_status    = MOI.LOCALLY_SOLVED,
        )
    end

    return nothing
end

function _test_random_sampler_post_sample_annotation()
    @testset "PostSampleCallback annotation" begin
        model = _build_random_reads_model(; num_reads = 2, final_num_reads = 2)
        callback = (sampleset, sampler) -> begin
            QUBOTools.metadata(sampleset)["annotation"] = Dict{String,Any}(
                "samples"   => length(sampleset),
                "variables" => MOI.get(sampler, MOI.NumberOfVariables()),
            )
            objectives = get!(QUBOTools.metadata(sampleset), "objectives") do
                Dict{String,Any}()
            end
            objectives["callback"] = _objective_rows(sampleset)

            return nothing
        end

        MOI.set(model, QUBODrivers.PostSampleCallback(), callback)
        MOI.optimize!(model)

        metadata = _solution_metadata(model)

        @test metadata["annotation"]["samples"] == MOI.get(model, MOI.ResultCount())
        @test metadata["annotation"]["variables"] == 2
        @test length(metadata["objectives"]["callback"]) == MOI.get(model, MOI.ResultCount())
        @test haskey(first(metadata["objectives"]["callback"]), "offset_adjusted_value")
        @test metadata["postprocess"]["callback"]["transform"] === false
        @test metadata["postprocess"]["callback"]["transformed"] === false
        @test haskey(metadata["postprocess"]["callback"], "time")
        @test !haskey(metadata["postprocess"], "raw_samples")
    end

    return nothing
end

function _test_random_sampler_post_sample_transform()
    @testset "PostSampleCallback transform" begin
        model = _build_random_reads_model(; num_reads = 1, final_num_reads = 1)
        callback = (sampleset, _) -> _offset_sampleset_values(sampleset, 10.0)

        MOI.set(model, QUBODrivers.PostSampleCallback(), callback)
        MOI.set(model, QUBODrivers.PostSampleTransform(), true)
        MOI.optimize!(model)

        solution = _random_solution(model)
        metadata = QUBOTools.metadata(solution)
        raw_sampleset = metadata["postprocess"]["raw_samples"]
        raw_samples = raw_sampleset["samples"]

        @test metadata["objectives"]["shifted"][1]["offset"] == 10.0
        @test raw_sampleset["format"] == "QUBODrivers.raw_samples"
        @test raw_sampleset["schema_version"] == 1
        @test raw_sampleset["sense"] == String(QUBOTools.sense(solution))
        @test raw_sampleset["domain"] == String(QUBOTools.domain(solution))
        @test metadata["postprocess"]["callback"]["transform"] === true
        @test metadata["postprocess"]["callback"]["transformed"] === true
        @test length(raw_samples) == length(solution)

        for i in eachindex(raw_samples)
            @test raw_samples[i]["state"] == QUBOTools.state(solution[i])
            @test raw_samples[i]["reads"] == QUBOTools.reads(solution[i])
            @test QUBOTools.value(solution[i]) == raw_samples[i]["value"] + 10.0
        end
    end

    return nothing
end

function _test_random_sampler_post_sample_transform_gate()
    @testset "PostSampleCallback transform gate" begin
        model = _build_random_reads_model(; num_reads = 1, final_num_reads = 1)
        callback = (sampleset, _) -> _offset_sampleset_values(sampleset, 10.0)

        MOI.set(model, QUBODrivers.PostSampleCallback(), callback)

        err = _optimize_error(model)
        msg = sprint(showerror, err)

        @test err isa ErrorException
        @test occursin("PostSampleTransform is false", msg)
    end

    return nothing
end

function _test_random_sampler_post_sample_error()
    @testset "PostSampleCallback error" begin
        model = _build_random_reads_model(; num_reads = 1, final_num_reads = 1)
        callback = (_, _) -> error("callback boom")

        MOI.set(model, MOI.RawOptimizerAttribute("post_sample_callback"), callback)

        err = _optimize_error(model)
        msg = sprint(showerror, err)

        @test err isa QUBODrivers._PostSampleCallbackError
        @test err.error isa ErrorException
        @test occursin("PostSampleCallback failed", msg)
        @test occursin("callback boom", msg)
    end

    return nothing
end

function test_random_sampler()
    QUBODrivers.test(RandomSampler.Optimizer)

    @testset "□ RandomSampler" verbose = true begin
        _test_random_sampler_final_number_of_reads_attribute()
        _test_random_sampler_final_number_of_reads_sampling()
        _test_random_sampler_post_sample_annotation()
        _test_random_sampler_post_sample_transform()
        _test_random_sampler_post_sample_transform_gate()
        _test_random_sampler_post_sample_error()
    end

    return nothing
end
