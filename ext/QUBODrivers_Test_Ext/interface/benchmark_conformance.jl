const _BENCHMARK_CONFORMANCE_FINAL_READS = 5
const _BENCHMARK_CONFORMANCE_TIME_LIMIT = 1.0
const _BENCHMARK_CONFORMANCE_TIME_LIMIT_SLACK = 5.0
const _BENCHMARK_CONFORMANCE_TIME_TOL = 1.0e-6
const _BENCHMARK_ALLOWED_TERMINATION_STATUSES = Set([
    MOI.OPTIMAL,
    MOI.LOCALLY_SOLVED,
    MOI.TIME_LIMIT,
    MOI.ITERATION_LIMIT,
    MOI.OTHER_LIMIT,
])

function _run_seed_determinism(determinism, ::Type{S}) where {S<:QUBODrivers.AbstractSampler}
    if determinism === :auto
        return QUBODrivers.supports_seed(S)
    elseif determinism isa Bool
        return determinism
    else
        error("`determinism` must be `:auto`, `true`, or `false`")
    end
end

function _benchmark_conformance_model(
    config!::Function,
    sampler::Type{S};
    final_number_of_reads = _BENCHMARK_CONFORMANCE_FINAL_READS,
    seed = nothing,
    time_limit = nothing,
) where {T,S<:QUBODrivers.AbstractSampler{T}}
    model = MOI.instantiate(sampler; with_bridge_type = T)

    Q = T[
        1 -2 3
        0 -1 -2
        0 0 2
    ]
    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 3))

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{SQF{T}}(), x' * Q * x)

    config!(model)

    if !isnothing(final_number_of_reads)
        MOI.set(model, QUBODrivers.FinalNumberOfReads(), final_number_of_reads)
    end

    if !isnothing(seed)
        MOI.set(model, QUBODrivers.RandomSeed(), seed)
    end

    if !isnothing(time_limit)
        MOI.set(model, MOI.TimeLimitSec(), time_limit)
    end

    return model
end

function _benchmark_conformance_solution(model)
    raw = MOI.get(model, MOI.RawSolver())

    return QUBOTools.solution(raw)
end

function _optimize_benchmark_conformance_model(args...; kwargs...)
    model = _benchmark_conformance_model(args...; kwargs...)

    MOI.optimize!(model)

    return model, _benchmark_conformance_solution(model)
end

function _sampleset_states_and_values(sampleset)
    return [(copy(QUBOTools.state(sample)), QUBOTools.value(sample)) for sample in sampleset]
end

