# Reference Conformance Prototype for Optional CUDA-Q QAOA Sampler (`JuliaQUBO/QUBODrivers.jl#88`)
#
# This self-contained prototype exercises the `CUDAQOpt.QAOA.Optimizer` contract
# specified in `docs/src/manual/cudaq-design.md` without adding Python `cudaq`
# or GPU SDK dependencies to core `QUBODrivers.jl`.
#
# Upstream attribution:
# Where Hamiltonian construction, target selection, and bitstring decoding
# adapt patterns from `alpha-unito/QSplit`
# (`qsplit/adapters/nvidia/cudaq_qaoa.py` and `qsplit/adapters/nvidia/util.py`
# at revision `4da64b072e702953038addd51cdf54f97f0f9516`), the MIT license
# notice of `alpha-unito/QSplit` (Copyright (c) 2024 alpha-unito) applies.

module CUDAQOptPrototype

import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet
const Random = QUBODrivers.RandomSampler.Random

"""
    probe_cudaq_environment(; pyimport_fn = nothing)

Probe the active Python environment for `cudaq` availability without requiring
quantum hardware credentials. When `PythonCall` is loaded and `pyimport_fn` is
not overridden, queries `sys` and `cudaq`; otherwise returns a deterministic
unavailable-environment descriptor suitable for credential-free unit tests.
"""
function probe_cudaq_environment(; pyimport_fn = nothing)
    if isnothing(pyimport_fn)
        return (
            python_version = "unavailable (credential-free Julia prototype mode)",
            cudaq_version  = "unavailable",
            has_qpp_cpu    = false,
            has_nvidia     = false,
            num_gpus       = 0,
        )
    end

    sys = pyimport_fn("sys")
    py_version = string(getproperty(sys, :version))
    cudaq = try
        pyimport_fn("cudaq")
    catch
        error(
            "Python package `cudaq` is not installed in the active Python environment " *
            "(Python $py_version). Install `cudaq >= 0.8` on a supported platform " *
            "(Linux x86_64/aarch64 or macOS arm64 for CPU targets) before running CUDAQOpt.",
        )
    end

    cudaq_version = hasproperty(cudaq, :__version__) ? string(getproperty(cudaq, :__version__)) : "unknown"
    has_qpp_cpu   = Bool(cudaq.has_target("qpp-cpu"))
    has_nvidia    = Bool(cudaq.has_target("nvidia"))
    num_gpus      = hasproperty(cudaq, :num_available_gpus) ? Int(cudaq.num_available_gpus()) : 0

    return (
        python_version = py_version,
        cudaq_version  = cudaq_version,
        has_qpp_cpu    = has_qpp_cpu,
        has_nvidia     = has_nvidia,
        num_gpus       = num_gpus,
    )
end

module QAOA

import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet
const Random = QUBODrivers.RandomSampler.Random
const AbstractRNG = Random.AbstractRNG

const _TARGET_LOCK = ReentrantLock()
const _PROCESS_ACTIVE_TARGET = Ref{Tuple{String,String}}(("qpp-cpu", "fp64"))
const _VALID_PRECISIONS = ("fp32", "fp64")

QUBODrivers.@setup Optimizer begin
    name       = "CUDAQOpt.QAOA"
    version    = v"0.1.0-prototype"
    attributes = begin
        CircuitDepth["p"]::Integer                                         = 1
        Target["target"]::String                                           = "qpp-cpu"
        TargetOption["target_option"]::Union{String,Nothing}               = nothing
        AllowTargetFallback["allow_target_fallback"]::Bool                 = false
        FallbackCandidates["fallback_candidates"]::Vector{Tuple{String,Union{String,Nothing}}} =
            Tuple{String,Union{String,Nothing}}[("qpp-cpu", "fp64")]
        AvailableTargets["available_targets"]::Vector{String}              = String["qpp-cpu"]
        MaxTargetQubits["max_target_qubits"]::Integer                      = 18
        SimulateMidSolveOOM["simulate_mid_solve_oom"]::Bool                = false
        NumberOfReads["num_reads"]::Integer                                = 1_024
        OptimizerName["optimizer"]::String                                 = "COBYLA"
        MaxIterations["max_iterations"]::Integer                           = 100
        InitialPoint["initial_point"]::Union{Vector{Float64},Nothing}      = nothing
        RandomSeed["seed"]::Union{Integer,Nothing}                         = nothing
    end
