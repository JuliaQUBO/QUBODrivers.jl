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
        _test_exact_sampler_public_status()
    end

    return nothing
end

function _exact_status_model(::Type{T}, domain, sense; constant = false, n = 2) where {T}
    model = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{T}())
    x, _ = MOI.add_constrained_variables(model, fill(domain, n))
    MOI.set(model, MOI.ObjectiveSense(), sense)
    affine = constant ? MOI.ScalarAffineTerm{T}[] : [
        MOI.ScalarAffineTerm{T}(T(-3), x[1]),
        MOI.ScalarAffineTerm{T}(T(2), x[2]),
    ]
    quadratic = constant ? MOI.ScalarQuadraticTerm{T}[] : [
        MOI.ScalarQuadraticTerm{T}(T(4), x[1], x[2]),
    ]
    f = MOI.ScalarQuadraticFunction{T}(quadratic, affine, T(5))
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    return model, x
end

function _test_exact_sampler_public_status()
    @testset "Public exhaustive status and original objectives" begin
        for T in (Float32, Float64), domain in (MOI.ZeroOne(), QUBODrivers.Spin()),
            sense in (MOI.MIN_SENSE, MOI.MAX_SENSE), constant in (false, true)

            source, x = _exact_status_model(T, domain, sense; constant)
            sampler = ExactSampler.Optimizer{T}()
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
            map = MOI.copy_to(sampler, source)
            MOI.optimize!(sampler)
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(sampler, MOI.ResultCount()) == 4
            @test MOI.get(sampler, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
            @test _solution_metadata(sampler)["termination_status"] == MOI.OPTIMAL
            values = domain isa MOI.ZeroOne ? (0, 1) : (-1, 1)
            oracle = [constant ? 5 : 5 - 3a + 2b + 4a*b for a in values for b in values]
            optimum = sense == MOI.MIN_SENSE ? minimum(oracle) : maximum(oracle)
            @test MOI.get(sampler, MOI.ObjectiveValue()) == optimum
            states = Set{Tuple{T,T}}()
            for row in 1:4
                a, b = [MOI.get(sampler, MOI.VariablePrimal(row), map[v]) for v in x]
                @test a in values && b in values
                @test MOI.get(sampler, MOI.ObjectiveValue(row)) ==
                      (constant ? 5 : 5 - 3a + 2b + 4a*b)
                push!(states, (a, b))
            end
            @test length(states) == 4
            MOI.empty!(sampler)
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
            @test MOI.get(sampler, MOI.ResultCount()) == 0
            # An empty model has one complete empty assignment, not no result.
            # QUBOTools' MOI parser requires a domain constraint; use its public
            # model API to represent the zero-variable constant explicitly.
            QUBODrivers.set_model!(sampler, QUBOTools.Model{VI,T,Int}(;
                offset = T(5), sense = sense == MOI.MIN_SENSE ? :min : :max,
                domain = domain isa MOI.ZeroOne ? :bool : :spin))
            MOI.optimize!(sampler)
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(sampler, MOI.ResultCount()) == 1
            @test MOI.get(sampler, MOI.ObjectiveValue()) == 5
        end
    end

    @testset "Failure, incomplete postprocessing and reused optimizers" begin
        source, _ = _exact_status_model(Float64, MOI.ZeroOne(), MOI.MIN_SENSE)
        sampler = ExactSampler.Optimizer()
        MOI.copy_to(sampler, source)
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (_, _) -> error("status failure"))
        @test_throws QUBODrivers._PostSampleCallbackError MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OTHER_ERROR

        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (_, _) -> throw(InterruptException()))
        @test_throws QUBODrivers._PostSampleCallbackError MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) != MOI.OPTIMAL

        # Removing the optimum can retain the source's metadata; it cannot retain
        # the public exhaustive certificate for the transformed returned result.
        MOI.set(sampler, QUBODrivers.PostSampleTransform(), true)
        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (samples, _) ->
            QUBOTools.SampleSet{Float64,Int}(collect(samples)[end:end];
                metadata = deepcopy(QUBOTools.metadata(samples)),
                sense = QUBOTools.sense(samples), domain = QUBOTools.domain(samples)))
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.ResultCount()) == 1
        @test MOI.get(sampler, MOI.ObjectiveValue()) > 2
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED

        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (samples, _) ->
            QUBOTools.SampleSet{Float64,Int}(;
                metadata = deepcopy(QUBOTools.metadata(samples))))
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.ResultCount()) == 0
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OTHER_ERROR

        MOI.set(sampler, QUBODrivers.PostSampleCallback(), (samples, _) ->
            (QUBOTools.metadata(samples)["annotation"] = "complete"; nothing))
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
        MOI.set(sampler, QUBODrivers.PostSampleCallback(), nothing)
        MOI.optimize!(sampler)
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OPTIMAL
    end

    @testset "Heuristic metadata is not a public certificate" begin
        source, _ = _exact_status_model(Float64, MOI.ZeroOne(), MOI.MIN_SENSE)
        for constructor in (RandomSampler.Optimizer, IdentitySampler.Optimizer)
            sampler = constructor()
            MOI.copy_to(sampler, source)
            for x in MOI.get(sampler, MOI.ListOfVariableIndices())
                MOI.set(sampler, MOI.VariablePrimalStart(), x, 0.0)
            end
            MOI.optimize!(sampler)
            QUBOTools.metadata(QUBOTools.solution(sampler))["termination_status"] = MOI.OPTIMAL
            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        end
    end
    return nothing
end
