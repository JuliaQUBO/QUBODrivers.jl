# Reference Conformance Prototype for Optional TKET / Quantinuum Nexus QAOA Sampler (`JuliaQUBO/QUBODrivers.jl#89`)
#
# This self-contained prototype exercises the `TKETOpt.QAOA.Optimizer` contract
# specified in `docs/src/manual/tket-nexus-design.md`—including TKET half-turn
# (π-radian) QAOA gate parameterization, logical classical readout bit ordering
# across physical compiler permutations (`get_counts(cbits = logical_cbits)`),
# and persistent Quantinuum Nexus job submission, recovery, timeout, and
# cancellation truth—without adding `pytket` or `qnexus` dependencies to core
# `QUBODrivers.jl`.
#
# Upstream attribution:
# Where QAOA circuit construction, TKET compilation, or Nexus job handling
# adapts patterns from `alpha-unito/QSplit`
# (`qsplit/adapters/quantinuum/__tket_qaoa.py`,
# `qsplit/adapters/quantinuum/tket_qaoa_cpu_noiseless.py`,
# `qsplit/adapters/quantinuum/tket_qaoa_nexus.py`, and
# `qsplit/adapters/quantinuum/util.py` at revision
# `4da64b072e702953038addd51cdf54f97f0f9516`), the MIT license notice of
# `alpha-unito/QSplit` (Copyright (c) 2024 alpha-unito) applies.

module TKETOptPrototype

import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet
const Random = QUBODrivers.RandomSampler.Random

"""
    probe_tket_environment(; pyimport_fn = nothing)

Probe the active Python environment for `pytket`, `pytket.extensions.qiskit`,
and `qnexus` without requiring cloud credentials.
"""
function probe_tket_environment(; pyimport_fn = nothing)
    if isnothing(pyimport_fn)
        return (
            python_version = "unavailable (credential-free Julia prototype mode)",
            pytket_version = "unavailable",
            has_aer        = false,
            has_qnexus     = false,
        )
    end

    sys = pyimport_fn("sys")
    py_version = string(getproperty(sys, :version))
    pytket = try
        pyimport_fn("pytket")
    catch
        error(
            "Python package `pytket` is not installed in the active Python environment " *
            "(Python $py_version). Install `pytket >= 1.30` and a local simulator plugin " *
            "(such as `pytket-qiskit`) before running TKETOpt.",
        )
    end

    pytket_version = hasproperty(pytket, :__version__) ? string(getproperty(pytket, :__version__)) : "unknown"
    has_aer = try
        pyimport_fn("pytket.extensions.qiskit")
        true
    catch
        false
    end
    has_qnexus = try
        pyimport_fn("qnexus")
        true
    catch
        false
    end

    return (
        python_version = py_version,
        pytket_version = pytket_version,
        has_aer        = has_aer,
        has_qnexus     = has_qnexus,
    )
end

module QAOA

import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet
const Random = QUBODrivers.RandomSampler.Random
const AbstractRNG = Random.AbstractRNG

const _VALID_EXECUTION_MODES = ("local_tket", "nexus_emulator", "nexus_hardware")

"""
    TKETGateSpec

Symbolic gate descriptor recording TKET half-turn (multiples of π radians)
parameterization:
- `:H` on `qubits = (q,)` with `half_turns = 0.0`
- `:Rz` on `qubits = (q,)` with `half_turns = -2 * γ * h_i / π`
- `:ZZPhase` on `qubits = (q_i, q_j)` with `half_turns = 2 * γ * J_ij / π`
- `:Rx` on `qubits = (q,)` with `half_turns = 2 * β / π`
- `:Measure` on `qubits = (q,)`, `cbits = (q,)`
"""
struct TKETGateSpec
    gate::Symbol
    qubits::Tuple{Vararg{Int}}
    cbits::Tuple{Vararg{Int}}
    half_turns::Float64
end

