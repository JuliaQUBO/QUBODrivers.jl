include(joinpath(@__DIR__, "..", "..", "examples", "cudaq_qaoa_prototype.jl"))
include(joinpath(@__DIR__, "..", "..", "examples", "tket_nexus_prototype.jl"))

function _build_permuted_qubo_model(optimizer_constructor; sense = MOI.MIN_SENSE)
    src = MOIU.Model{Float64}()
    v = [MOI.add_variable(src) for _ in 1:4]
    # Add domain constraints in non-monotonic variable order [v[3], v[1], v[4], v[2]] and fix v[2] = 1.0
    MOI.add_constraint(src, v[3], MOI.ZeroOne())
    MOI.add_constraint(src, v[1], MOI.ZeroOne())
    MOI.add_constraint(src, v[4], MOI.ZeroOne()) # v[4] is an isolated free variable
    MOI.add_constraint(src, v[2], MOI.ZeroOne())
    MOI.add_constraint(src, v[2], MOI.EqualTo(1.0))

    # Objective: 2.0 * ( -1.5 * v[1] + 2.25 * v[3] - 3.0 * v[1]*v[3] + 0.5 * v[2]*v[1] ) + 4.5
    # With v[2] = 1.0 fixed:
    f = MOI.ScalarQuadraticFunction{Float64}(
        MOI.ScalarQuadraticTerm{Float64}[
            MOI.ScalarQuadraticTerm{Float64}(-6.0, v[1], v[3]),
        ],
        MOI.ScalarAffineTerm{Float64}[
            MOI.ScalarAffineTerm{Float64}(-3.0, v[1]),
            MOI.ScalarAffineTerm{Float64}(4.5, v[3]),
            MOI.ScalarAffineTerm{Float64}(1.0, v[2]),
        ],
        4.5,
    )
    MOI.set(src, MOI.ObjectiveSense(), sense)
    MOI.set(src, MOI.ObjectiveFunction{typeof(f)}(), f)

    sampler = optimizer_constructor()
    MOI.copy_to(sampler, src)
    return sampler, v
end

function _verify_against_exact_sampler(sampler, v)
    exact, _ = _build_permuted_qubo_model(ExactSampler.Optimizer; sense = MOI.get(sampler, MOI.ObjectiveSense()))
    MOI.optimize!(exact)
    exact_values = Dict{Vector{Int},Float64}()
    for r in 1:MOI.get(exact, MOI.ResultCount())
        state = [round(Int, MOI.get(exact, MOI.VariablePrimal(r), vi)) for vi in v]
        exact_values[state] = MOI.get(exact, MOI.ObjectiveValue(r))
    end

    m = MOI.get(sampler, MOI.ResultCount())
    @test m >= 1
    for r in 1:m
        state = [round(Int, MOI.get(sampler, MOI.VariablePrimal(r), vi)) for vi in v]
        @test state[2] == 1 # fixed variable v[2] == 1
        @test haskey(exact_values, state)
        @test isapprox(MOI.get(sampler, MOI.ObjectiveValue(r)), exact_values[state]; atol = 1e-10)
    end
    return nothing
end

