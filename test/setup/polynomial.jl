import JuMP
import MultivariatePolynomials as MP

module _TestPolySampler

import MultivariatePolynomials as MP
import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet

QUBODrivers.@setup Optimizer begin
    name    = "Test Polynomial Sampler"
    version = QUBODrivers.__version__()
end

QUBODrivers.supports_polynomial_objective(::Type{<:Optimizer}) = true
QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = false

sample_state(i::Integer, n::Integer, domain::QUBOTools.Domain) =
    let bits = digits(Int, i - 1; base = 2, pad = n)
        domain === QUBOTools.SpinDomain ? [2b - 1 for b in bits] : bits
    end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    p = QUBODrivers.polynomial_objective(sampler)
    vars = MP.variables(p)
    n = QUBOTools.dimension(sampler)
    sense = QUBOTools.sense(sampler)
    domain = QUBOTools.domain(sampler)

    m = 2^n
    samples = Vector{Sample{T,Int}}(undef, m)

    results = @timed for i in 1:m
        ψ = sample_state(i, n, domain)
        λ = isempty(vars) ?
            convert(T, MP.coefficient(p, MP.constant_monomial(p))) :
            convert(T, p(vars => T.(ψ)))
        samples[i] = Sample{T,Int}(ψ, λ)
    end

    metadata = QUBODrivers._sampler_metadata(
        origin                = "Test Polynomial Sampler @ QUBODrivers.jl",
        algorithm_name        = "Exhaustive Polynomial Search",
        execution_mode        = "exhaustive_search",
        optimizer_evaluations = m,
        number_of_reads       = m,
        final_number_of_reads = m,
        status                = "optimal",
        termination_status    = MOI.OPTIMAL,
    )
    metadata["time"] = Dict{String,Any}("effective" => results.time)

    return SampleSet{T,Int}(samples, metadata; sense = sense, domain = domain)
end

end # module _TestPolySampler

mutable struct _MinimalPolySampler <: QUBODrivers.AbstractSampler{Float64}
    model::QUBOTools.Model{VI,Float64,Int}
    _MinimalPolySampler() = new(QUBOTools.Model{VI,Float64,Int}())
end

QUBOTools.backend(sampler::_MinimalPolySampler) = sampler.model
function QUBODrivers.set_model!(
    sampler::_MinimalPolySampler,
    model::QUBOTools.Model{VI,Float64,Int},
)
    sampler.model = model
    return model
end
QUBODrivers.supports_polynomial_objective(::Type{_MinimalPolySampler}) = true

function test_polynomial_objective_bridge()
    @testset "□ Polynomial Objective Bridge" verbose = true begin
        test_cubic_jump_objective_fixture()
        test_polynomial_sense_and_domain_casting()
        test_polynomial_quadratic_and_linear_compat()
        test_invalid_nl_expression_errors()
        test_polyjump_functions_and_bridges()
        test_non_opted_in_drivers_unaffected()
        test_minimal_sampler_polynomial_fallback()
    end

    return nothing
end