end

QUBODrivers.honors_final_reads(::Type{<:Optimizer}) = true
QUBODrivers.supports_seed(::Type{<:Optimizer}) = true

function MOI.get(sampler::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    ω = QUBOTools.solution(sampler)
    metadata = QUBOTools.metadata(ω)
    status = get(metadata, "termination_status", nothing)
    if status isa MOI.TerminationStatusCode
        return status
    end
    return invoke(
        MOI.get,
        Tuple{QUBODrivers.AbstractSampler{T},MOI.TerminationStatus},
        sampler,
        MOI.TerminationStatus(),
    )
end

function _attach_failure_state!(
    sampler::Optimizer{T},
    termination_status::MOI.TerminationStatusCode,
    status_str::String,
    cudaq_meta::Dict{String,Any},
) where {T}
    metadata = Dict{String,Any}(
        "origin"             => "CUDAQOpt.QAOA @ cudaq",
        "status"             => status_str,
        "termination_status" => termination_status,
        "cudaq"              => cudaq_meta,
        "time"               => Dict{String,Any}("total" => 0.0, "effective" => 0.0),
    )
    empty_set = SampleSet{T}(Sample{T,Int}[], metadata; sense = :min, domain = :bool)
    QUBOTools.attach!(sampler, empty_set)
    return nothing
end

function _resolve_target_and_precision(
    requested_target::String,
    target_option::Union{String,Nothing},
    allow_fallback::Bool,
    fallback_candidates::Vector{Tuple{String,Union{String,Nothing}}},
    available_targets::Vector{String},
)
    req_precision = isnothing(target_option) ? "fp64" : target_option
    target_ok = (requested_target in available_targets) && (req_precision in _VALID_PRECISIONS)

    if target_ok
        return (
            selected_target  = requested_target,
            precision        = req_precision,
            fallback_applied = false,
            fallback_reason  = nothing,
        )
    end

    reason = if !(req_precision in _VALID_PRECISIONS)
        "unsupported target_option '$req_precision' for target '$requested_target'"
    else
        "requested target '$requested_target' (option=$(repr(target_option))) is unavailable in $(available_targets)"
    end

    if !allow_fallback
        return (
            selected_target  = requested_target,
            precision        = req_precision,
            fallback_applied = false,
            fallback_reason  = reason,
        )
    end

    for (cand_target, cand_opt) in fallback_candidates
        cand_prec = isnothing(cand_opt) ? "fp64" : cand_opt
        if (cand_target in available_targets) && (cand_prec in _VALID_PRECISIONS)
            return (
                selected_target  = cand_target,
                precision        = cand_prec,
                fallback_applied = true,
                fallback_reason  = reason,
            )
        end
    end

    return (
        selected_target  = requested_target,
        precision        = req_precision,
        fallback_applied = false,
        fallback_reason  = reason,
    )
end

# Cost Hamiltonian H_C = -∑_i h_i Z_{i-1} + ∑_{i<j} J_{ij} Z_{i-1} Z_{j-1}
# For computational basis state |b_1 ... b_n⟩ with b_i ∈ {0, 1}, Z_{i-1}|b_i⟩ = (1 - 2b_i)|b_i⟩ = -s_i|b_i⟩,
# so ⟨b|H_C|b⟩ = ∑_i h_i s_i + ∑_{i<j} J_{ij} s_i s_j where s_i = 2b_i - 1 ∈ {-1, +1}.
function _cost_hamiltonian_diagonal(
    n::Int,
    h::Dict{Int,T},
    J::Dict{Tuple{Int,Int},T},
) where {T}
    num_states = 1 << n
    diag = zeros(Float64, num_states)
    for idx in 0:(num_states - 1)
        e = 0.0
        for (i, hi) in h
            bit_i = (idx >> (i - 1)) & 1
            z_i   = 1.0 - 2.0 * bit_i
            e    += -Float64(hi) * z_i
        end
        for ((i, j), Jij) in J
            bit_i = (idx >> (i - 1)) & 1
            bit_j = (idx >> (j - 1)) & 1
            z_i   = 1.0 - 2.0 * bit_i
            z_j   = 1.0 - 2.0 * bit_j
            e    += Float64(Jij) * z_i * z_j
        end
        diag[idx + 1] = e
    end
    return diag
end

function _qaoa_statevector(
    n::Int,
    diag_cost::Vector{Float64},
    params::Vector{Float64},
    p::Int,
)
    num_states = 1 << n
    inv_sqrt = 1.0 / sqrt(Float64(num_states))
    ψ = fill(ComplexF64(inv_sqrt, 0.0), num_states)

    for layer in 1:p
        γ = params[layer]
        β = params[p + layer]

        # Cost unitary U_C(γ) = exp(-i γ H_C)
        @inbounds for s in 1:num_states
            ψ[s] *= cis(-γ * diag_cost[s])
        end

        # Mixer unitary U_B(β) = ∏_{q=0}^{n-1} R_X(2β, q) where R_X(2β) = cos(β) I - i sin(β) X
        c = cos(β)
        ms = -im * sin(β)
        for q in 0:(n - 1)
            mask = 1 << q
            @inbounds for s in 0:(num_states - 1)
                if (s & mask) == 0
                    i0 = s + 1
                    i1 = (s | mask) + 1
                    a0 = ψ[i0]
                    a1 = ψ[i1]
                    ψ[i0] = c * a0 + ms * a1
                    ψ[i1] = ms * a0 + c * a1
                end
            end
        end
    end

    return abs2.(ψ)
end

function _sample_bitstring_counts(
    rng::AbstractRNG,
    probs::Vector{Float64},
    n::Int,
    shots::Int,
)
    counts = Dict{Vector{Int},Int}()
    num_states = length(probs)
    for _ in 1:shots
        u = rand(rng)
        acc = 0.0
        chosen = num_states - 1
        @inbounds for idx in 0:(num_states - 1)
            acc += probs[idx + 1]
            if u <= acc
                chosen = idx
                break
            end
        end
        bits = Vector{Int}(undef, n)
        @inbounds for q in 1:n
            bits[q] = (chosen >> (q - 1)) & 1
        end
        counts[bits] = get(counts, bits, 0) + 1
    end
    return counts
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    n, h, J, α, β       = QUBOTools.ising(sampler, :dict; sense = :min)
    _, L, Q, α_q, β_q   = QUBOTools.qubo(sampler, :dict; sense = :min)

    p                   = Int(MOI.get(sampler, CircuitDepth()))
    requested_target    = String(MOI.get(sampler, Target()))
    target_option       = MOI.get(sampler, TargetOption())
    allow_fallback      = Bool(MOI.get(sampler, AllowTargetFallback()))
    fallback_candidates = MOI.get(sampler, FallbackCandidates())
    available_targets   = MOI.get(sampler, AvailableTargets())
    max_target_qubits   = Int(MOI.get(sampler, MaxTargetQubits()))
    simulate_oom        = Bool(MOI.get(sampler, SimulateMidSolveOOM()))
    num_reads           = Int(MOI.get(sampler, NumberOfReads()))
    final_num_reads     = Int(MOI.get(sampler, QUBODrivers.FinalNumberOfReads()))
    optimizer_name      = String(MOI.get(sampler, OptimizerName()))
    max_iterations      = Int(MOI.get(sampler, MaxIterations()))
    initial_point       = MOI.get(sampler, InitialPoint())
    seed                = MOI.get(sampler, QUBODrivers.RandomSeed())

    p >= 1 || throw(ArgumentError("QAOA circuit depth `p` must be >= 1, got $p."))
    num_reads >= 1 || throw(ArgumentError("`num_reads` must be >= 1, got $num_reads."))
    final_num_reads >= 1 || throw(ArgumentError("`final_num_reads` must be >= 1, got $final_num_reads."))
    max_iterations >= 1 || throw(ArgumentError("`max_iterations` must be >= 1, got $max_iterations."))
    if !isnothing(initial_point) && length(initial_point) != 2 * p
        throw(ArgumentError("`initial_point` must have length 2p = $(2 * p), got $(length(initial_point))."))
    end

    return @lock _TARGET_LOCK begin
        resolved = _resolve_target_and_precision(
            requested_target,
            target_option,
            allow_fallback,
            fallback_candidates,
            available_targets,
        )

        cudaq_meta = Dict{String,Any}(
            "requested_target" => requested_target,
            "selected_target"  => resolved.selected_target,
            "target_option"    => target_option,
            "precision"        => resolved.precision,
            "fallback_applied" => resolved.fallback_applied,
            "fallback_reason"  => resolved.fallback_reason,
            "num_qubits"       => n,
        )

        if !(resolved.selected_target in available_targets) || !(resolved.precision in _VALID_PRECISIONS)
            _attach_failure_state!(sampler, MOI.OTHER_ERROR, "target_unavailable", cudaq_meta)
            error(
                "CUDAQOpt target initialization failed for target='$(requested_target)', " *
                "target_option=$(repr(target_option)), n=$n: $(resolved.fallback_reason)",
            )
        end

        # Set process-global active target inside the lock
        _PROCESS_ACTIVE_TARGET[] = (resolved.selected_target, resolved.precision)

        # Capacity / memory check (never triggers silent target fallback mid-solve)
        if n > max_target_qubits || simulate_oom
            _attach_failure_state!(sampler, MOI.MEMORY_LIMIT, "memory_limit", cudaq_meta)
            error(
                "CUDAQOpt out-of-memory / capacity limit on target='$(resolved.selected_target)' " *
                "(target_option=$(repr(target_option)), precision='$(resolved.precision)'): " *
                "model has n=$n logical qubits (max_target_qubits=$max_target_qubits, simulate_oom=$simulate_oom).",
            )
        end

        rng = isnothing(seed) ? Random.MersenneTwister(0xC0DA_2026) : Random.MersenneTwister(Int(seed))
        samples = Sample{T,Int}[]
        iterations_performed = 0
        circuit_evaluations  = 0

        timed_run = @timed begin
            t0_ns = time_ns()
            if n == 0
                const_val = convert(T, α * β)
                push!(samples, Sample{T,Int}(Int[], const_val, final_num_reads))
            else
                diag_cost = _cost_hamiltonian_diagonal(n, h, J)
                best_params = isnothing(initial_point) ?
                    Float64[0.35 + 0.1 * (k / (2 * p)) for k in 1:(2 * p)] :
                    copy(initial_point)

                best_probs = _qaoa_statevector(n, diag_cost, best_params, p)
                best_exp   = sum(best_probs[i] * diag_cost[i] for i in eachindex(diag_cost))
                circuit_evaluations  = 1
                iterations_performed = 1

                step_scale = 0.45
                for iter in 2:max_iterations
                    cand_params = Float64[
                        best_params[k] + step_scale * (2.0 * rand(rng) - 1.0) for k in 1:(2 * p)
                    ]
                    cand_probs = _qaoa_statevector(n, diag_cost, cand_params, p)
                    cand_exp   = sum(cand_probs[i] * diag_cost[i] for i in eachindex(diag_cost))
                    circuit_evaluations  += 1
                    iterations_performed += 1
                    if cand_exp < best_exp
                        best_exp    = cand_exp
                        best_params = cand_params
                        best_probs  = cand_probs
                    end
                    step_scale *= 0.92
                end

                counts = _sample_bitstring_counts(rng, best_probs, n, final_num_reads)
                circuit_evaluations += 1

                for (bits, count) in counts
                    λ = QUBOTools.value(bits, L, Q, α_q, β_q)
                    push!(samples, Sample{T,Int}(bits, λ, count))
                end
            end
            while time_ns() == t0_ns
                yield()
            end
        end

        elapsed = timed_run.time
        exec_mode = resolved.selected_target == "qpp-cpu" ? "local_cpu_simulator" : "cudaq_target"
        seeds_dict = isnothing(seed) ? Dict{String,Any}() : Dict{String,Any}("sampler" => Int(seed))

        metadata = QUBODrivers._sampler_metadata(
            origin                = "CUDAQOpt.QAOA @ cudaq",
            algorithm_name        = "QAOA",
            backend_name          = "cudaq",
            backend_version       = "0.8.0-prototype",
            execution_mode        = exec_mode,
            optimizer_iterations  = iterations_performed,
            optimizer_evaluations = circuit_evaluations,
            number_of_reads       = num_reads,
            final_number_of_reads = final_num_reads,
            seeds                 = seeds_dict,
            status                = "locally_solved",
            termination_status    = MOI.LOCALLY_SOLVED,
        )
        metadata["algorithm"]["p"]         = p
        metadata["algorithm"]["optimizer"] = optimizer_name
        metadata["cudaq"]                  = cudaq_meta
        metadata["time"]                   = Dict{String,Any}("effective" => elapsed)

        SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
    end
end

end # module QAOA

end # module CUDAQOptPrototype

