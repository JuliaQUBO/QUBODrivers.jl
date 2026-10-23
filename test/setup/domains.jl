import JuMP
import MultivariatePolynomials as MP

module _TestFiniteDomainSampler

import MultivariatePolynomials as MP
import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet

QUBODrivers.@setup Optimizer begin
    name    = "Test Finite Domain Sampler"
    version = QUBODrivers.__version__()
end

QUBODrivers.supports_polynomial_objective(::Type{<:Optimizer}) = true
QUBODrivers.supported_domains(::Type{<:Optimizer}) = Set{Symbol}([:bool, :spin, :int, :set])
QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = false

function _cartesian_levels(num_levels::Vector{Int})
    isempty(num_levels) && return Vector{Int}[Int[]]
    ranges = [0:(d - 1) for d in num_levels]
    return [collect(Int, tup) for tup in Iterators.product(ranges...)]
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    num_levels = QUBODrivers.variable_num_levels(sampler)
    sense = QUBOTools.sense(sampler)
    domain = QUBOTools.domain(sampler)

    all_levels = _cartesian_levels(num_levels)
    m = length(all_levels)
    samples = Vector{Sample{T,Int}}(undef, m)

    results = @timed for (idx, lvls) in enumerate(all_levels)
        ψ = QUBODrivers.levels_to_values(sampler, lvls)
        λ = QUBOTools.value(sampler, ψ)
        samples[idx] = Sample{T,Int}(ψ, λ)
    end

    metadata = QUBODrivers._sampler_metadata(
        origin                = "Test Finite Domain Sampler @ QUBODrivers.jl",
        algorithm_name        = "Exhaustive Finite-Domain Search",
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

end # module _TestFiniteDomainSampler

module _ExternalEncodingAttrModule
import QUBODrivers: MOI
struct VariableEncodingSet <: MOI.AbstractVariableAttribute end
end # module _ExternalEncodingAttrModule

mutable struct _MinimalDomainSampler <: QUBODrivers.AbstractSampler{Float64}
    model::QUBOTools.Model{VI,Float64,Int}
    _MinimalDomainSampler() = new(QUBOTools.Model{VI,Float64,Int}())
end

QUBOTools.backend(sampler::_MinimalDomainSampler) = sampler.model
function QUBODrivers.set_model!(
    sampler::_MinimalDomainSampler,
    model::QUBOTools.Model{VI,Float64,Int},
)
    sampler.model = model
    return model
end
QUBODrivers.supported_domains(::Type{_MinimalDomainSampler}) = Set{Symbol}([:bool, :int, :set])

function test_finite_variable_domains()
    @testset "□ Finite Variable Domains Contract" verbose = true begin
        test_domain_capability_traits()
        test_contiguous_bounded_integer_domains()
        test_arbitrary_finite_encoding_sets()
        test_heterogeneous_domains_and_shifting()
        test_domain_validation_and_rejection()
        test_minimal_domain_sampler_fallback()
    end

    return nothing
end

function test_domain_capability_traits()
    @testset "→ Domain capability traits" begin
        @test QUBODrivers.supported_domains(ExactSampler.Optimizer) == Set([:bool, :spin])
        @test QUBODrivers.supports_domain(ExactSampler.Optimizer, :bool)
        @test QUBODrivers.supports_domain(ExactSampler.Optimizer, QUBOTools.BoolDomain)
        @test QUBODrivers.supports_domain(ExactSampler.Optimizer, :spin)
        @test QUBODrivers.supports_domain(ExactSampler.Optimizer, QUBOTools.SpinDomain)
        @test !QUBODrivers.supports_domain(ExactSampler.Optimizer, :int)
        @test !QUBODrivers.supports_domain(ExactSampler.Optimizer, :set)
        @test_throws ArgumentError QUBODrivers.supports_domain(ExactSampler.Optimizer, :continuous)

        exact_inst = ExactSampler.Optimizer{Float64}()
        @test QUBODrivers.supported_domains(exact_inst) == Set([:bool, :spin])
        @test QUBODrivers.supports_domain(exact_inst, :bool)
        @test !QUBODrivers.supports_domain(exact_inst, :int)
        @test MOI.supports_constraint(exact_inst, VI, MOI.ZeroOne)
        @test MOI.supports_constraint(exact_inst, VI, QUBODrivers.Spin)
        @test !MOI.supports_constraint(exact_inst, VI, MOI.Integer)
        @test !MOI.supports_constraint(exact_inst, VI, MOI.Interval{Float64})
        @test !MOI.supports(exact_inst, QUBODrivers.VariableEncodingSet(), VI)

        fd_inst = _TestFiniteDomainSampler.Optimizer{Float64}()
        @test QUBODrivers.supported_domains(fd_inst) == Set([:bool, :spin, :int, :set])
        @test QUBODrivers.supports_domain(fd_inst, :int)
        @test QUBODrivers.supports_domain(fd_inst, :set)
        @test MOI.supports_constraint(fd_inst, VI, MOI.Integer)
        @test MOI.supports_constraint(fd_inst, VI, MOI.Interval{Float64})
        @test MOI.supports_constraint(fd_inst, VI, MOI.GreaterThan{Float64})
        @test MOI.supports_constraint(fd_inst, VI, MOI.LessThan{Float64})
        @test MOI.supports(fd_inst, QUBODrivers.VariableEncodingSet(), VI)
        @test MOI.supports(fd_inst, _ExternalEncodingAttrModule.VariableEncodingSet(), VI)
    end

    return nothing
end

function test_contiguous_bounded_integer_domains()
    @testset "→ Contiguous bounded integer domains (:int)" begin
        # Quadratic objective with diagonal terms: (x - 2)^2 + (y + 1)^2 + 1.5
        # x ∈ {-1, 0, 1, 2, 3}, y ∈ {-2, -1, 0, 1}
        # Minimum is at (x, y) = (2, -1) with objective 1.5.
        # Notice that if x^2 were collapsed to x (as in :bool) or 1 (as in :spin),
        # the minimum and objective value would be completely wrong.
        model = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
        JuMP.@variable(model, -1 <= x <= 3, Int)
        JuMP.@variable(model, -2.4 <= y <= 1.7, Int) # fractional bounds tighten to [-2, 1]
        JuMP.@variable(model, z, Int)
        JuMP.fix(z, 2; force = true) # fixed integer variable without interval bounds
        JuMP.@objective(model, Min, (x - 2.0)^2 + (y + 1.0)^2 + 0.5 * z + 0.5)

        JuMP.set_start_value(x, 1)
        JuMP.set_start_value(y, 0)

        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        vx = JuMP.index(x)
        vy = JuMP.index(y)
        vz = JuMP.index(z)

        @test QUBODrivers.variable_domain(sampler, vx) == [-1, 0, 1, 2, 3]
        @test QUBODrivers.variable_domain(sampler, vy) == [-2, -1, 0, 1]
        @test QUBODrivers.variable_domain(sampler, vz) == [2]
        @test QUBODrivers.variable_domains(sampler) == [[-1, 0, 1, 2, 3], [-2, -1, 0, 1]]
        @test QUBODrivers.variable_bounds(sampler) == [(-1, 3), (-2, 1)]
        @test QUBODrivers.variable_num_levels(sampler) == [5, 4]
        @test QUBODrivers.levels_to_values(sampler, [0, 0]) == [-1, -2]
        @test QUBODrivers.levels_to_values(sampler, [3, 1]) == [2, -1]
        @test QUBODrivers.values_to_levels(sampler, [2, -1]) == [3, 1]

        @test JuMP.value(x) == 2.0
        @test JuMP.value(y) == -1.0
        @test JuMP.value(z) == 2.0
        @test JuMP.objective_value(model) ≈ 1.5

        @test MOI.get(sampler, MOI.VariablePrimalStart(), vx) == 1
        @test MOI.get(sampler, MOI.VariablePrimalStart(), vy) == 0
        @test MOI.get(sampler, MOI.VariablePrimalStart(), vz) == 2

        # MOI.Integer constraint introspection
        @test MOI.get(sampler, MOI.NumberOfConstraints{VI,MOI.Integer}()) == 3
        @test (VI, MOI.Integer) in MOI.get(sampler, MOI.ListOfConstraintTypesPresent())
        int_cis = MOI.get(sampler, MOI.ListOfConstraintIndices{VI,MOI.Integer}())
        @test length(int_cis) == 3
        @test all(ci -> MOI.is_valid(sampler, ci), int_cis)
        @test !MOI.is_valid(sampler, MOI.ConstraintIndex{VI,MOI.Integer}(4))
        @test MOI.get(sampler, MOI.ConstraintFunction(), int_cis[1]) == vx
        @test MOI.get(sampler, MOI.ConstraintSet(), int_cis[1]) == MOI.Integer()

        # Direct MOI.Interval constraint test
        src = MOIU.UniversalFallback(MOIU.Model{Float64}())
        v1 = MOI.add_variable(src)
        MOI.add_constraint(src, v1, MOI.Integer())
        MOI.add_constraint(src, v1, MOI.Interval(0.0, 2.0))
        MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            src,
            MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
            MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(2.0, v1, v1)],
                [MOI.ScalarAffineTerm(-4.0, v1)],
                4.0,
            ),
        )
        dest = _TestFiniteDomainSampler.Optimizer{Float64}()
        MOI.copy_to(dest, src)
        MOI.optimize!(dest)
        @test QUBODrivers.variable_domain(dest, v1) == [0, 1, 2]
        @test MOI.get(dest, MOI.VariablePrimal(), v1) == 2.0
        @test MOI.get(dest, MOI.ObjectiveValue()) ≈ 0.0
    end

    return nothing