function test_cubic_jump_objective_fixture()
    @testset "→ Cubic binary JuMP objective fixture" begin
        model = JuMP.Model(_TestPolySampler.Optimizer)
        JuMP.@variable(model, x, Bin)
        JuMP.@variable(model, y, Bin)
        JuMP.@variable(model, z, Bin)
        JuMP.@objective(model, Min, -4.0 * x * y * z + 1.5 * x * y + 2.0 * z + 3.25)

        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        p = QUBODrivers.polynomial_objective(sampler)
        spf = QUBODrivers.polynomial_function(sampler)

        @test p isa MP.AbstractPolynomial{Float64}
        @test spf isa QUBODrivers.ScalarPolynomialFunction{Float64}
        @test spf.variables == QUBOTools.variables(sampler)
        @test MP.maxdegree(p) == 3
        @test length(MP.variables(p)) == 3
        @test Symbol.(MP.variables(p)) == [:x, :y, :z]
        @test MP.coefficient(p, MP.constant_monomial(p)) == 3.25
        @test MOI.constant(spf) == 3.25
        @test MOI.get(sampler, MOI.ObjectiveSense()) == MOI.MIN_SENSE
        @test QUBOTools.sense(sampler) == QUBOTools.Min

        # Minimum is achieved at (x, y, z) = (1, 1, 1) -> -4.0 + 1.5 + 2.0 + 3.25 = 2.75
        @test JuMP.value(x) == 1.0
        @test JuMP.value(y) == 1.0
        @test JuMP.value(z) == 1.0
        @test JuMP.objective_value(model) ≈ 2.75

        # Calling quadratic form extractors on degree-3 objective throws a clear ArgumentError
        @test_throws ArgumentError QUBOTools.qubo(sampler)
        @test_throws ArgumentError QUBOTools.ising(sampler)
        @test_throws ArgumentError QUBOTools.form(sampler)

        # Out-of-order expression and omitted middle variable still preserve model variable order
        model_order = JuMP.Model(_TestPolySampler.Optimizer)
        JuMP.@variable(model_order, a, Bin)
        JuMP.@variable(model_order, b, Bin)
        JuMP.@variable(model_order, c, Bin)
        JuMP.@objective(model_order, Max, 5.0 * c * a - 1.0)
        JuMP.optimize!(model_order)

        sampler_order = JuMP.unsafe_backend(model_order)
        p_order = QUBODrivers.polynomial_objective(sampler_order)
        @test Symbol.(MP.variables(p_order)) == [:a, :b, :c]
        @test MOI.get(sampler_order, MOI.ObjectiveSense()) == MOI.MAX_SENSE
        @test QUBOTools.sense(sampler_order) == QUBOTools.Max
        @test MP.coefficient(p_order, MP.constant_monomial(p_order)) == -1.0
        @test JuMP.objective_value(model_order) ≈ 4.0

        # Fixed variables in a cubic objective
        model_fixed = JuMP.Model(_TestPolySampler.Optimizer)
        JuMP.@variable(model_fixed, u[1:4], Bin)
        JuMP.fix(u[2], 1.0; force = true)
        JuMP.@objective(model_fixed, Min, -6.0 * u[1] * u[2] * u[3] * u[4] + 2.0 * u[2] + 1.0)
        JuMP.optimize!(model_fixed)

        sampler_fixed = JuMP.unsafe_backend(model_fixed)
        p_fixed = QUBODrivers.polynomial_objective(sampler_fixed)
        @test length(MP.variables(p_fixed)) == 3
        @test MP.maxdegree(p_fixed) == 3
        @test MP.coefficient(p_fixed, MP.constant_monomial(p_fixed)) == 3.0
        @test JuMP.value.(u) == [1.0, 1.0, 1.0, 1.0]
        @test JuMP.objective_value(model_fixed) ≈ -3.0
    end

    return nothing
end

