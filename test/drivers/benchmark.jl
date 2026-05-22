function _benchmark_source_model(::Type{T} = Float64) where {T}
    model = MOI.Utilities.Model{T}()
    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), 2))

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(
        model,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{T}}(),
        MOI.ScalarAffineFunction{T}(
            MOI.ScalarAffineTerm{T}[
                MOI.ScalarAffineTerm{T}(-one(T), x[1]),
                MOI.ScalarAffineTerm{T}(2one(T), x[2]),
            ],
            zero(T),
        ),
    )

    return model
end

function test_benchmark_helper()
    @testset "□ Benchmark Helper" begin
        exact = QUBODrivers.benchmark(ExactSampler.Optimizer)

        @test exact.solver == "Exact Sampler"
        @test exact.objective_sense == MOI.MIN_SENSE
        @test exact.variables == 3
        @test exact.result_count == 8
        @test length(exact.objective_values) == exact.result_count
        @test exact.read_counts == ones(Int, exact.result_count)
        @test exact.objective_summary.minimum == minimum(exact.objective_values)
        @test exact.objective_summary.maximum == maximum(exact.objective_values)
        @test exact.objective_summary.mean ≈ sum(exact.objective_values) / exact.result_count
        @test exact.objective_summary.total_reads == sum(exact.read_counts)
        @test sum(values(exact.objective_summary.histogram)) == exact.result_count
        @test exact.best_objective ≈ -1.0
        @test exact.best_index in 1:exact.result_count
        @test exact.best_state ≈ [0.0, 0.0, 1.0] ||
              exact.best_state ≈ [0.0, 1.0, 0.0] ||
              exact.best_state ≈ [1.0, 0.0, 0.0]
        @test exact.solve_time >= 0
        @test exact.wall_time >= 0
        @test exact.termination_status == MOI.LOCALLY_SOLVED
        @test exact.raw_status == "optimal"

        random = QUBODrivers.benchmark(RandomSampler.Optimizer) do model
            MOI.set(model, MOI.RawOptimizerAttribute("num_reads"), 1)
            MOI.set(model, MOI.RawOptimizerAttribute("seed"), 1)
        end

        @test random.solver == "Random Sampler"
        @test random.result_count == 1
        @test length(random.objective_values) == random.result_count
        @test random.read_counts == [1]
        @test random.objective_summary.minimum == only(random.objective_values)
        @test random.objective_summary.maximum == only(random.objective_values)
        @test random.objective_summary.mean == only(random.objective_values)
        @test random.objective_summary.total_reads == 1
        @test random.objective_summary.histogram == Dict(only(random.objective_values) => 1)
        @test random.best_index in 1:random.result_count
        @test random.best_objective == minimum(random.objective_values)
        @test length(random.best_state) == random.variables

        random_many = QUBODrivers.benchmark(RandomSampler.Optimizer) do model
            MOI.set(model, MOI.RawOptimizerAttribute("num_reads"), 100)
            MOI.set(model, MOI.RawOptimizerAttribute("seed"), 1)
        end

        @test random_many.result_count <= 100
        @test sum(random_many.read_counts) == 100
        @test random_many.objective_summary.total_reads == 100
        @test sum(values(random_many.objective_summary.histogram)) == 100
        @test random_many.objective_summary.mean ≈
              sum(
                  value * reads for
                  (value, reads) in zip(random_many.objective_values, random_many.read_counts)
              ) / 100

        empty_random = QUBODrivers.benchmark(RandomSampler.Optimizer) do model
            MOI.set(model, MOI.RawOptimizerAttribute("num_reads"), 0)
            MOI.set(model, MOI.RawOptimizerAttribute("seed"), 1)
        end

        @test empty_random.result_count == 0
        @test isempty(empty_random.objective_values)
        @test isempty(empty_random.read_counts)
        @test empty_random.objective_summary.minimum === nothing
        @test empty_random.objective_summary.maximum === nothing
        @test empty_random.objective_summary.mean === nothing
        @test empty_random.objective_summary.total_reads == 0
        @test isempty(empty_random.objective_summary.histogram)
        @test empty_random.best_index === nothing
        @test empty_random.best_objective === nothing
        @test empty_random.best_state === nothing

        max_exact = QUBODrivers.benchmark(ExactSampler.Optimizer; objective_sense = MOI.MAX_SENSE)

        @test max_exact.objective_sense == MOI.MAX_SENSE
        @test max_exact.best_objective ≈ 9.0
        @test max_exact.best_state ≈ [1.0, 1.0, 1.0]

        source = _benchmark_source_model()
        custom = QUBODrivers.benchmark(ExactSampler.Optimizer, source)

        @test custom.variables == 2
        @test custom.result_count == 4
        @test custom.read_counts == ones(Int, custom.result_count)
        @test custom.objective_summary.minimum ≈ -1.0
        @test custom.objective_summary.maximum ≈ 2.0
        @test custom.objective_summary.total_reads == 4
        @test custom.best_objective ≈ -1.0
        @test custom.best_state ≈ [1.0, 0.0]

        configured_raw_sampler = Ref(false)
        configured = QUBODrivers.benchmark(IdentitySampler.Optimizer, source) do sampler
            configured_raw_sampler[] = sampler isa IdentitySampler.Optimizer{Float64}
            @test MOI.get(sampler, MOI.NumberOfVariables()) == 2

            x = MOI.get(sampler, MOI.ListOfVariableIndices())
            MOI.set(sampler, MOI.VariablePrimalStart(), x[1], 1.0)
            MOI.set(sampler, MOI.VariablePrimalStart(), x[2], 0.0)
        end

        @test configured_raw_sampler[]
        @test configured.result_count == 1
        @test configured.best_objective ≈ -1.0
        @test configured.best_state ≈ [1.0, 0.0]
    end

    return nothing
end