end

function test_arbitrary_finite_encoding_sets()
    @testset "→ Arbitrary finite integer value sets (:set)" begin
        model = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
        JuMP.@variable(model, x)
        JuMP.@variable(model, -5 <= y <= 5, Int)
        JuMP.@variable(model, z)

        # User-specified ordering (including non-sorted order) is preserved
        MOI.set(model, QUBODrivers.VariableEncodingSet(), x, [5, -2, 1])
        MOI.set(JuMP.backend(model), _ExternalEncodingAttrModule.VariableEncodingSet(), JuMP.index(y), [-3, 0, 4])
        MOI.set(model, QUBODrivers.VariableEncodingSet(), z, [10, 20])
        JuMP.fix(z, 20; force = true)

        # Objective: (x - 1)^2 + (y + 3)^2 + 0.1 * z
        # Minimum is at x = 1 (level 2), y = -3 (level 0), z = 20 -> objective 2.0
        JuMP.@objective(model, Min, (x - 1.0)^2 + (y + 3.0)^2 + 0.1 * z)

        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        vx = JuMP.index(x)
        vy = JuMP.index(y)
        vz = JuMP.index(z)

        @test QUBODrivers.variable_domain(sampler, vx) == [5, -2, 1]
        @test QUBODrivers.variable_domain(sampler, vy) == [-3, 0, 4]
        @test QUBODrivers.variable_domain(sampler, vz) == [10, 20]
        @test QUBODrivers.variable_domains(sampler) == [[5, -2, 1], [-3, 0, 4]]
        @test QUBODrivers.variable_bounds(sampler, vx) == (-2, 5)
        @test QUBODrivers.variable_bounds(sampler, vy) == (-3, 4)
        @test QUBODrivers.variable_num_levels(sampler) == [3, 3]

        @test QUBODrivers.levels_to_values(sampler, vx, 0) == 5
        @test QUBODrivers.levels_to_values(sampler, vx, 1) == -2
        @test QUBODrivers.levels_to_values(sampler, vx, 2) == 1
        @test QUBODrivers.values_to_levels(sampler, vx, 5) == 0
        @test QUBODrivers.values_to_levels(sampler, vx, -2) == 1
        @test QUBODrivers.values_to_levels(sampler, vx, 1) == 2
        @test QUBODrivers.levels_to_values(sampler, [2, 0]) == [1, -3]
        @test QUBODrivers.values_to_levels(sampler, [1, -3]) == [2, 0]

        @test MOI.get(sampler, QUBODrivers.VariableEncodingSet(), vx) == [5.0, -2.0, 1.0]
        @test MOI.get(sampler, _ExternalEncodingAttrModule.VariableEncodingSet(), vy) == [-3.0, 0.0, 4.0]
        @test QUBODrivers.VariableEncodingSet() in MOI.get(sampler, MOI.ListOfVariableAttributesSet())

        @test JuMP.value(x) == 1.0
        @test JuMP.value(y) == -3.0
        @test JuMP.value(z) == 20.0
        @test JuMP.objective_value(model) ≈ 2.0

        # Direct MOI.set of VariableEncodingSet on sampler updates the domain
        MOI.set(sampler, QUBODrivers.VariableEncodingSet(), vx, [-4, 2])
        @test QUBODrivers.variable_domain(sampler, vx) == [-4, 2]
        @test_throws ArgumentError MOI.set(sampler, QUBODrivers.VariableEncodingSet(), vx, nothing)
    end

    return nothing