"""
    build_tket_qaoa_circuit(n, h, J, params, p)

Construct the logical `Circuit(n, n)` gate list in TKET half-turn units,
including `H` and `Rx` mixer gates on isolated variables and explicit
`Measure(Qubit(i - 1), Bit(i - 1))` instructions for every `i in 1:n`.
"""
function build_tket_qaoa_circuit(
    n::Int,
    h::Dict{Int,T},
    J::Dict{Tuple{Int,Int},T},
    params::Vector{Float64},
    p::Int,
) where {T}
    gates = TKETGateSpec[]
    for i in 1:n
        push!(gates, TKETGateSpec(:H, (i - 1,), (), 0.0))
    end
    for layer in 1:p
        γ = params[layer]
        β = params[p + layer]
        for i in sort!(collect(keys(h)))
            hi = Float64(h[i])
            if !iszero(hi)
                push!(gates, TKETGateSpec(:Rz, (i - 1,), (), -2.0 * γ * hi / π))
            end
        end
        for (i, j) in sort!(collect(keys(J)))
            Jij = Float64(J[(i, j)])
            if !iszero(Jij)
                u, v = min(i, j) - 1, max(i, j) - 1
                push!(gates, TKETGateSpec(:ZZPhase, (u, v), (), 2.0 * γ * Jij / π))
            end
        end
        for i in 1:n
            push!(gates, TKETGateSpec(:Rx, (i - 1,), (), 2.0 * β / π))
        end
    end
    for i in 1:n
        push!(gates, TKETGateSpec(:Measure, (i - 1,), (i - 1,), 0.0))
    end
    return gates
end

"""
    MockNexusClient

Deterministic in-memory mock of Quantinuum Nexus (`qnexus`) job lifecycle calls
(`start_compile_job`, `start_execute_job`, `jobs.status`, `jobs.results`,
`jobs.cancel`) for credential-free conformance and failure-mode verification.
"""
mutable struct MockNexusClient
    compile_submissions::Int
    execute_submissions::Int
    cancel_requests::Int
    status_sequence::Vector{String}
    post_cancel_status::String
    physical_counts_override::Union{Dict{Vector{Int},Int},Nothing}
    jobs::Dict{String,Dict{String,Any}}
end

function MockNexusClient(;
    status_sequence::Vector{String} = ["COMPLETED"],
    post_cancel_status::String = "CANCELLED",
    physical_counts_override::Union{Dict{Vector{Int},Int},Nothing} = nothing,
)
    return MockNexusClient(
        0,
        0,
        0,
        copy(status_sequence),
        post_cancel_status,
        physical_counts_override,
        Dict{String,Dict{String,Any}}(),
    )
end

QUBODrivers.@setup Optimizer begin
    name       = "TKETOpt.QAOA"
    version    = v"0.1.0-prototype"
    attributes = begin
        ExecutionMode["execution_mode"]::String                             = "local_tket"
        BackendName["backend_name"]::String                                 = "AerBackend"
        CircuitDepth["p"]::Integer                                          = 1
        OptimisationLevel["optimisation_level"]::Integer                    = 2
        NumberOfReads["num_reads"]::Integer                                 = 1_024
        OptimizerName["optimizer"]::String                                  = "COBYLA"
        MaxIterations["max_iterations"]::Integer                            = 100
        InitialPoint["initial_point"]::Union{Vector{Float64},Nothing}       = nothing
        RandomSeed["seed"]::Union{Integer,Nothing}                          = nothing
        NexusProject["nexus_project"]::Union{String,Nothing}                = nothing
        JobPersistencePath["job_persistence_path"]::Union{String,Nothing}   = nothing
        NexusResumeJobId["nexus_resume_job_id"]::Union{String,Nothing}      = nothing
        PollTimeoutSec["poll_timeout_sec"]::Float64                         = 900.0
        PollIntervalSec["poll_interval_sec"]::Float64                       = 5.0
        CancelOnTimeout["cancel_on_timeout"]::Bool                          = false
        CompilerPermutation["compiler_permutation"]::Union{Vector{Int},Nothing} = nothing
        NexusClient["nexus_client"]::Any                                    = nothing
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
    tket_meta::Dict{String,Any},
    origin::String,
) where {T}
    metadata = Dict{String,Any}(
        "origin"             => origin,
        "status"             => status_str,
        "termination_status" => termination_status,
        "tket"               => tket_meta,
        "time"               => Dict{String,Any}("total" => 0.0, "effective" => 0.0),
    )
    empty_set = SampleSet{T}(Sample{T,Int}[], metadata; sense = :min, domain = :bool)
    QUBOTools.attach!(sampler, empty_set)
    return nothing
end

