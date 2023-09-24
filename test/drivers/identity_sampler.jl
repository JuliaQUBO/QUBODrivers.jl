function _is_spin(model)
    return (VI, Spin) ∈ MOI.get(model, MOI.ListOfConstraintTypesPresent())
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

    return nothing
end