function test_polynomial_sense_and_domain_casting()
    @testset "→ Sense and domain casting" begin
        model = JuMP.Model(_TestPolySampler.Optimizer)
        JuMP.@variable(model, x[1:2], Bin)
        JuMP.@objective(model, Max, 4.0 * x[1] * x[2] - 2.0 * x[1] + 1.0)
        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        p_max = QUBODrivers.polynomial_objective(sampler)
        p_min = QUBODrivers.polynomial_objective(sampler; sense = :min)
        @test p_min == -p_max

        # Cast bool (x in {0, 1}) to spin (s in {-1, 1}) via x = (1 + s) / 2
        p_spin = QUBODrivers.polynomial_objective(sampler; domain = :spin)
        vars_bool = MP.variables(p_max)
        vars_spin = MP.variables(p_spin)
        for (b1, b2) in Iterators.product((0, 1), (0, 1))
            s1, s2 = 2b1 - 1, 2b2 - 1
            @test p_max(vars_bool => [Float64(b1), Float64(b2)]) ≈
                  p_spin(vars_spin => [Float64(s1), Float64(s2)])
        end

        # Spin model cast to bool
        spin_src = MOIU.UniversalFallback(MOIU.Model{Float64}())
        s_vars, _ = MOI.add_constrained_variables(spin_src, fill(Spin(), 3))
        MOI.set(spin_src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        nl = MOI.ScalarNonlinearFunction(
            :+,
            Any[
                MOI.ScalarNonlinearFunction(:*, Any[2.0, s_vars[1], s_vars[2], s_vars[3]]),
                -1.5,
            ],
        )
        MOI.set(spin_src, MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(), nl)

        spin_sampler = _TestPolySampler.Optimizer{Float64}()
        MOI.copy_to(spin_sampler, spin_src)
        MOI.optimize!(spin_sampler)

        p_s = QUBODrivers.polynomial_objective(spin_sampler)
        p_b = QUBODrivers.polynomial_objective(spin_sampler; domain = :bool)
        vs = MP.variables(p_s)
        vb = MP.variables(p_b)
        for (b1, b2, b3) in Iterators.product((0, 1), (0, 1), (0, 1))
            s1, s2, s3 = 2b1 - 1, 2b2 - 1, 2b3 - 1
            @test p_s(vs => Float64[s1, s2, s3]) ≈ p_b(vb => Float64[b1, b2, b3])
        end
        @test MOI.get(spin_sampler, MOI.ObjectiveValue()) ≈ -3.5
    end

    return nothing
end

function test_polynomial_quadratic_and_linear_compat()
    @testset "→ Quadratic and linear objectives on opted-in sampler" begin
        model = JuMP.Model(_TestPolySampler.Optimizer)
        JuMP.@variable(model, x[1:3], Bin)
        JuMP.@objective(model, Min, 2.0 * x[1] * x[2] - 3.0 * x[3] + 1.25)
        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        p = QUBODrivers.polynomial_objective(sampler)
        @test MP.maxdegree(p) == 2
        @test MP.coefficient(p, MP.constant_monomial(p)) == 1.25

        n, L, Q, α, β = QUBOTools.qubo(sampler, :dict; sense = :min)
        @test n == 3
        @test L[3] == -3.0
        @test Q[(1, 2)] == 2.0
        @test α == 1.0
        @test β == 1.25

        # Degree-2 ScalarNonlinearFunction also populates quadratic QUBOTools model
        nl_src = MOIU.UniversalFallback(MOIU.Model{Float64}())
        v, _ = MOI.add_constrained_variables(nl_src, fill(MOI.ZeroOne(), 2))
        MOI.set(nl_src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        nl_quad = MOI.ScalarNonlinearFunction(
            :^,
            Any[MOI.ScalarNonlinearFunction(:+, Any[v[1], v[2]]), 2],
        )
        MOI.set(nl_src, MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(), nl_quad)

        nl_sampler = _TestPolySampler.Optimizer{Float64}()
        MOI.copy_to(nl_sampler, nl_src)
        n2, L2, Q2, _, β2 = QUBOTools.qubo(nl_sampler, :dict; sense = :min)
        @test n2 == 2
        @test L2[1] == 1.0
        @test L2[2] == 1.0
        @test Q2[(1, 2)] == 2.0
        @test β2 == 0.0
    end

    return nothing
end

function test_invalid_nl_expression_errors()
    @testset "→ Invalid nonlinear operator errors" begin
        x = VI(1)
        y = VI(2)

        invalid_cases = [
            (MOI.ScalarNonlinearFunction(:sin, Any[x]), "sin"),
            (MOI.ScalarNonlinearFunction(:cos, Any[x]), "cos"),
            (MOI.ScalarNonlinearFunction(:exp, Any[x]), "exp"),
            (MOI.ScalarNonlinearFunction(:/, Any[x, y]), "/"),
            (MOI.ScalarNonlinearFunction(:/, Any[1.0, x]), "/"),
            (MOI.ScalarNonlinearFunction(:/, Any[x, 0.0]), "/"),
            (MOI.ScalarNonlinearFunction(:/, Any[1.0, 0.0]), "/"),
            (MOI.ScalarNonlinearFunction(:^, Any[x, 1.5]), "^"),
            (MOI.ScalarNonlinearFunction(:^, Any[x, -1]), "^"),
            (MOI.ScalarNonlinearFunction(:^, Any[x, y]), "^"),
        ]

        for (nl, expected_op) in invalid_cases
            err = try
                QUBODrivers.polynomial_function(nl, Float64)
                nothing
            catch e
                e
            end

            @test err isa QUBODrivers.InvalidNLExpression
            msg = sprint(showerror, err)
            @test occursin("InvalidNLExpression", msg)
            @test occursin(expected_op, msg)

            # Also verify error is thrown when copying into an opted-in sampler
            src = MOIU.UniversalFallback(MOIU.Model{Float64}())
            MOI.add_constrained_variables(src, fill(MOI.ZeroOne(), 2))
            MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(src, MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(), nl)
            sampler = _TestPolySampler.Optimizer{Float64}()
            @test_throws QUBODrivers.InvalidNLExpression MOI.copy_to(sampler, src)
        end

        # Constant scalar division (x * y) / 2.0 is a valid polynomial
        valid_div = MOI.ScalarNonlinearFunction(
            :/,
            Any[MOI.ScalarNonlinearFunction(:*, Any[x, y]), 2.0],
        )
        spf_div = QUBODrivers.polynomial_function(valid_div, Float64)
        @test MP.maxdegree(spf_div.polynomial) == 2
        @test only(MP.coefficients(spf_div.polynomial)) == 0.5
    end

    return nothing
end

function test_polyjump_functions_and_bridges()
    @testset "→ ScalarPolynomialFunction, ToPolynomialBridge & NLToPolynomial" begin
        P = QUBODrivers.polynomial_type(VI, Float64)
        F = QUBODrivers.ScalarPolynomialFunction{Float64,P}
        @test QUBODrivers.polynomial_type(VI) == QUBODrivers.PolyType
        @test QUBODrivers.polynomial_type(Float64) == P

        x1 = VI(1)
        x2 = VI(2)

        f_vi = convert(F, x1)
        @test f_vi.variables == [x1]
        @test MOI.constant(f_vi) == 0.0

        f_const_saf = convert(F, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm{Float64}[], 7.5))
        @test isempty(f_const_saf.variables)
        @test MOI.constant(f_const_saf) == 7.5

        f_saf = convert(
            F,
            MOI.ScalarAffineFunction(
                [MOI.ScalarAffineTerm(2.0, x2), MOI.ScalarAffineTerm(3.0, x1)],
                1.0,
            ),
        )
        @test f_saf.variables == [x1, x2]
        @test MOI.constant(f_saf) == 1.0

        f_sqf = convert(
            F,
            MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(4.0, x1, x1), MOI.ScalarQuadraticTerm(5.0, x1, x2)],
                [MOI.ScalarAffineTerm(-1.0, x2)],
                2.5,
            ),
        )
        @test f_sqf.variables == [x1, x2]
        @test MOI.constant(f_sqf) == 2.5

        f_copy = copy(f_sqf)
        @test MOI.Utilities.canonicalize!(f_copy) === f_copy
        @test MOI.Utilities.is_coefficient_type(F, Float64)
        @test !MOI.Utilities.is_coefficient_type(F, Int)

        VF = QUBODrivers.VectorPolynomialFunction{Float64,P}
        @test MOI.Utilities.scalar_type(VF) == F
        @test MOI.Utilities.is_coefficient_type(VF, Float64)
        @test !MOI.Utilities.is_coefficient_type(VF, Int)
        @test MOI.Utilities.promote_operation(-, Float64, F) == F
        @test MOI.Utilities.promote_operation(-, Float64, F, Float64) == F
        @test MOI.Utilities.promote_operation(-, Float64, VF, Vector{Float64}) == VF
        @test MOI.Utilities.promote_operation(vcat, Float64, F) == VF

        f_sum = MOI.Utilities.operate(+, Float64, f_saf, 4.0)
        @test MOI.constant(f_sum) == 5.0

        f_sub = MOI.Utilities.substitute_variables(f_saf) do vi
            return MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(2.0, vi)], 1.0)
        end
        @test f_sub.variables == [x1, x2]
        @test MOI.constant(f_sub) == 6.0

        # ToPolynomialBridge
        inner = MOIU.UniversalFallback(MOIU.Model{Float64}())
        bridged = MOI.Bridges.Objective.SingleBridgeOptimizer{
            QUBODrivers.ToPolynomialBridge{Float64},
        }(inner)
        v = MOI.add_variables(bridged, 3)
        nl = MOI.ScalarNonlinearFunction(
            :+,
            Any[MOI.ScalarNonlinearFunction(:*, Any[3.0, v[1], v[2], v[3]]), 2.0],
        )
        MOI.set(bridged, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(bridged, MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(), nl)

        bridged_obj = MOI.get(inner, MOI.ObjectiveFunction{F}())
        @test bridged_obj isa F
        @test bridged_obj.variables == v
        @test MOI.constant(bridged_obj) == 2.0

        # Copy from bridged model into opted-in sampler
        for vi in v
            MOI.add_constraint(inner, vi, MOI.ZeroOne())
        end
        sampler = _TestPolySampler.Optimizer{Float64}()
        MOI.copy_to(sampler, inner)
        @test MP.maxdegree(QUBODrivers.polynomial_objective(sampler)) == 3

        # NLToPolynomial wrapper
        nl_opt = QUBODrivers.NLToPolynomial{Float64}(inner)
        @test !MOI.is_empty(nl_opt)
        @test MOI.supports(nl_opt, MOI.NLPBlock())
        bad_res = QUBODrivers._to_polynomial(
            nl_opt,
            MOI.ScalarNonlinearFunction(:sin, Any[v[1]]),
        )
        @test bad_res === nothing
        @test MOI.get(nl_opt, MOI.TerminationStatus()) == MOI.INVALID_MODEL
        @test MOI.get(nl_opt, MOI.ResultCount()) == 0
        @test MOI.get(nl_opt, MOI.PrimalStatus()) == MOI.NO_SOLUTION
        @test occursin("sin", MOI.get(nl_opt, MOI.RawStatusString()))
        MOI.empty!(nl_opt)
        @test MOI.is_empty(nl_opt)
    end

    return nothing
end

function test_non_opted_in_drivers_unaffected()
    @testset "→ Non-opted-in drivers unaffected" begin
        for OptimizerType in (
            ExactSampler.Optimizer,
            RandomSampler.Optimizer,
            IdentitySampler.Optimizer,
            MIPSampler.Optimizer,
        )
            sampler = OptimizerType{Float64}()
            @test !QUBODrivers.supports_polynomial_objective(sampler)
            @test !MOI.supports(
                sampler,
                MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(),
            )
            @test !MOI.supports(
                sampler,
                MOI.ObjectiveFunction{QUBODrivers.FuncType{Float64}}(),
            )
            @test_throws ArgumentError QUBODrivers.polynomial_objective(sampler)

            # JuMP cubic model rejected by non-opted-in optimizer
            model = JuMP.Model(OptimizerType)
            JuMP.@variable(model, x[1:3], Bin)
            @test_throws ErrorException JuMP.@objective(model, Min, x[1] * x[2] * x[3])

            # Direct MOI.copy_to with cubic objective rejected (both with and without fixed variables)
            src = MOIU.UniversalFallback(MOIU.Model{Float64}())
            vars, _ = MOI.add_constrained_variables(src, fill(MOI.ZeroOne(), 3))
            MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(
                src,
                MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(),
                MOI.ScalarNonlinearFunction(:*, Any[vars[1], vars[2], vars[3]]),
            )
            @test_throws Exception MOI.copy_to(OptimizerType{Float64}(), src)

            MOI.add_constraint(src, vars[1], MOI.EqualTo(1.0))
            @test_throws Exception MOI.copy_to(OptimizerType{Float64}(), src)
        end
    end

    return nothing
end

function test_minimal_sampler_polynomial_fallback()
    @testset "→ Minimal custom sampler fallback storage" begin
        sampler = _MinimalPolySampler()
        @test QUBODrivers.supports_polynomial_objective(sampler)
        @test iszero(QUBODrivers.polynomial_objective(sampler))

        src = MOIU.UniversalFallback(MOIU.Model{Float64}())
        vars, _ = MOI.add_constrained_variables(src, fill(MOI.ZeroOne(), 3))
        MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            src,
            MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}(),
            MOI.ScalarNonlinearFunction(:*, Any[vars[1], vars[2], vars[3]]),
        )

        MOI.copy_to(sampler, src)
        p = QUBODrivers.polynomial_objective(sampler)
        @test MP.maxdegree(p) == 3
        @test length(MP.variables(p)) == 3

        MOI.empty!(sampler)
        @test iszero(QUBODrivers.polynomial_objective(sampler))
    end

    return nothing
end