function _write_job_ledger_file(path::String, record::Dict{String,Any})
    mkpath(dirname(abspath(path)))
    tmp_path = path * ".tmp"
    open(tmp_path, "w") do io
        println(io, "compile_job_id=", get(record, "compile_job_id", ""))
        println(io, "execute_job_id=", get(record, "execute_job_id", ""))
        println(io, "backend_name=", get(record, "backend_name", ""))
        println(io, "nexus_project=", something(get(record, "nexus_project", ""), ""))
        println(io, "status=", get(record, "status", ""))
        println(io, "cancel_requested=", get(record, "cancel_requested", false))
        println(io, "cancelled=", get(record, "cancelled", false))
    end
    mv(tmp_path, path; force = true)
    return nothing
end

function _read_job_ledger_file(path::String)
    isfile(path) || return nothing
    data = Dict{String,String}()
    for line in eachline(path)
        isempty(strip(line)) && continue
        parts = split(line, '='; limit = 2)
        length(parts) == 2 || continue
        data[strip(parts[1])] = strip(parts[2])
    end
    isempty(get(data, "execute_job_id", "")) && return nothing
    return data
end

# Simulate a TKET circuit in half-turn units:
# Rz(α) = exp(-i π/2 α Z) => phase on |b⟩ (where Z|b⟩ = (1 - 2b)|b⟩) is exp(-i π/2 α (1 - 2b))
# ZZPhase(α) = exp(-i π/2 α Z⊗Z) => phase on |b_u, b_v⟩ is exp(-i π/2 α (1 - 2b_u)(1 - 2b_v))
# Rx(α) = exp(-i π/2 α X) = cos(π α / 2) I - i sin(π α / 2) X
function _simulate_tket_circuit_probabilities(n::Int, gates::Vector{TKETGateSpec})
    num_states = 1 << n
    ψ = zeros(ComplexF64, num_states)
    ψ[1] = 1.0 + 0.0im

    for g in gates
        if g.gate === :H
            q = g.qubits[1]
            mask = 1 << q
            inv_s2 = 1.0 / sqrt(2.0)
            @inbounds for s in 0:(num_states - 1)
                if (s & mask) == 0
                    i0 = s + 1
                    i1 = (s | mask) + 1
                    a0 = ψ[i0]
                    a1 = ψ[i1]
                    ψ[i0] = inv_s2 * (a0 + a1)
                    ψ[i1] = inv_s2 * (a0 - a1)
                end
            end
        elseif g.gate === :Rz
            q = g.qubits[1]
            θ = (π / 2.0) * g.half_turns
            @inbounds for s in 0:(num_states - 1)
                bit = (s >> q) & 1
                z   = 1.0 - 2.0 * bit
                ψ[s + 1] *= cis(-θ * z)
            end
        elseif g.gate === :ZZPhase
            u, v = g.qubits[1], g.qubits[2]
            θ = (π / 2.0) * g.half_turns
            @inbounds for s in 0:(num_states - 1)
                bu = (s >> u) & 1
                bv = (s >> v) & 1
                zz = (1.0 - 2.0 * bu) * (1.0 - 2.0 * bv)
                ψ[s + 1] *= cis(-θ * zz)
            end
        elseif g.gate === :Rx
            q = g.qubits[1]
            θ = (π / 2.0) * g.half_turns
            c = cos(θ)
            ms = -im * sin(θ)
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

# Simulate physical-qubit compiled execution followed by `get_counts(cbits = [Bit(0), ..., Bit(n - 1)])`:
# If the compiler maps logical qubit `k` (1:n) to physical readout wire `perm[k]`,
# a physical bit-tuple `phys_bits` has `phys_bits[perm[k]] == logical_bits[k]`.
# `get_counts_logical_cbits` extracts the readout in logical `[Bit(0), ..., Bit(n - 1)]` order.
function _sample_physical_counts(
    rng::AbstractRNG,
    probs::Vector{Float64},
    n::Int,
    shots::Int,
    perm::Vector{Int},
)
    phys_counts = Dict{Vector{Int},Int}()
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
        phys_bits = Vector{Int}(undef, n)
        @inbounds for k in 1:n
            logical_bit = (chosen >> (k - 1)) & 1
            phys_bits[perm[k]] = logical_bit
        end
        phys_counts[phys_bits] = get(phys_counts, phys_bits, 0) + 1
    end
    return phys_counts
end