function _test_benchmark_metadata_conformance(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Metadata Conformance" begin
        _, sampleset = _optimize_benchmark_conformance_model(config!, sampler)
        violations = QUBODrivers.validate_metadata(sampleset)

        Test.@test isempty(violations)
    end

    return nothing
end

function _test_benchmark_timing_sanity(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Timing Sanity" begin
        model, sampleset = _optimize_benchmark_conformance_model(config!, sampler)
        metadata = QUBOTools.metadata(sampleset)
        time = get(metadata, "time", nothing)

        Test.@test time isa AbstractDict

        if time isa AbstractDict
            total = get(time, "total", nothing)
            effective = get(time, "effective", nothing)

            Test.@test total isa Real
            Test.@test effective isa Real

            if total isa Real && effective isa Real
                Test.@test total > 0
                Test.@test effective > 0
                Test.@test effective <= total * (1 + _BENCHMARK_CONFORMANCE_TIME_TOL)
            end
        end

        Test.@test MOI.get(model, MOI.SolveTimeSec()) >= 0
    end

    return nothing
end

function _test_benchmark_seed_determinism(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Seed Determinism" begin
        first_model, first_sampleset =
            _optimize_benchmark_conformance_model(config!, sampler; seed = 1)
        second_model, second_sampleset =
            _optimize_benchmark_conformance_model(config!, sampler; seed = 1)

        Test.@test MOI.get(first_model, MOI.ResultCount()) ==
                   MOI.get(second_model, MOI.ResultCount())
        Test.@test _sampleset_states_and_values(first_sampleset) ==
                   _sampleset_states_and_values(second_sampleset)
    end

    return nothing
end

function _test_benchmark_reads_semantics(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Reads Semantics" begin
        k = _BENCHMARK_CONFORMANCE_FINAL_READS
        _, sampleset =
            _optimize_benchmark_conformance_model(config!, sampler; final_number_of_reads = k)

        Test.@test !QUBODrivers.honors_final_reads(S) || length(sampleset) <= k
    end

    return nothing
end

function _test_benchmark_time_limit_acceptance(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Time Limit Acceptance" begin
        limit = _BENCHMARK_CONFORMANCE_TIME_LIMIT
        model = _benchmark_conformance_model(
            config!,
            sampler;
            final_number_of_reads = _BENCHMARK_CONFORMANCE_FINAL_READS,
        )

        Test.@test MOI.set(model, MOI.TimeLimitSec(), limit) === nothing

        if QUBODrivers.enforces_time_limit(S)
            MOI.optimize!(model)
            sampleset = _benchmark_conformance_solution(model)
            total = QUBOTools.metadata(sampleset)["time"]["total"]

            Test.@test total <= limit * _BENCHMARK_CONFORMANCE_TIME_LIMIT_SLACK
        end
    end

    return nothing
end

function _test_benchmark_termination_status(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "Termination Status" begin
        model, _ = _optimize_benchmark_conformance_model(config!, sampler)

        Test.@test MOI.get(model, MOI.TerminationStatus()) in _BENCHMARK_ALLOWED_TERMINATION_STATUSES
    end

    return nothing
end

function _test_benchmark_auto_configure(config!::Function, sampler::Type{S}) where {S}
    Test.@testset "AutoConfigure Acceptance" begin
        model_off = _benchmark_conformance_model(config!, sampler)
        if MOI.supports(model_off, QUBODrivers.AutoConfigure())
            Test.@test MOI.get(model_off, QUBODrivers.AutoConfigure()) === false
            MOI.optimize!(model_off)
            sampleset_off = _benchmark_conformance_solution(model_off)
            Test.@test !haskey(QUBOTools.metadata(sampleset_off), "auto_configure")

            model_on = _benchmark_conformance_model(
                config!,
                sampler;
                final_number_of_reads = nothing,
            )
            Test.@test MOI.set(model_on, QUBODrivers.AutoConfigure(), true) === nothing
            Test.@test MOI.get(model_on, QUBODrivers.AutoConfigure()) === true
            MOI.optimize!(model_on)
            sampleset_on = _benchmark_conformance_solution(model_on)
            metadata_on = QUBOTools.metadata(sampleset_on)
            Test.@test haskey(metadata_on, "auto_configure")
            auto_meta = metadata_on["auto_configure"]
            Test.@test auto_meta isa AbstractDict
            Test.@test auto_meta["enabled"] === true
            Test.@test auto_meta["supported"] === QUBODrivers.supports_auto_configure(S)
            Test.@test auto_meta["num_variables"] == 3
            Test.@test auto_meta["parameters"] isa AbstractDict
            Test.@test isempty(QUBODrivers.validate_metadata(sampleset_on))
        else
            Test.@test !QUBODrivers.supports_auto_configure(S)
        end
    end

    return nothing
end

function _test_benchmark_conformance(
    config!::Function,
    sampler::Type{S};
    metadata_conformance::Bool,
    timing_sanity::Bool,
    determinism,
    reads_semantics::Bool,
    time_limit_acceptance::Bool,
    termination_status::Bool,
) where {S<:QUBODrivers.AbstractSampler}
    Test.@testset "→ Benchmark Conformance" begin
        if metadata_conformance
            _test_benchmark_metadata_conformance(config!, sampler)
            _test_benchmark_auto_configure(config!, sampler)
        end

        if timing_sanity
            _test_benchmark_timing_sanity(config!, sampler)
        end

        if _run_seed_determinism(determinism, sampler)
            _test_benchmark_seed_determinism(config!, sampler)
        end

        if reads_semantics
            _test_benchmark_reads_semantics(config!, sampler)
        end

        if time_limit_acceptance
            _test_benchmark_time_limit_acceptance(config!, sampler)
        end

        if termination_status
            _test_benchmark_termination_status(config!, sampler)
        end
    end

    return nothing
end
