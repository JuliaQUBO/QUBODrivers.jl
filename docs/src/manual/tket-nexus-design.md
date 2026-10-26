# Optional TKET / Quantinuum Nexus Sampler Design

This page records the contract and package-boundary design for an optional
TKET and Quantinuum Nexus Quantum Approximate Optimization Algorithm (QAOA)
sampler wrapper for the JuliaQUBO ecosystem
([`JuliaQUBO/QUBODrivers.jl#89`](https://github.com/JuliaQUBO/QUBODrivers.jl/issues/89)).
It specifies package ownership, the separation between credential-free local
`pytket` execution and remote Quantinuum Nexus job execution, logical-to-physical
circuit bit mapping, persistent Nexus job recovery without duplicate paid
submissions, and the local conformance and mocked lifecycle test plan.

!!! note "Design Status, Executable Conformance Prototype, and Package Boundary"
    `QUBODrivers.jl` hosts this interface specification, the self-contained
    executable conformance prototype in
    `examples/tket_nexus_prototype.jl` (`TKETOptPrototype.QAOA.Optimizer`,
    exercised in CI by `test/drivers/optional_qaoa_prototypes.jl`), and the
    conformance checklist only; it does **not** import `pytket` or `qnexus`, and
    no TKET or Quantinuum SDK dependencies are added to `QUBODrivers.jl`,
    `QUBOTools.jl`, `ToQUBO.jl`, `QUBO.jl`, or `QUBODecomposition.jl`. Standalone
    package publication (`TKETOpt.jl`) is explicitly deferred until a dedicated
    wrapper repository with an isolated `pytket` / `qnexus` Python environment is
    provisioned; when published, it will be added to the
    [External Sampler Packages](@ref) table in
    [`docs/src/manual/3-samplers.md`](3-samplers.md).

## Ownership and Package Placement

- **Proposed package and module**: A standalone optional wrapper package,
  `TKETOpt.jl` (hosted under `JuliaQUBO` or `SECQUOIA`), exposing
  `TKETOpt.QAOA.Optimizer{T} <: QUBODrivers.AbstractSampler{T}` generated via
  [`QUBODrivers.@setup`](@ref).
- **Zero vendor leakage into core packages**: `QUBODrivers.jl` and
  `QUBODecomposition.jl` interact with `TKETOpt.QAOA.Optimizer` exclusively
  through the public [`QUBODrivers.AbstractSampler`](@ref) and MathOptInterface
  contracts (see [Public composition pattern](@ref)).
- **Isolated Python environment**: `pytket`, local simulator backends (such as
  `pytket-qiskit` or `pytket` state/shot simulators), and `qnexus` have distinct
  version and dependency constraints from `QiskitOpt.jl` and IQM clients. The
  standalone package must document an isolated CondaPkg / PythonCall environment
  so users can install `TKETOpt.jl` without conflicting with `QiskitOpt.jl`.
- **Upstream reference attribution**: Where QAOA circuit construction, local
  TKET compilation, or Nexus submission adapts patterns from
  [`alpha-unito/QSplit`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/quantinuum/__tket_qaoa.py)
  ([`tket_qaoa_cpu_noiseless.py`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/quantinuum/tket_qaoa_cpu_noiseless.py),
  [`tket_qaoa_nexus.py`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/quantinuum/tket_qaoa_nexus.py),
  and [`util.py`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/quantinuum/util.py)),
  the wrapper repository must preserve the
  [QSplit MIT license notice](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/LICENSE)
  and record the adapted revision (`4da64b072e702953038addd51cdf54f97f0f9516`).

## Minimum Sampler Surface and Execution Modes

`TKETOpt.QAOA.Optimizer` must explicitly separate local credential-free TKET
simulation from remote Quantinuum Nexus emulator and hardware execution rather
than assuming IBM Qiskit primitive compatibility:

| Attribute / Raw Key | Type & Default | Contract |
| :-- | :-- | :-- |
| `"execution_mode"` | `String = "local_tket"` | Explicit execution route: `"local_tket"` (credential-free local `pytket` backend), `"nexus_emulator"` (remote Quantinuum Nexus emulator), or `"nexus_hardware"` (remote Quantinuum QPU). |
| `"backend_name"` | `String = "AerBackend"` | Target backend identifier (for example `"AerBackend"` in `"local_tket"` mode, or `"H1-1E"` / `"H1-1"` in Nexus modes). |
| `"p"` | `Integer = 1` | QAOA circuit depth ($p \ge 1$), parameterizing $2p$ angles $(\gamma_1, \dots, \gamma_p, \beta_1, \dots, \beta_p)$. |
| `"optimisation_level"` | `Integer = 2` | TKET compiler optimization level (`0`, `1`, `2`, or `3`) passed to `backend.get_compiled_circuit` or `qnexus.start_compile_job`. |
| `"num_reads"` | `Integer = 1_024` | Shot count (`n_shots`) per circuit evaluation during variational parameter optimization. |
| [`QUBODrivers.FinalNumberOfReads()`](@ref) / `"final_num_reads"` | `Union{Integer,Nothing} = nothing` | Shot count (`n_shots`) used for final sample-set generation (`honors_final_reads(::Type{<:Optimizer}) = true`; defaults to `"num_reads"` when unset). |
| `"optimizer"` | `String = "COBYLA"` | Classical outer-loop optimizer name. |
| `"max_iterations"` | `Integer = 100` | Maximum classical optimizer iterations (`max_iterations >= 1`). |
| `"initial_point"` | `Union{Vector{Float64},Nothing} = nothing` | Optional length-$2p$ initial parameter vector; when `nothing`, initialized deterministically from `"seed"`. |
| [`QUBODrivers.RandomSeed()`](@ref) / `"seed"` | `Union{Integer,Nothing} = nothing` | Seed forwarded to local backend shot sampling (`seed` keyword in `process_circuits` / `get_result`) and classical optimizer initialization (`supports_seed(::Type{<:Optimizer}) = true`). |
| `"nexus_project"` | `Union{String,Nothing} = nothing` | Explicit Quantinuum Nexus project name or reference (required for `"nexus_emulator"` and `"nexus_hardware"` modes). |
| `"job_persistence_path"` | `Union{String,Nothing} = nothing` | Optional JSON file path where accepted Nexus compile/execute job descriptors are persisted immediately upon submission. |
| `"nexus_resume_job_id"` | `Union{String,Nothing} = nothing` | Optional existing Nexus execute job ID to inspect/retrieve before submitting any new remote compilation or execution job. |
| `"poll_timeout_sec"` | `Float64 = 900.0` | Maximum wall-clock seconds to wait for a submitted Nexus compile or execute job before timing out. |
| `"poll_interval_sec"` | `Float64 = 5.0` | Polling interval in seconds when checking Nexus job status. |
| `"cancel_on_timeout"` | `Bool = false` | Whether to issue a best-effort cancellation request (`qnexus.jobs.cancel`) when polling exceeds `"poll_timeout_sec"`. |

## Model Lowering, Compiled-Circuit Bit Mapping, and Scoring

1. **Logical variable order and `QUBOTools` spin convention**:
   Retrieve the internal model in `QUBOTools.variables(sampler)` order (`1:n`)
   via `n, h, J, α, β = QUBOTools.ising(sampler, :dict; sense = :min)`.
   In `QUBOTools.jl`, `BoolDomain` ($x_i \in \{0, 1\}$) and `SpinDomain`
   ($s_i \in \{-1, +1\}$) are related by $s_i = 2x_i - 1$ ($x_i = (1 + s_i)/2$,
   so $x_i = 0 \leftrightarrow s_i = -1$ and $x_i = 1 \leftrightarrow s_i = +1$).
   Under computational-basis bit encoding $|x_i\rangle$ ($b_i = 0 \leftrightarrow x_i = 0$,
   $b_i = 1 \leftrightarrow x_i = 1$), the Pauli-$Z$ operator satisfies
   $Z_{i-1}|x_i\rangle = (1 - 2x_i)|x_i\rangle = -s_i|x_i\rangle$. Substituting
   $s_i = -Z_{i-1}$ into the `QUBOTools.ising` form (equivalently substituting
   $x_i = (I - Z_{i-1})/2$ into `QUBOTools.qubo`) gives the Pauli-$Z$ Cost
   Hamiltonian:
   ```math
   H_C = -\sum_{i=1}^{n} h_i Z_{i-1} + \sum_{1 \le i < j \le n} J_{ij} Z_{i-1} Z_{j-1}
   ```
2. **TKET half-turn ($\pi$-radian) gate parameterization and isolated qubits**:
   Allocate `Circuit(n, n)` with logical qubits `Qubit(0)` through
   `Qubit(n - 1)` and classical readout bits `Bit(0)` through `Bit(n - 1)`.
   - Initialize every qubit $i \in 1:n$ (including isolated variables with zero
     linear and quadratic terms) with `H(i - 1)`.
   - Because `pytket` rotation gates (`Rz`, `Rx`, `ZZPhase`) take angles in
     **half-turns** (multiples of $\pi$ radians, where $\text{Rz}(\alpha) = e^{-i \frac{\pi}{2} \alpha Z}$
     and $\text{ZZPhase}(\alpha) = e^{-i \frac{\pi}{2} \alpha (Z \otimes Z)}$),
     layer $l \in 1:p$ applies:
     - `Rz(-2 * γ_l * h_i / π, i - 1)` for each nonzero linear term $h_i$,
     - `ZZPhase(2 * γ_l * J_{ij} / π, i - 1, j - 1)` for each nonzero quadratic
       term $J_{ij}$ ($1 \le i < j \le n$), and
     - mixer `Rx(2 * β_l / π, i - 1)` on every qubit $i \in 1:n$.
   - Append `Measure(Qubit(i - 1), Bit(i - 1))` for every $i \in 1:n$.
3. **Preserving logical variable order across TKET compilation**:
   TKET compilation passes (`backend.get_compiled_circuit` or
   `qnexus.start_compile_job`) may relabel or permute physical qubits. To
   guarantee that readout bit $k - 1$ always corresponds to logical variable
   `QUBOTools.variables(sampler)[k]`:
   - Always request shot counts explicitly ordered by the logical classical
     register bits:
     ```python
     logical_cbits = [Bit(i) for i in range(n)]
     counts = backend_result.get_counts(cbits=logical_cbits)
     ```
   - For each `(bit_tuple, count)` in `counts.items()`:
     - When constructing a `:bool` `SampleSet` (`domain = :bool`), map
       `x_k = Int(bit_tuple[k])` (`0` or `1`) and score with
       $\lambda = \text{QUBOTools.value}(x, L, Q, \alpha_q, \beta_q)$ from
       `QUBOTools.qubo(sampler, :dict; sense = :min)`.
     - When constructing a `:spin` `SampleSet` (`domain = :spin`), map
       `s_k = (Int(bit_tuple[k]) == 1 ? 1 : -1)` and score with
       $\lambda = \text{QUBOTools.value}(s, h, J, \alpha, \beta)$ from
       `QUBOTools.ising(sampler, :dict; sense = :min)`.
     - Emit `QUBOTools.Sample{T,Int}(ψ, λ, Int(count))` so shot multiplicities
       round-trip as sample read counts (`sum(counts) == final_num_reads`).

## Nexus Job Lifecycle, Persistence, and Non-Resubmission Contract

Remote execution in `"nexus_emulator"` and `"nexus_hardware"` modes uses
asynchronous compilation and execution jobs (`qnexus.start_compile_job`,
`qnexus.start_execute_job`). Because Quantinuum hardware and cloud emulator
credits are metered, the wrapper must enforce strict job-lifecycle safety:

1. **Persist job identity before polling**:
   Immediately after `start_compile_job` or `start_execute_job` returns an
   accepted job handle, record its `"compile_job_id"` / `"execute_job_id"`,
   `"backend_name"`, `"nexus_project"`, `"submitted_at"`, and logical variable
   order in memory and—when `"job_persistence_path"` is configured—atomically
   write the job ledger to disk **before** entering any polling wait loop.
2. **Inspect/recover before retry (no silent resubmission)**:
   - If `"nexus_resume_job_id"` is provided (or an in-flight job entry already
     exists in `"job_persistence_path"` for the active solve), query
     `qnexus.jobs.get(id=job_id)` and `qnexus.jobs.status(job)` first:
     - If the job is `COMPLETED`, retrieve its `BackendResult` via
       `qnexus.jobs.results(job)` without submitting a new job.
     - If the job is `QUEUED`, `RUNNING`, or `SUBMITTED`, resume polling that
       existing job up to `"poll_timeout_sec"`.
     - If the job is `FAILED`, `CANCELLED`, or `DEPLETED`, do **not** silently
       submit a replacement job; surface the remote status and error details.
   - If a network error occurs during submission itself and it is unknown whether
     Nexus accepted the job, query recent project jobs matching the run's unique
     client job name/tag before attempting any retry.
3. **Timeout and cancellation truth**:
   - When polling exceeds `"poll_timeout_sec"`, if `"cancel_on_timeout" = true`,
     call `qnexus.jobs.cancel(job)` and record `"cancel_requested" = true`.
   - Never equate a cancellation request with confirmed cancellation: re-query
     `qnexus.jobs.status(job)` and set `"cancelled" = true` only when the remote
     status is confirmed as `CANCELLED`.
   - On timeout or remote failure, clear any stale sample results from previous
     solves, set `MOI.TerminationStatus()` to `MOI.TIME_LIMIT` (on poll timeout)
     or `MOI.OTHER_ERROR` (on remote job failure), preserve the job ledger in
     `metadata["tket"]["nexus_jobs"]`, and throw an exception containing the
     `execute_job_id` so the user can resume retrieval later.

## Metadata Contract

Every completed solve must pass [`QUBODrivers.validate_metadata`](@ref) with zero
violations and populate:

- `"origin"`: `"TKETOpt.QAOA @ pytket"` (or `"TKETOpt.QAOA @ qnexus"`)
- `"algorithm"`: `Dict("name" => "QAOA", "p" => p, "optimizer" => optimizer_name)`
- `"backend"`: `Dict("name" => backend_name, "version" => pytket_version)`
- `"execution"`: `Dict("mode" => execution_mode)` (`"local_tket"`, `"nexus_emulator"`, or `"nexus_hardware"`)
- `"optimizer"`: `Dict("iterations" => iterations_performed, "evaluations" => circuit_evaluations)`
- `"reads"`: `Dict("number_of_reads" => num_reads, "final_number_of_reads" => final_num_reads)`
- `"seeds"`: `Dict("sampler" => seed)` when seeded
- `"tket"`:
  ```julia
  Dict{String,Any}(
      "execution_mode"     => execution_mode,
      "backend_name"       => backend_name,
      "optimisation_level" => optimisation_level,
      "num_qubits"         => n,
      "nexus_project"      => nexus_project,
      "nexus_jobs"         => nexus_job_records, # compile/execute IDs, statuses, cancel flags
  )
  ```

## Local Backend Conformance and Mocked Lifecycle Test Plan

### Supported Python / TKET Environment Probe

```julia
using PythonCall

function probe_tket_environment()
    sys = pyimport("sys")
    py_version = pyconvert(String, sys.version)
    pytket = try
        pyimport("pytket")
    catch err
        error(
            "Python package `pytket` is not installed in the active PythonCall environment " *
            "(Python $py_version). Install `pytket >= 1.30` and a local simulator plugin " *
            "(such as `pytket-qiskit`) before running TKETOpt.",
        )
    end

    pytket_version = hasproperty(pytket, :__version__) ?
        pyconvert(String, pytket.__version__) : "unknown"
    has_aer = try
        pyimport("pytket.extensions.qiskit")
        true
    catch
        false
    end
    has_qnexus = try
        pyimport("qnexus")
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
```

### Verification Suite for the Standalone Package

1. **Credential-free local TKET conformance (`"execution_mode" => "local_tket"`)**:
   - Run `QUBODrivers.test(TKETOpt.QAOA.Optimizer; examples = true, benchmark_conformance = true)`
     using a local simulator backend (`AerBackend`), `"p" => 1`,
     `"num_reads" => 64`, `"max_iterations" => 5`, and `"seed" => 42`.
   - Verify a QUBO with reordered `MOI.VariableIndex` IDs, non-zero scale and
     constant offset, isolated variables, fixed variables, and non-uniform shot
     multiplicities, independently checking every returned sample's energy
     against `QUBOTools.value` and [`QUBODrivers.ExactSampler.Optimizer`](@ref).
   - Verify that `get_counts(cbits = [Bit(0), ..., Bit(n - 1)])` preserves the
     exact logical variable order even when a synthetic qubit permutation pass
     is applied during compilation.
2. **Deterministic mocked Nexus job-lifecycle tests (no cloud credentials)**:
   - Inject a mock `qnexus` client to simulate:
     - normal compile $\to$ execute $\to$ poll $\to$ `get_counts` completion;
     - poll timeout after accepted job submission (`MOI.TIME_LIMIT`, job ID
       persisted to `"job_persistence_path"`, no duplicate submission);
     - interrupted persistence / polling error followed by resumption via
       `"nexus_resume_job_id"`, verifying that the existing accepted job is
       reused and `start_execute_job` is not called a second time;
     - timeout with `"cancel_on_timeout" = true` where `qnexus.jobs.cancel` is
       requested, distinguishing `"cancel_requested" == true` and
       `"cancelled" == false` (when the backend remains `RUNNING`) from
       confirmed `"cancelled" == true` (when the backend transitions to
       `CANCELLED`);
     - remote `FAILED` status clearing prior results and setting
       `MOI.TerminationStatus() == MOI.OTHER_ERROR`.
3. **Decomposition child integration test**:
   - Verify that `TKETOpt.QAOA.Optimizer` composes as the child factory of
     `QUBODecomposition.Optimizer` in `"local_tket"` mode using only the generic
     driver contract.
