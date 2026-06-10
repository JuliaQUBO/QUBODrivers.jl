function _test_exact_sampler_metadata_schema()
    @testset "Metadata schema" begin
        model = MOI.instantiate(ExactSampler.Optimizer; with_bridge_type = Float64)
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 1))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{VI}(), x[1])
        MOI.optimize!(model)

        _assert_sampler_metadata_schema(
            _solution_metadata(model);
            algorithm_name        = "Exact Sampler",
            execution_mode        = "exhaustive_search",
            number_of_reads       = 2,
            optimizer_evaluations = 2,
            final_number_of_reads = 2,
            status                = "optimal",
            termination_status    = MOI.OPTIMAL,
        )
    end

    return nothing
end

function test_exact_sampler()
    QUBODrivers.test(ExactSampler.Optimizer)

    @testset "□ ExactSampler" verbose = true begin
        _test_exact_sampler_metadata_schema()
    end

    return nothing
end