function _run_generic_decomposition_components(child_factory::Function)
    # Generic 2-component QUBO solved component-by-component via public MOI.copy_to / MOI.optimize!
    # Component A: x1, x2 with min -x1 - 2*x2 + 3*x1*x2 (optimum at x1=0, x2=1 => -2.0)
    # Component B: x3, x4 with min -2*x3 - x4 + 3*x3*x4 (optimum at x3=1, x4=0 => -2.0)
    comp_objectives = [
        ([-1.0, -2.0], 3.0),
        ([-2.0, -1.0], 3.0),
    ]
    incumbent = Int[]
    total_obj = 0.0
    for (lin, quad) in comp_objectives
        child = child_factory()
        src = MOIU.Model{Float64}()
        x = [MOI.add_variable(src) for _ in 1:2]
        for xi in x
            MOI.add_constraint(src, xi, MOI.ZeroOne())
        end
        f = MOI.ScalarQuadraticFunction{Float64}(
            [MOI.ScalarQuadraticTerm{Float64}(quad, x[1], x[2])],
            [
                MOI.ScalarAffineTerm{Float64}(lin[1], x[1]),
                MOI.ScalarAffineTerm{Float64}(lin[2], x[2]),
            ],
            0.0,
        )
        MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(src, MOI.ObjectiveFunction{typeof(f)}(), f)
        MOI.copy_to(child, src)
        MOI.optimize!(child)
        @test MOI.get(child, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        @test MOI.get(child, MOI.ResultCount()) >= 1
        append!(incumbent, [round(Int, MOI.get(child, MOI.VariablePrimal(1), xi)) for xi in x])
        total_obj += MOI.get(child, MOI.ObjectiveValue(1))
    end
    return incumbent, total_obj
end

function test_cudaq_qaoa_prototype()
    @testset "□ CUDAQOpt.QAOA Prototype (#88)" verbose = true begin
        # 1. Standard QUBODrivers conformance & benchmark suite on qpp-cpu
        QUBODrivers.test(
            CUDAQOptPrototype.QAOA.Optimizer;
            examples = true,
            benchmark_conformance = true,
        ) do sampler
            MOI.set(sampler, MOI.RawOptimizerAttribute("target"), "qpp-cpu")
            MOI.set(sampler, MOI.RawOptimizerAttribute("p"), 1)
            MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 64)
            MOI.set(sampler, MOI.RawOptimizerAttribute("max_iterations"), 5)
            MOI.set(sampler, QUBODrivers.RandomSeed(), 42)
        end

        # 2. Environment probe helper (credential-free)
        probe = CUDAQOptPrototype.probe_cudaq_environment()
        @test probe.has_qpp_cpu === false
        @test probe.num_gpus == 0

        # 3. Permuted labels, fixed variables, isolated variables, offsets, and shot multiplicities
        @testset "Permuted QUBO, isolated/fixed variables, and shot counts" begin
            for sense in (MOI.MIN_SENSE, MOI.MAX_SENSE)
                sampler, v = _build_permuted_qubo_model(CUDAQOptPrototype.QAOA.Optimizer; sense = sense)
                MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 48)
                MOI.set(sampler, QUBODrivers.FinalNumberOfReads(), 32)
                MOI.set(sampler, MOI.RawOptimizerAttribute("max_iterations"), 6)
                MOI.set(sampler, QUBODrivers.RandomSeed(), 17)
                MOI.optimize!(sampler)

                @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
                _verify_against_exact_sampler(sampler, v)

                sol = QUBOTools.solution(sampler)
                meta = QUBOTools.metadata(sol)
                @test isempty(QUBODrivers.validate_metadata(sol))
                @test sum(QUBOTools.reads(s) for s in sol) == 32
                @test meta["reads"]["number_of_reads"] == 48
                @test meta["reads"]["final_number_of_reads"] == 32
                @test meta["cudaq"]["selected_target"] == "qpp-cpu"
                @test meta["cudaq"]["num_qubits"] == 3
            end
        end

        # 4. Target isolation, no silent precision/target downgrade, and explicit fallback
        @testset "Target isolation and fallback policy" begin
            sampler_a, _ = _build_permuted_qubo_model(CUDAQOptPrototype.QAOA.Optimizer)
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("target"), "qpp-cpu")
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("target_option"), "fp32")
            MOI.set(sampler_a, QUBODrivers.RandomSeed(), 11)
            MOI.optimize!(sampler_a)
            meta_a = QUBOTools.metadata(QUBOTools.solution(sampler_a))
            @test meta_a["cudaq"]["selected_target"] == "qpp-cpu"
            @test meta_a["cudaq"]["precision"] == "fp32"
            @test meta_a["cudaq"]["fallback_applied"] === false

            # Requesting unavailable "nvidia" target with allow_target_fallback = false must fail
            # and clear any prior solution on the same optimizer instance
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("target"), "nvidia")
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("target_option"), "fp64")
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("allow_target_fallback"), false)
            err = try
                MOI.optimize!(sampler_a)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("target='nvidia'", sprint(showerror, err))
            @test MOI.get(sampler_a, MOI.TerminationStatus()) == MOI.OTHER_ERROR
            @test MOI.get(sampler_a, MOI.ResultCount()) == 0
            @test MOI.get(sampler_a, MOI.PrimalStatus()) == MOI.NO_SOLUTION

            # Explicit fallback enabled: records requested_target, selected_target, and fallback_reason
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("allow_target_fallback"), true)
            MOI.optimize!(sampler_a)
            meta_fb = QUBOTools.metadata(QUBOTools.solution(sampler_a))
            @test MOI.get(sampler_a, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
            @test meta_fb["cudaq"]["requested_target"] == "nvidia"
            @test meta_fb["cudaq"]["selected_target"] == "qpp-cpu"
            @test meta_fb["cudaq"]["fallback_applied"] === true
            @test meta_fb["cudaq"]["fallback_reason"] isa String

            # Capacity / OOM failure sets MOI.MEMORY_LIMIT and never silently falls back mid-solve
            MOI.set(sampler_a, MOI.RawOptimizerAttribute("max_target_qubits"), 2)
            err_oom = try
                MOI.optimize!(sampler_a)
                nothing
            catch e
                e
            end
            @test err_oom isa ErrorException
            @test occursin("out-of-memory / capacity limit", sprint(showerror, err_oom))
            @test MOI.get(sampler_a, MOI.TerminationStatus()) == MOI.MEMORY_LIMIT
            @test MOI.get(sampler_a, MOI.ResultCount()) == 0
            @test MOI.get(sampler_a, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        end

        # 5. Generic decomposition child composition
        @testset "Generic decomposition child composition" begin
            incumbent, total_obj = _run_generic_decomposition_components() do
                opt = CUDAQOptPrototype.QAOA.Optimizer()
                MOI.set(opt, MOI.RawOptimizerAttribute("num_reads"), 64)
                MOI.set(opt, MOI.RawOptimizerAttribute("max_iterations"), 8)
                MOI.set(opt, QUBODrivers.RandomSeed(), 9)
                return opt
            end
            @test length(incumbent) == 4
            @test total_obj <= -3.0
        end
    end

    return nothing
end

function test_tket_nexus_prototype()
    @testset "□ TKETOpt.QAOA Prototype (#89)" verbose = true begin
        # 1. Standard QUBODrivers conformance & benchmark suite in local_tket mode
        QUBODrivers.test(
            TKETOptPrototype.QAOA.Optimizer;
            examples = true,
            benchmark_conformance = true,
        ) do sampler
            MOI.set(sampler, MOI.RawOptimizerAttribute("execution_mode"), "local_tket")
            MOI.set(sampler, MOI.RawOptimizerAttribute("backend_name"), "AerBackend")
            MOI.set(sampler, MOI.RawOptimizerAttribute("p"), 1)
            MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 64)
            MOI.set(sampler, MOI.RawOptimizerAttribute("max_iterations"), 5)
            MOI.set(sampler, QUBODrivers.RandomSeed(), 42)
        end

        # 2. Environment probe helper (credential-free)
        probe = TKETOptPrototype.probe_tket_environment()
        @test probe.has_aer === false
        @test probe.has_qnexus === false

        # 3. Half-turn gate parameterization and compiled-circuit bit permutation preservation
        @testset "TKET half-turn gates and logical cbits permutation" begin
            h = Dict(1 => -1.5, 2 => 0.75)
            J = Dict((1, 2) => 2.0)
            gates = TKETOptPrototype.QAOA.build_tket_qaoa_circuit(3, h, J, [0.4, 0.25], 1)
            rz_gates = filter(g -> g.gate === :Rz, gates)
            zz_gates = filter(g -> g.gate === :ZZPhase, gates)
            rx_gates = filter(g -> g.gate === :Rx, gates)
            meas_gates = filter(g -> g.gate === :Measure, gates)
            @test length(rz_gates) == 2
            @test isapprox(rz_gates[1].half_turns, -2.0 * 0.4 * (-1.5) / π; atol = 1e-12)
            @test length(zz_gates) == 1
            @test isapprox(zz_gates[1].half_turns, 2.0 * 0.4 * 2.0 / π; atol = 1e-12)
            @test length(rx_gates) == 3 # includes isolated qubit 3
            @test length(meas_gates) == 3

            sampler, v = _build_permuted_qubo_model(TKETOptPrototype.QAOA.Optimizer)
            # Apply a non-trivial 3-qubit physical compiler permutation [3, 1, 2]
            MOI.set(sampler, MOI.RawOptimizerAttribute("compiler_permutation"), [3, 1, 2])
            MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 48)
            MOI.set(sampler, QUBODrivers.FinalNumberOfReads(), 24)
            MOI.set(sampler, MOI.RawOptimizerAttribute("max_iterations"), 6)
            MOI.set(sampler, QUBODrivers.RandomSeed(), 23)
            MOI.optimize!(sampler)

            @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
            _verify_against_exact_sampler(sampler, v)
            sol = QUBOTools.solution(sampler)
            @test isempty(QUBODrivers.validate_metadata(sol))
            @test sum(QUBOTools.reads(s) for s in sol) == 24
        end

        # 4. Deterministic mocked Quantinuum Nexus job lifecycle (no cloud credentials)
        @testset "Mocked Quantinuum Nexus job lifecycle, persistence, and recovery" begin
            mktempdir() do tmpdir
                ledger_path = joinpath(tmpdir, "nexus_job_ledger.txt")

                # 4a. Poll timeout persists job ID before polling, requests cancel (unconfirmed RUNNING),
                #     clears stale solutions, and sets MOI.TIME_LIMIT
                client_timeout = TKETOptPrototype.QAOA.MockNexusClient(;
                    status_sequence    = ["SUBMITTED", "QUEUED", "RUNNING"],
                    post_cancel_status = "RUNNING",
                )
                sampler, v = _build_permuted_qubo_model(TKETOptPrototype.QAOA.Optimizer)
                MOI.set(sampler, MOI.RawOptimizerAttribute("execution_mode"), "nexus_emulator")
                MOI.set(sampler, MOI.RawOptimizerAttribute("backend_name"), "H1-1E")
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_project"), "secquoia-test-proj")
                MOI.set(sampler, MOI.RawOptimizerAttribute("job_persistence_path"), ledger_path)
                MOI.set(sampler, MOI.RawOptimizerAttribute("poll_timeout_sec"), 0.02)
                MOI.set(sampler, MOI.RawOptimizerAttribute("poll_interval_sec"), 0.01)
                MOI.set(sampler, MOI.RawOptimizerAttribute("cancel_on_timeout"), true)
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_client"), client_timeout)
                MOI.set(sampler, QUBODrivers.RandomSeed(), 31)

                err_to = try
                    MOI.optimize!(sampler)
                    nothing
                catch e
                    e
                end
                @test err_to isa ErrorException
                @test occursin("nexus-exec-1", sprint(showerror, err_to))
                @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.TIME_LIMIT
                @test MOI.get(sampler, MOI.ResultCount()) == 0
                @test isfile(ledger_path)
                @test client_timeout.execute_submissions == 1
                @test client_timeout.cancel_requests == 1
                job_meta = QUBOTools.metadata(QUBOTools.solution(sampler))["tket"]["nexus_jobs"][1]
                @test job_meta["execute_job_id"] == "nexus-exec-1"
                @test job_meta["cancel_requested"] === true
                @test job_meta["cancelled"] === false # RUNNING != CANCELLED

                # 4b. Resume from persisted ledger / nexus_resume_job_id without duplicate submission
                client_timeout.status_sequence = ["RUNNING", "COMPLETED"]
                MOI.set(sampler, MOI.RawOptimizerAttribute("poll_timeout_sec"), 1.0)
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_resume_job_id"), "nexus-exec-1")
                MOI.optimize!(sampler)

                @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
                @test client_timeout.execute_submissions == 1 # NO duplicate job submitted!
                _verify_against_exact_sampler(sampler, v)
                resumed_meta = QUBOTools.metadata(QUBOTools.solution(sampler))["tket"]["nexus_jobs"][1]
                @test resumed_meta["execute_job_id"] == "nexus-exec-1"
                @test resumed_meta["recovered"] === true
                @test resumed_meta["status"] == "COMPLETED"

                # 4c. Confirmed cancellation on timeout (post_cancel_status == "CANCELLED")
                client_cancel = TKETOptPrototype.QAOA.MockNexusClient(;
                    status_sequence    = ["QUEUED", "RUNNING"],
                    post_cancel_status = "CANCELLED",
                )
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_resume_job_id"), nothing)
                MOI.set(sampler, MOI.RawOptimizerAttribute("job_persistence_path"), nothing)
                MOI.set(sampler, MOI.RawOptimizerAttribute("poll_timeout_sec"), 0.01)
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_client"), client_cancel)
                @test_throws ErrorException MOI.optimize!(sampler)
                @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.TIME_LIMIT
                cancel_meta = QUBOTools.metadata(QUBOTools.solution(sampler))["tket"]["nexus_jobs"][1]
                @test cancel_meta["cancel_requested"] === true
                @test cancel_meta["cancelled"] === true

                # 4d. Remote FAILED status clears prior results and sets MOI.OTHER_ERROR
                client_fail = TKETOptPrototype.QAOA.MockNexusClient(;
                    status_sequence = ["SUBMITTED", "FAILED"],
                )
                MOI.set(sampler, MOI.RawOptimizerAttribute("poll_timeout_sec"), 1.0)
                MOI.set(sampler, MOI.RawOptimizerAttribute("nexus_client"), client_fail)
                @test_throws ErrorException MOI.optimize!(sampler)
                @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.OTHER_ERROR
                @test MOI.get(sampler, MOI.ResultCount()) == 0
                @test MOI.get(sampler, MOI.PrimalStatus()) == MOI.NO_SOLUTION
            end
        end

        # 5. Generic decomposition child composition in local_tket mode
        @testset "Generic decomposition child composition" begin
            incumbent, total_obj = _run_generic_decomposition_components() do
                opt = TKETOptPrototype.QAOA.Optimizer()
                MOI.set(opt, MOI.RawOptimizerAttribute("execution_mode"), "local_tket")
                MOI.set(opt, MOI.RawOptimizerAttribute("num_reads"), 64)
                MOI.set(opt, MOI.RawOptimizerAttribute("max_iterations"), 8)
                MOI.set(opt, QUBODrivers.RandomSeed(), 9)
                return opt
            end
            @test length(incumbent) == 4
            @test total_obj <= -3.0
        end
    end

    return nothing
end