end

function test_heterogeneous_domains_and_shifting()
    @testset "→ Heterogeneous domains & polynomial shift" begin
        # Heterogeneous model combining :bool, :spin, :int, and :set with higher-order objective
        model = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
        JuMP.@variable(model, b, Bin)
        JuMP.@variable(model, s in QUBODrivers.Spin())
        JuMP.@variable(model, -1 <= n <= 1, Int)
        JuMP.@variable(model, q)
        MOI.set(model, QUBODrivers.VariableEncodingSet(), q, [-2, 3])

        # Nonlinear cubic polynomial: (b - 1)^2 + (s + 1)^2 + (n - 1)^2 * (q + 2)^2 + b * n * q
        # Wait: let's use a cubic objective: b * n * q + (n - 1)^2 + (s + 1)^2
        # For b ∈ {0, 1}, s ∈ {-1, 1}, n ∈ {-1, 0, 1}, q ∈ {-2, 3}:
        # At s = -1, (s + 1)^2 = 0.
        # Compare candidates at s = -1:
        # (b=1, n=1, q=-2): 1*1*(-2) + 0 + 0 = -2
        # (b=1, n=-1, q=3): 1*(-1)*3 + (-2)^2 + 0 = -3 + 4 = 1
        # So unique minimum is (b=1, s=-1, n=1, q=-2) with value -2.0.
        JuMP.@objective(model, Min, b * n * q + (n - 1.0)^2 + (s + 1.0)^2)

        JuMP.optimize!(model)

        sampler = JuMP.unsafe_backend(model)
        @test QUBODrivers.variable_domains(sampler) == [[0, 1], [-1, 1], [-1, 0, 1], [-2, 3]]
        @test JuMP.value(b) == 1.0
        @test JuMP.value(s) == -1.0
        @test JuMP.value(n) == 1.0
        @test JuMP.value(q) == -2.0
        @test JuMP.objective_value(model) ≈ -2.0

        # Non-contiguous domains (:spin, :set) reject `shift = true`
        @test_throws ArgumentError QUBODrivers.polynomial_objective(sampler; shift = true)

        # Contiguous domains (:bool + :int) support `shift = true`
        cmodel = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
        JuMP.@variable(cmodel, cb, Bin)
        JuMP.@variable(cmodel, -2 <= cx <= 1, Int)
        JuMP.@variable(cmodel, 3 <= cy <= 5, Int)
        JuMP.@objective(cmodel, Min, (cx + 1.0)^2 * (cy - 4.0) - 2.0 * cb * cx + 1.25)

        JuMP.optimize!(cmodel)
        csampler = JuMP.unsafe_backend(cmodel)

        p_orig = QUBODrivers.polynomial_objective(csampler)
        p_shift = QUBODrivers.polynomial_objective(csampler; shift = true)
        spf_shift = QUBODrivers.polynomial_function(csampler; shift = true)
        vars_orig = MP.variables(p_orig)
        vars_shift = MP.variables(p_shift)

        # Verify shifted polynomial evaluated on zero-based levels matches original on values
        for l_cb in 0:1, l_cx in 0:3, l_cy in 0:2
            lvls = [l_cb, l_cx, l_cy]
            vals = QUBODrivers.levels_to_values(csampler, lvls)
            @test p_shift(vars_shift => Float64.(lvls)) ≈ p_orig(vars_orig => Float64.(vals))
            @test spf_shift.polynomial(vars_shift => Float64.(lvls)) ≈ QUBOTools.value(csampler, vals)
        end
    end

    return nothing
