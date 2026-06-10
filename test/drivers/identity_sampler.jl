function _is_spin(model)
    return (VI, Spin) ∈ MOI.get(model, MOI.ListOfConstraintTypesPresent())
end

function _test_identity_sampler_metadata_schema()
    @testset "Metadata schema" begin
        model = MOI.instantiate(IdentitySampler.Optimizer; with_bridge_type = Float64)
        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 1))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{VI}(), x[1])
        MOI.set(model, MOI.VariablePrimalStart(), x[1], 1.0)
        MOI.optimize!(model)

        _assert_sampler_metadata_schema(
            _solution_metadata(model);
            algorithm_name        = "Identity Sampler",
            execution_mode        = "warm_start",
            number_of_reads       = 1,
            optimizer_evaluations = 1,
            final_number_of_reads = 1,
            status                = "locally_solved",
            termination_status    = MOI.LOCALLY_SOLVED,
        )
    end

    return nothing
end

function test_identiy_sampler()
    QUBODrivers.test(IdentitySampler.Optimizer) do model
        if _is_spin(model)
            for (i, x) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
                MOI.set(model, MOI.VariablePrimalStart(), x, iseven(i) ? -1.0 : 1.0)
            end
        else # !is spin
            for (i, x) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
                MOI.set(model, MOI.VariablePrimalStart(), x, iseven(i) ? 0.0 : 1.0)
            end
        end
    end

    @testset "□ IdentitySampler" verbose = true begin
        _test_identity_sampler_metadata_schema()
    end

    return nothing
end
