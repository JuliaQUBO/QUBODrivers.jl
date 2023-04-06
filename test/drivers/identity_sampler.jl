function test_identiy_sampler()
    QUBODrivers.test(IdentitySampler.Optimizer) do model
        let is_spin =
                (model) -> begin
                    return (MOI.VariableIndex, Spin) ∈
                           MOI.get(model, MOI.ListOfConstraintTypesPresent())
                end

            if is_spin(model)
                for (i, x) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
                    MOI.set(model, MOI.VariablePrimalStart(), x, iseven(i) ? -1.0 : 1.0)
                end
            else # is spin
                for (i, x) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
                    MOI.set(model, MOI.VariablePrimalStart(), x, iseven(i) ? 0.0 : 1.0)
                end
            end
        end
    end

    return nothing
end