end

function test_domain_validation_and_rejection()
    @testset "→ Domain validation & descriptive rejection" begin
        # 1. Binary-only sampler rejects integer variables and VariableEncodingSet
        @testset "Binary-only sampler rejection" begin
            src_int = MOIU.UniversalFallback(MOIU.Model{Float64}())
            v = MOI.add_variable(src_int)
            MOI.add_constraint(src_int, v, MOI.Integer())
            MOI.add_constraint(src_int, v, MOI.Interval(0.0, 2.0))
            MOI.set(src_int, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(src_int, MOI.ObjectiveFunction{VI}(), v)
            exact = ExactSampler.Optimizer{Float64}()
            @test_throws ArgumentError MOI.copy_to(exact, src_int)

            src_set = MOIU.UniversalFallback(MOIU.Model{Float64}())
            vs = MOI.add_variable(src_set)
            MOI.set(src_set, QUBODrivers.VariableEncodingSet(), vs, [0, 1, 2])
            MOI.set(src_set, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(src_set, MOI.ObjectiveFunction{VI}(), vs)
            @test_throws ArgumentError MOI.copy_to(exact, src_set)
        end

        # 2. Continuous variable without discrete domain is rejected (no silent relaxation)
        @testset "Continuous variable rejection" begin
            model = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
            JuMP.@variable(model, 0 <= x <= 2) # continuous!
            JuMP.@objective(model, Min, x^2)
            @test_throws ArgumentError JuMP.optimize!(model)
        end

        # 3. Unbounded / half-bounded / empty-interval integer variables are rejected
        @testset "Unbounded and empty integer bounds" begin
            for build_var! in (
                m -> JuMP.@variable(m, x, Int),
                m -> JuMP.@variable(m, x >= 0, Int),
                m -> JuMP.@variable(m, x <= 3, Int),
                m -> JuMP.@variable(m, 1.2 <= x <= 1.8, Int),
                m -> JuMP.@variable(m, 3 <= x <= 1, Int),
            )
                m = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
                x = build_var!(m)
                JuMP.@objective(m, Min, x)
                @test_throws ArgumentError JuMP.optimize!(m)
            end
        end

        # 4. Invalid VariableEncodingSet values
        @testset "Invalid VariableEncodingSet" begin
            for bad_set in (
                Int[],
                [1, 2, 1],
                [1.0, 2.5],
                [0.0, Inf],
            )
                m = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
                JuMP.@variable(m, x)
                MOI.set(m, QUBODrivers.VariableEncodingSet(), x, bad_set)
                JuMP.@objective(m, Min, x)
                @test_throws ArgumentError JuMP.optimize!(m)
            end

            # Value set outside variable bounds
            m_oob = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
            JuMP.@variable(m_oob, 0 <= x <= 2, Int)
            MOI.set(m_oob, QUBODrivers.VariableEncodingSet(), x, [0, 1, 3])
            JuMP.@objective(m_oob, Min, x)
            @test_throws ArgumentError JuMP.optimize!(m_oob)

            # Value set on binary or spin variable
            m_bin = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
            JuMP.@variable(m_bin, b, Bin)
            MOI.set(m_bin, QUBODrivers.VariableEncodingSet(), b, [0, 1])
            JuMP.@objective(m_bin, Min, b)
            @test_throws ArgumentError JuMP.optimize!(m_bin)

            m_spin = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
            JuMP.@variable(m_spin, s in QUBODrivers.Spin())
            MOI.set(m_spin, QUBODrivers.VariableEncodingSet(), s, [-1, 1])
            JuMP.@objective(m_spin, Min, s)
            @test_throws ArgumentError JuMP.optimize!(m_spin)
        end

        # 5. Incompatible QUBOTools form / domain casting rejection on non-binary models
        @testset "QUBOTools form & domain casting rejection" begin
            m = JuMP.Model(_TestFiniteDomainSampler.Optimizer)
            JuMP.@variable(m, 0 <= x <= 2, Int)
            JuMP.@objective(m, Min, x^2 - x)
            JuMP.optimize!(m)
            sampler = JuMP.unsafe_backend(m)

            @test_throws ArgumentError QUBOTools.qubo(sampler)
            @test_throws ArgumentError QUBOTools.ising(sampler)
            @test_throws ArgumentError QUBOTools.form(sampler)
            @test_throws ArgumentError QUBOTools.form(sampler, :bool)
            @test_throws ArgumentError QUBODrivers.polynomial_objective(sampler; domain = :bool)
            @test_throws ArgumentError QUBODrivers.polynomial_objective(sampler; domain = :spin)

            # Out-of-range level / value lookup errors
            vx = JuMP.index(x)
            @test_throws ArgumentError QUBODrivers.levels_to_values(sampler, vx, -1)
            @test_throws ArgumentError QUBODrivers.levels_to_values(sampler, vx, 3)
            @test_throws ArgumentError QUBODrivers.values_to_levels(sampler, vx, 5)
            @test_throws DimensionMismatch QUBODrivers.levels_to_values(sampler, [0, 1])
            @test_throws DimensionMismatch QUBODrivers.values_to_levels(sampler, [0, 1])

            # Warm-start validation on non-binary domain
            @test_throws ErrorException MOI.set(sampler, MOI.VariablePrimalStart(), vx, 5)
            @test_throws ErrorException MOI.set(sampler, MOI.VariablePrimalStart(), vx, 1.5)
        end
    end

    return nothing
end

function test_minimal_domain_sampler_fallback()
    @testset "→ Minimal AbstractSampler fallback storage for domains" begin
        src = MOIU.UniversalFallback(MOIU.Model{Float64}())
        v1 = MOI.add_variable(src)
        v2 = MOI.add_variable(src)
        MOI.add_constraint(src, v1, MOI.Integer())
        MOI.add_constraint(src, v1, MOI.Interval(-1.0, 1.0))
        MOI.set(src, QUBODrivers.VariableEncodingSet(), v2, [2, 5])
        MOI.set(src, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            src,
            MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
            MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(2.0, v1, v1)],
                [MOI.ScalarAffineTerm(1.0, v2)],
                0.0,
            ),
        )

        sampler = _MinimalDomainSampler()
        MOI.copy_to(sampler, src)

        @test QUBODrivers.variable_domains(sampler) == [[-1, 0, 1], [2, 5]]
        @test QUBODrivers.variable_bounds(sampler) == [(-1, 1), (2, 5)]
        @test QUBODrivers.variable_num_levels(sampler) == [3, 2]
        @test QUBOTools.value(sampler, [-1, 2]) ≈ 3.0

        MOI.empty!(sampler)
        @test isempty(QUBODrivers.variable_domains(sampler))
    end

    return nothing
end
