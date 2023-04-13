function __test_basic_bool_min(
    config!::Function,
    sampler::Type{S},
    n::Integer,
    Q::Matrix{T},
) where {T,S<:AbstractSampler{T}}
    Test.@testset "▷ Bool ⋄ Min" begin
        model = MOI.instantiate(sampler; with_bridge_type = T)

        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{SQF{T}}(),
            SQF{T}(
                SQT{T}[SQT{T}(Q[i, j], x[i], x[j]) for i = 1:n for j = 1:n if i != j],
                SAT{T}[SAT{T}(Q[i, i], x[i]) for i = 1:n],
                zero(T),
            ),
        )

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0

        for i = 1:MOI.get(model, MOI.ResultCount())
            xi = MOI.get.(model, MOI.VariablePrimal(i), x)
            yi = MOI.get(model, MOI.ObjectiveValue(i))

            if xi ≈ [0, 0, 1] || xi ≈ [0, 1, 0] || xi ≈ [1, 0, 0]
                Test.@test yi ≈ -1.0
            elseif xi ≈ [0, 0, 0]
                Test.@test yi ≈ 0.0
            elseif xi ≈ [0, 1, 1] || xi ≈ [1, 1, 0] || xi ≈ [1, 0, 1]
                Test.@test yi ≈ 2.0
            elseif xi ≈ [1, 1, 1]
                Test.@test yi ≈ 9.0
            else
                Test.@test false
            end
        end
    end

    return nothing
end

function __test_basic_bool_max(
    config!::Function,
    sampler::Type{S},
    n::Integer,
    Q::Matrix{T},
) where {T,S<:AbstractSampler{T}}
    Test.@testset "▷ Bool ⋄ Max" begin
        model = MOI.instantiate(sampler; with_bridge_type = T)

        x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{SQF{T}}(),
            SQF{T}(
                SQT{T}[SQT{T}(Q[i, j], x[i], x[j]) for i = 1:n for j = 1:n if i != j],
                SAT{T}[SAT{T}(Q[i, i], x[i]) for i = 1:n],
                zero(T),
            ),
        )

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0

        for i = 1:MOI.get(model, MOI.ResultCount())
            xi = MOI.get.(model, MOI.VariablePrimal(i), x)
            yi = MOI.get(model, MOI.ObjectiveValue(i))

            if xi ≈ [1, 1, 1]
                Test.@test yi ≈ 9.0
            elseif xi ≈ [0, 1, 1] || xi ≈ [1, 1, 0] || xi ≈ [1, 0, 1]
                Test.@test yi ≈ 2.0
            elseif xi ≈ [0, 0, 0]
                Test.@test yi ≈ 0.0
            elseif xi ≈ [0, 0, 1] || xi ≈ [0, 1, 0] || xi ≈ [1, 0, 0]
                Test.@test yi ≈ -1.0
            else
                Test.@test false
            end
        end
    end

    return nothing
end

function __test_basic_spin_min(
    config!::Function,
    sampler::Type{S},
    n::Integer,
    h::Vector{T},
    J::Matrix{T},
) where {T,S<:AbstractSampler{T}}
    Test.@testset "▷ Spin ⋄ Min" begin
        # Build Model
        model = MOI.instantiate(sampler; with_bridge_type = T)

        s, _ = MOI.add_constrained_variables(model, fill(Spin(), n))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{SQF{T}}(),
            SQF{T}(
                SQT{T}[SQT{T}(J[i, j], s[i], s[j]) for i = 1:n for j = 1:n],
                SAT{T}[SAT{T}(h[i], s[i]) for i = 1:n],
                zero(T),
            ),
        )

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0

        for i = 1:MOI.get(model, MOI.ResultCount())
            si = MOI.get.(model, MOI.VariablePrimal(i), s)
            Hi = MOI.get(model, MOI.ObjectiveValue(i))

            if si ≈ [↓, ↓, ↑] || si ≈ [↓, ↑, ↓] || si ≈ [↑, ↓, ↓]
                Test.@test Hi ≈ -5.0
            elseif si ≈ [↑, ↑, ↓] || si ≈ [↑, ↓, ↑] || si ≈ [↓, ↑, ↑]
                Test.@test Hi ≈ -3.0
            elseif si ≈ [↓, ↓, ↓]
                Test.@test Hi ≈ 9.0
            elseif si ≈ [↑, ↑, ↑]
                Test.@test Hi ≈ 15.0
            else
                Test.@test false
            end
        end
    end

    return nothing
end

function __test_basic_spin_max(
    config!::Function,
    sampler::Type{S},
    n::Integer,
    h::Vector{T},
    J::Matrix{T},
) where {T,S<:AbstractSampler{T}}
    Test.@testset "▷ Spin ⋄ Min" begin
        # Build Model
        model = MOI.instantiate(sampler; with_bridge_type = T)

        s, _ = MOI.add_constrained_variables(model, fill(Spin(), n))

        MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{SQF{T}}(),
            SQF{T}(
                SQT{T}[SQT{T}(J[i, j], s[i], s[j]) for i = 1:n for j = 1:n],
                SAT{T}[SAT{T}(h[i], s[i]) for i = 1:n],
                zero(T),
            ),
        )

        config!(model)

        MOI.optimize!(model)

        Test.@test MOI.get(model, MOI.ResultCount()) > 0

        for i = 1:MOI.get(model, MOI.ResultCount())
            si = MOI.get.(model, MOI.VariablePrimal(i), s)
            Hi = MOI.get(model, MOI.ObjectiveValue(i))

            if si ≈ [↑, ↑, ↑]
                Test.@test Hi ≈ 15.0
            elseif si ≈ [↓, ↓, ↓]
                Test.@test Hi ≈ 9.0
            elseif si ≈ [↑, ↑, ↓] || si ≈ [↑, ↓, ↑] || si ≈ [↓, ↑, ↑]
                Test.@test Hi ≈ -3.0
            elseif si ≈ [↓, ↓, ↑] || si ≈ [↓, ↑, ↓] || si ≈ [↑, ↓, ↓]
                Test.@test Hi ≈ -5.0
            else
                Test.@test false
            end
        end
    end

    return nothing
end

function __test_basic_examples(
    config!::Function,
    sampler::Type{S},
) where {T,S<:AbstractSampler{T}}
    Test.@testset "⊚ Basic ⊚" verbose = true begin
        # Problem size
        n = 3

        # QUBO Matrix
        Q = T[-1 2 2; 2 -1 2; 2 2 -1]

        # Ising Hamiltonian
        J = T[0 4 4; 0 0 4; 0 0 0]
        h = T[-1; -1; -1]

        __test_basic_bool_min(config!, sampler, n, Q)
        __test_basic_bool_max(config!, sampler, n, Q)
        __test_basic_spin_min(config!, sampler, n, h, J)
        __test_basic_spin_max(config!, sampler, n, h, J)
    end

    return nothing
end