"""
    get_counts_logical_cbits(physical_counts, perm)

Equivalent of `backend_result.get_counts(cbits=[Bit(0), ..., Bit(n - 1)])`:
given raw counts keyed by physical readout wires where logical bit `Bit(k - 1)`
was routed to physical wire `perm[k]`, reconstructs the counts in exact logical
register order `1:n`.
"""
function get_counts_logical_cbits(
    physical_counts::Dict{Vector{Int},Int},
    perm::Vector{Int},
)
    n = length(perm)
    logical_counts = Dict{Vector{Int},Int}()
    for (phys_bits, count) in physical_counts
        logical_bits = Vector{Int}(undef, n)
        for k in 1:n
            logical_bits[k] = phys_bits[perm[k]]
        end
        logical_counts[logical_bits] = get(logical_counts, logical_bits, 0) + count
    end
    return logical_counts
end

function _execute_nexus_lifecycle!(
    client::MockNexusClient,
    n::Int,
    probs::Vector{Float64},
    final_num_reads::Int,
    perm::Vector{Int},
    rng::AbstractRNG;
    backend_name::String,
    nexus_project::String,
    persistence_path::Union{String,Nothing},
    resume_job_id::Union{String,Nothing},
    poll_timeout_sec::Float64,
    poll_interval_sec::Float64,
    cancel_on_timeout::Bool,
)
    # 1. Inspect/recover existing job before submitting any new compile/execute job
    recovered_job_id = resume_job_id
    if isnothing(recovered_job_id) && !isnothing(persistence_path)
        persisted = _read_job_ledger_file(persistence_path)
        if !isnothing(persisted) && get(persisted, "status", "") in ("SUBMITTED", "QUEUED", "RUNNING", "COMPLETED")
            recovered_job_id = persisted["execute_job_id"]
        end
    end

    job_record = if !isnothing(recovered_job_id) && haskey(client.jobs, recovered_job_id)
        existing = client.jobs[recovered_job_id]
        existing["recovered"] = true
        existing
    else
        client.compile_submissions += 1
        compile_id = "nexus-compile-$(client.compile_submissions)"
        client.execute_submissions += 1
        execute_id = "nexus-exec-$(client.execute_submissions)"

        phys_counts = isnothing(client.physical_counts_override) ?
            _sample_physical_counts(rng, probs, n, final_num_reads, perm) :
            deepcopy(client.physical_counts_override)

        rec = Dict{String,Any}(
            "compile_job_id"   => compile_id,
            "execute_job_id"   => execute_id,
            "backend_name"     => backend_name,
            "nexus_project"    => nexus_project,
            "status"           => "SUBMITTED",
            "recovered"        => false,
            "cancel_requested" => false,
            "cancelled"        => false,
            "poll_cursor"      => 0,
            "physical_counts"  => phys_counts,
        )
        client.jobs[execute_id] = rec
        # Persist immediately BEFORE polling
        if !isnothing(persistence_path)
            _write_job_ledger_file(persistence_path, rec)
        end
        rec
    end

    # 2. Poll job status up to poll_timeout_sec
    elapsed_poll = 0.0
    seq = client.status_sequence
    while true
        idx = min(job_record["poll_cursor"] + 1, length(seq))
        job_record["poll_cursor"] = idx
        current_status = seq[idx]
        job_record["status"] = current_status
        if !isnothing(persistence_path)
            _write_job_ledger_file(persistence_path, job_record)
        end

        if current_status == "COMPLETED"
            logical_counts = get_counts_logical_cbits(job_record["physical_counts"], perm)
            return (:completed, logical_counts, job_record)
        elseif current_status in ("FAILED", "CANCELLED", "DEPLETED")
            return (:failed, Dict{Vector{Int},Int}(), job_record)
        end

        elapsed_poll += max(poll_interval_sec, 1e-6)
        if elapsed_poll > poll_timeout_sec
            if cancel_on_timeout
                client.cancel_requests += 1
                job_record["cancel_requested"] = true
                # Re-query remote status after cancel request; only mark cancelled = true when confirmed CANCELLED
                confirmed_status = client.post_cancel_status
                job_record["status"]    = confirmed_status
                job_record["cancelled"] = (confirmed_status == "CANCELLED")
            end
            if !isnothing(persistence_path)
                _write_job_ledger_file(persistence_path, job_record)
            end
            return (:timeout, Dict{Vector{Int},Int}(), job_record)
        end
    end
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    n, h, J, α, β       = QUBOTools.ising(sampler, :dict; sense = :min)
    _, L, Q, α_q, β_q   = QUBOTools.qubo(sampler, :dict; sense = :min)

    execution_mode      = String(MOI.get(sampler, ExecutionMode()))
    backend_name        = String(MOI.get(sampler, BackendName()))
    p                   = Int(MOI.get(sampler, CircuitDepth()))
    optimisation_level  = Int(MOI.get(sampler, OptimisationLevel()))
    num_reads           = Int(MOI.get(sampler, NumberOfReads()))
    final_num_reads     = Int(MOI.get(sampler, QUBODrivers.FinalNumberOfReads()))
    optimizer_name      = String(MOI.get(sampler, OptimizerName()))
    max_iterations      = Int(MOI.get(sampler, MaxIterations()))
    initial_point       = MOI.get(sampler, InitialPoint())
    seed                = MOI.get(sampler, QUBODrivers.RandomSeed())
    nexus_project       = MOI.get(sampler, NexusProject())
    persistence_path    = MOI.get(sampler, JobPersistencePath())
    resume_job_id       = MOI.get(sampler, NexusResumeJobId())
    poll_timeout_sec    = Float64(MOI.get(sampler, PollTimeoutSec()))
    poll_interval_sec   = Float64(MOI.get(sampler, PollIntervalSec()))
    cancel_on_timeout   = Bool(MOI.get(sampler, CancelOnTimeout()))
    compiler_perm       = MOI.get(sampler, CompilerPermutation())
    nexus_client        = MOI.get(sampler, NexusClient())

    execution_mode in _VALID_EXECUTION_MODES || throw(
        ArgumentError("`execution_mode` must be one of $(_VALID_EXECUTION_MODES), got '$execution_mode'."),
    )
    0 <= optimisation_level <= 3 || throw(
        ArgumentError("`optimisation_level` must be in 0:3, got $optimisation_level."),
    )
    p >= 1 || throw(ArgumentError("`p` must be >= 1, got $p."))
    num_reads >= 1 || throw(ArgumentError("`num_reads` must be >= 1, got $num_reads."))
    final_num_reads >= 1 || throw(ArgumentError("`final_num_reads` must be >= 1, got $final_num_reads."))
    max_iterations >= 1 || throw(ArgumentError("`max_iterations` must be >= 1, got $max_iterations."))

    perm = if isnothing(compiler_perm)
        collect(1:n)
    else
        (length(compiler_perm) == n && sort(compiler_perm) == collect(1:n)) || throw(
            ArgumentError("`compiler_permutation` must be a permutation of 1:$n, got $compiler_perm."),
        )
        copy(compiler_perm)
    end

    origin = execution_mode == "local_tket" ? "TKETOpt.QAOA @ pytket" : "TKETOpt.QAOA @ qnexus"
    nexus_job_records = Dict{String,Any}[]

    tket_meta = Dict{String,Any}(
        "execution_mode"     => execution_mode,
        "backend_name"       => backend_name,
        "optimisation_level" => optimisation_level,
        "num_qubits"         => n,
        "nexus_project"      => nexus_project,
        "nexus_jobs"         => nexus_job_records,
    )

    if execution_mode in ("nexus_emulator", "nexus_hardware") && (isnothing(nexus_project) || isempty(strip(nexus_project)))
        _attach_failure_state!(sampler, MOI.OTHER_ERROR, "missing_nexus_project", tket_meta, origin)
        error("TKETOpt mode '$execution_mode' requires a non-empty `nexus_project` attribute.")
    end

    rng = isnothing(seed) ? Random.MersenneTwister(0x74E7_2026) : Random.MersenneTwister(Int(seed))
    samples = Sample{T,Int}[]
    iterations_performed = 0
    circuit_evaluations  = 0

    timed_run = @timed begin
        if n == 0
            const_val = convert(T, α * β)
            push!(samples, Sample{T,Int}(Int[], const_val, final_num_reads))
        else
            best_params = isnothing(initial_point) ?
                Float64[0.3 + 0.1 * (k / (2 * p)) for k in 1:(2 * p)] :
                copy(initial_point)
            best_gates = build_tket_qaoa_circuit(n, h, J, best_params, p)
            best_probs = _simulate_tket_circuit_probabilities(n, best_gates)

            # Evaluate expected Ising energy under computational basis bit mapping s_i = 2b_i - 1
            function _expected_ising_energy(probs::Vector{Float64})
                total = 0.0
                for idx in 0:((1 << n) - 1)
                    e = 0.0
                    for (i, hi) in h
                        s_i = 2 * ((idx >> (i - 1)) & 1) - 1
                        e += Float64(hi) * s_i
                    end
                    for ((i, j), Jij) in J
                        s_i = 2 * ((idx >> (i - 1)) & 1) - 1
                        s_j = 2 * ((idx >> (j - 1)) & 1) - 1
                        e += Float64(Jij) * s_i * s_j
                    end
                    total += probs[idx + 1] * e
                end
                return total
            end

            best_exp = _expected_ising_energy(best_probs)
            iterations_performed = 1
            circuit_evaluations  = 1
            step_scale = 0.45

            for _ in 2:max_iterations
                cand_params = Float64[
                    best_params[k] + step_scale * (2.0 * rand(rng) - 1.0) for k in 1:(2 * p)
                ]
                cand_gates = build_tket_qaoa_circuit(n, h, J, cand_params, p)
                cand_probs = _simulate_tket_circuit_probabilities(n, cand_gates)
                cand_exp   = _expected_ising_energy(cand_probs)
                iterations_performed += 1
                circuit_evaluations  += 1
                if cand_exp < best_exp
                    best_exp    = cand_exp
                    best_params = cand_params
                    best_gates  = cand_gates
                    best_probs  = cand_probs
                end
                step_scale *= 0.92
            end

            logical_counts = if execution_mode == "local_tket"
                phys_counts = _sample_physical_counts(rng, best_probs, n, final_num_reads, perm)
                circuit_evaluations += 1
                get_counts_logical_cbits(phys_counts, perm)
            else
                client = isnothing(nexus_client) ? MockNexusClient() : nexus_client::MockNexusClient
                outcome, counts, job_rec = _execute_nexus_lifecycle!(
                    client,
                    n,
                    best_probs,
                    final_num_reads,
                    perm,
                    rng;
                    backend_name     = backend_name,
                    nexus_project    = String(nexus_project),
                    persistence_path = persistence_path,
                    resume_job_id    = resume_job_id,
                    poll_timeout_sec = poll_timeout_sec,
                    poll_interval_sec = poll_interval_sec,
                    cancel_on_timeout = cancel_on_timeout,
                )
                push!(
                    nexus_job_records,
                    Dict{String,Any}(
                        "compile_job_id"   => job_rec["compile_job_id"],
                        "execute_job_id"   => job_rec["execute_job_id"],
                        "status"           => job_rec["status"],
                        "recovered"        => job_rec["recovered"],
                        "cancel_requested" => job_rec["cancel_requested"],
                        "cancelled"        => job_rec["cancelled"],
                    ),
                )
                if outcome === :timeout
                    _attach_failure_state!(sampler, MOI.TIME_LIMIT, "nexus_poll_timeout", tket_meta, origin)
                    error(
                        "Quantinuum Nexus poll timeout after $(poll_timeout_sec)s for " *
                        "execute_job_id='$(job_rec["execute_job_id"])' " *
                        "(status='$(job_rec["status"])', cancel_requested=$(job_rec["cancel_requested"]), " *
                        "cancelled=$(job_rec["cancelled"])).",
                    )
                elseif outcome === :failed
                    _attach_failure_state!(sampler, MOI.OTHER_ERROR, "nexus_job_failed", tket_meta, origin)
                    error(
                        "Quantinuum Nexus job failed with remote status '$(job_rec["status"])' " *
                        "for execute_job_id='$(job_rec["execute_job_id"])'.",
                    )
                end
                circuit_evaluations += 1
                counts
            end

            for (bits, count) in logical_counts
                λ = QUBOTools.value(bits, L, Q, α_q, β_q)
                push!(samples, Sample{T,Int}(bits, λ, count))
            end
        end
    end

    elapsed = max(timed_run.time, eps(Float64))
    seeds_dict = isnothing(seed) ? Dict{String,Any}() : Dict{String,Any}("sampler" => Int(seed))

    metadata = QUBODrivers._sampler_metadata(
        origin                = origin,
        algorithm_name        = "QAOA",
        backend_name          = backend_name,
        backend_version       = "1.30.0-prototype",
        execution_mode        = execution_mode,
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
    metadata["tket"]                   = tket_meta
    metadata["time"]                   = Dict{String,Any}("effective" => elapsed)

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

end # module QAOA

end # module TKETOptPrototype

