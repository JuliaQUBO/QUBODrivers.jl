module _PreprocessIntTestSampler
import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet
QUBODrivers.@setup Optimizer begin
    name    = "Preprocess Int Test Sampler"
    version = QUBODrivers.__version__()
end
QUBODrivers.supported_domains(::Type{<:Optimizer}) = Set{Symbol}([:bool, :spin, :int])
QUBODrivers.sample(sampler::Optimizer{T}) where {T} = SampleSet{T,Int}()
end

function test_preprocessing()
    @testset "→ Preprocessing (QUBOPreprocessing.jl)" verbose = true begin
        @testset "Attribute Normalization & Validation" begin
            sampler = ExactSampler.Optimizer{Float64}()

            @test MOI.supports(sampler, QUBODrivers.Preprocess())
            @test MOI.supports(sampler, MOI.RawOptimizerAttribute("preprocess"))
            @test MOI.get(sampler, QUBODrivers.Preprocess()) === :none
            @test MOI.get(sampler, MOI.RawOptimizerAttribute("preprocess")) === :none
            @test QUBODrivers.preprocess_rules(sampler) === :none

            for off_val in (false, nothing, :none, :off, "none", "false", "off", " NONE ")
                MOI.set(sampler, QUBODrivers.Preprocess(), off_val)
                @test MOI.get(sampler, QUBODrivers.Preprocess()) === :none
                @test QUBODrivers.preprocess_rules(sampler) === :none
            end

            for strong_val in (true, :strong, :all, "strong", "true", "all", " STRONG ")
                MOI.set(sampler, QUBODrivers.Preprocess(), strong_val)
                @test MOI.get(sampler, QUBODrivers.Preprocess()) === :strong
                @test QUBODrivers.preprocess_rules(sampler) === :strong
            end

            for rule in (:weak, :dominance, :elimination, :relations, :mixed, :identity)
                MOI.set(sampler, QUBODrivers.Preprocess(), rule)
                @test MOI.get(sampler, QUBODrivers.Preprocess()) === rule
                MOI.set(sampler, MOI.RawOptimizerAttribute("preprocess"), String(rule))
                @test MOI.get(sampler, QUBODrivers.Preprocess()) === rule
            end

            @test_throws ErrorException MOI.set(sampler, QUBODrivers.Preprocess(), :unknown_rule)
            @test_throws ErrorException MOI.set(sampler, QUBODrivers.Preprocess(), 123)
        end

        @testset "Complete Reduction (n_reduced == 0) & Large-n Exact Solve" begin
            # 25-variable chain/coercive model that reduces completely to 0 variables
            n = 25
            model = MOI.instantiate(ExactSampler.Optimizer{Float64}; with_bridge_type = Float64)
            x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

            terms = MOI.ScalarQuadraticTerm{Float64}[]
            affs  = MOI.ScalarAffineTerm{Float64}[]
            for i = 1:n
                # Strongly negative linear bias forces x[i] = 1
                push!(affs, MOI.ScalarAffineTerm(-10.0 * i, x[i]))
            end
            for i = 1:(n - 1)
                push!(terms, MOI.ScalarQuadraticTerm(-2.0, x[i], x[i + 1]))
            end

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                model,
                MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
                MOI.ScalarQuadraticFunction(terms, affs, 3.5),
            )
            MOI.set(model, QUBODrivers.Preprocess(), :strong)
            MOI.optimize!(model)

            raw_solver = MOI.get(model, MOI.RawSolver())
            @test QUBOTools.dimension(QUBOTools.backend(raw_solver)) == n
            @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(model, MOI.ResultCount()) == 1

            expected_obj = 3.5 - 10.0 * sum(1:n) - 2.0 * (n - 1)
            @test MOI.get(model, MOI.ObjectiveValue()) ≈ expected_obj
            for i = 1:n
                @test MOI.get(model, MOI.VariablePrimal(), x[i]) == 1.0
            end

            sol = QUBOTools.solution(raw_solver)
            meta = QUBOTools.metadata(sol)
            @test isempty(QUBODrivers.validate_metadata(sol))
            @test haskey(meta, "preprocess")
            @test meta["preprocess"]["enabled"] === true
            @test meta["preprocess"]["rules"] == "strong"
            @test meta["preprocess"]["original_variables"] == n
            @test meta["preprocess"]["reduced_variables"] == 0
            @test meta["preprocess"]["removed_variables"] == n
            @test meta["preprocess"]["reduction_steps"] >= n
            @test meta["preprocess"]["time"] >= 0.0
            @test meta["time"]["preprocess"] >= 0.0
            @test QUBODrivers.effective_time(sol) >= meta["time"]["preprocess"]
        end

        @testset "Partial Reduction Across Samplers, Domains, Senses & Scales" begin
            for sense in (MOI.MIN_SENSE, MOI.MAX_SENSE),
                use_spin in (false, true),
                rules in (:strong, :weak, :dominance, :elimination, :relations, :mixed, :identity)

                # Reference solve without preprocessing
                ref_model = MOI.instantiate(ExactSampler.Optimizer{Float64}; with_bridge_type = Float64)
                vars_ref = if use_spin
                    first(MOI.add_constrained_variables(ref_model, fill(QUBODrivers.Spin(), 5)))
                else
                    first(MOI.add_constrained_variables(ref_model, fill(MOI.ZeroOne(), 5)))
                end

                # Build a 5-variable model with decimal/half-integer coefficients where:
                # - variables 1 and 2 have strong coercive fields (fixed by dominance)
                # - variable 3 is degree-1 coupled to variable 4 (eliminated)
                # - variables 4 and 5 form a coupled pair
                q_terms_ref = [
                    MOI.ScalarQuadraticTerm(1.0, vars_ref[1], vars_ref[2]),
                    MOI.ScalarQuadraticTerm(-1.5, vars_ref[3], vars_ref[4]),
                    MOI.ScalarQuadraticTerm(2.5, vars_ref[4], vars_ref[5]),
                ]
                a_terms_ref = [
                    MOI.ScalarAffineTerm(-8.5, vars_ref[1]),
                    MOI.ScalarAffineTerm(9.5, vars_ref[2]),
                    MOI.ScalarAffineTerm(0.5, vars_ref[3]),
                    MOI.ScalarAffineTerm(-1.25, vars_ref[4]),
                    MOI.ScalarAffineTerm(-0.75, vars_ref[5]),
                ]
                MOI.set(ref_model, MOI.ObjectiveSense(), sense)
                MOI.set(
                    ref_model,
                    MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
                    MOI.ScalarQuadraticFunction(q_terms_ref, a_terms_ref, 1.25),
                )
                MOI.optimize!(ref_model)
                ref_obj = MOI.get(ref_model, MOI.ObjectiveValue())

                # Solve with preprocessing enabled
                prep_model = MOI.instantiate(ExactSampler.Optimizer{Float64}; with_bridge_type = Float64)
                vars_prep = if use_spin
                    first(MOI.add_constrained_variables(prep_model, fill(QUBODrivers.Spin(), 5)))
                else
                    first(MOI.add_constrained_variables(prep_model, fill(MOI.ZeroOne(), 5)))
                end
                q_terms_prep = [
                    MOI.ScalarQuadraticTerm(1.0, vars_prep[1], vars_prep[2]),
                    MOI.ScalarQuadraticTerm(-1.5, vars_prep[3], vars_prep[4]),
                    MOI.ScalarQuadraticTerm(2.5, vars_prep[4], vars_prep[5]),
                ]
                a_terms_prep = [
                    MOI.ScalarAffineTerm(-8.5, vars_prep[1]),
                    MOI.ScalarAffineTerm(9.5, vars_prep[2]),
                    MOI.ScalarAffineTerm(0.5, vars_prep[3]),
                    MOI.ScalarAffineTerm(-1.25, vars_prep[4]),
                    MOI.ScalarAffineTerm(-0.75, vars_prep[5]),
                ]
                MOI.set(prep_model, MOI.ObjectiveSense(), sense)
                MOI.set(
                    prep_model,
                    MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
                    MOI.ScalarQuadraticFunction(q_terms_prep, a_terms_prep, 1.25),
                )
                MOI.set(prep_model, QUBODrivers.Preprocess(), rules)
                MOI.optimize!(prep_model)

                @test MOI.get(prep_model, MOI.ObjectiveValue()) ≈ ref_obj atol = 1e-9

                raw_prep = MOI.get(prep_model, MOI.RawSolver())
                @test QUBOTools.dimension(QUBOTools.backend(raw_prep)) == 5

                sol = QUBOTools.solution(raw_prep)
                @test isempty(QUBODrivers.validate_metadata(sol))
                state_vec = [MOI.get(prep_model, MOI.VariablePrimal(), v) for v in vars_prep]
                @test length(state_vec) == 5
                if use_spin
                    @test all(v -> v in (-1.0, 1.0), state_vec)
                else
                    @test all(v -> v in (0.0, 1.0), state_vec)
                end
            end
        end

        @testset "Integer Coefficient Type & IdentitySampler / RandomSampler Integration" begin
            # ExactSampler{Int}
            int_model = MOI.instantiate(ExactSampler.Optimizer{Int}; with_bridge_type = Int)
            x, _ = MOI.add_constrained_variables(int_model, fill(MOI.ZeroOne(), 4))
            MOI.set(int_model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                int_model,
                MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Int}}(),
                MOI.ScalarQuadraticFunction(
                    [
                        MOI.ScalarQuadraticTerm(2, x[1], x[2]),
                        MOI.ScalarQuadraticTerm(-4, x[2], x[3]),
                    ],
                    [
                        MOI.ScalarAffineTerm(-10, x[1]),
                        MOI.ScalarAffineTerm(3, x[2]),
                        MOI.ScalarAffineTerm(3, x[3]),
                        MOI.ScalarAffineTerm(-5, x[4]),
                    ],
                    2,
                ),
            )
            MOI.set(int_model, QUBODrivers.Preprocess(), :strong)
            MOI.optimize!(int_model)
            @test MOI.get(int_model, MOI.ObjectiveValue()) == -13
            @test [MOI.get(int_model, MOI.VariablePrimal(), xi) for xi in x] == [1, 0, 0, 1]

            # IdentitySampler with warm starts preserved on surviving variables
            id_model = MOI.instantiate(IdentitySampler.Optimizer{Float64}; with_bridge_type = Float64)
            y, _ = MOI.add_constrained_variables(id_model, fill(MOI.ZeroOne(), 3))
            for yi in y
                MOI.set(id_model, MOI.VariablePrimalStart(), yi, 1.0)
            end
            MOI.set(id_model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                id_model,
                MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
                MOI.ScalarQuadraticFunction(
                    [MOI.ScalarQuadraticTerm(4.0, y[2], y[3])],
                    [
                        MOI.ScalarAffineTerm(-10.0, y[1]),
                        MOI.ScalarAffineTerm(-1.0, y[2]),
                        MOI.ScalarAffineTerm(-1.0, y[3]),
                    ],
                    0.0,
                ),
            )
            MOI.set(id_model, QUBODrivers.Preprocess(), :dominance)
            MOI.optimize!(id_model)
            @test MOI.get(id_model, MOI.ResultCount()) == 1
            @test [MOI.get(id_model, MOI.VariablePrimal(), yi) for yi in y] == [1.0, 1.0, 1.0]
            @test MOI.get(id_model, MOI.ObjectiveValue()) ≈ -8.0

            # RandomSampler with AutoConfigure + Preprocess + PostSampleCallback
             callback_called = Ref(false)
            rnd_model = MOI.instantiate(RandomSampler.Optimizer{Float64}; with_bridge_type = Float64)
            z, _ = MOI.add_constrained_variables(rnd_model, fill(MOI.ZeroOne(), 4))
            MOI.set(rnd_model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                rnd_model,
                MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
                MOI.ScalarQuadraticFunction(
                    [MOI.ScalarQuadraticTerm(2.0, z[3], z[4])],
                    [
                        MOI.ScalarAffineTerm(-20.0, z[1]),
                        MOI.ScalarAffineTerm(20.0, z[2]),
                        MOI.ScalarAffineTerm(-1.0, z[3]),
                        MOI.ScalarAffineTerm(-1.0, z[4]),
                    ],
                    0.0,
                ),
            )
            MOI.set(rnd_model, QUBODrivers.RandomSeed(), 42)
            MOI.set(rnd_model, QUBODrivers.AutoConfigure(), true)
            MOI.set(rnd_model, QUBODrivers.Preprocess(), :strong)
            MOI.set(
                rnd_model,
                QUBODrivers.PostSampleCallback(),
                (sampleset, sampler) -> begin
                    callback_called[] = true
                    @test length(QUBOTools.state(first(sampleset))) == 4
                    return nothing
                end,
            )
            MOI.optimize!(rnd_model)
            @test callback_called[]
            @test MOI.get(rnd_model, MOI.VariablePrimal(), z[1]) == 1.0
            @test MOI.get(rnd_model, MOI.VariablePrimal(), z[2]) == 0.0
            raw_rnd = MOI.get(rnd_model, MOI.RawSolver())
            @test isempty(QUBODrivers.validate_metadata(QUBOTools.solution(raw_rnd)))
        end

        @testset "Unsupported Domain Rejection" begin
            # Non-binary domain with Preprocess enabled throws ArgumentError
            dom_sampler = MOI.instantiate(
                _PreprocessIntTestSampler.Optimizer{Float64};
                with_bridge_type = Float64,
            )
            x = MOI.add_variables(dom_sampler, 2)
            for xi in x
                MOI.add_constraint(dom_sampler, xi, MOI.Integer())
                MOI.add_constraint(dom_sampler, xi, MOI.GreaterThan(0.0))
                MOI.add_constraint(dom_sampler, xi, MOI.LessThan(3.0))
            end
            MOI.set(dom_sampler, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                dom_sampler,
                MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
                MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x[1])], 0.0),
            )
            MOI.set(dom_sampler, QUBODrivers.Preprocess(), :strong)
            @test_throws ArgumentError MOI.optimize!(dom_sampler)
        end
    end

    return nothing
end

