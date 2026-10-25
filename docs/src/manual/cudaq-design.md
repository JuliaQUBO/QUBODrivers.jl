# Optional CUDA-Q QAOA Sampler Design

This page records the contract and package-boundary design for an optional
CUDA-Q Quantum Approximate Optimization Algorithm (QAOA) sampler wrapper for the
JuliaQUBO ecosystem ([`JuliaQUBO/QUBODrivers.jl#88`](https://github.com/JuliaQUBO/QUBODrivers.jl/issues/88)).
It defines package ownership, the minimum [`QUBODrivers.AbstractSampler`](@ref)
surface, target and precision semantics, credential-free CPU conformance
testing, and the Python/CUDA-Q environment probe required before runtime
publication in a dedicated wrapper repository.

!!! note "Design Status and Package Boundary"
    `QUBODrivers.jl` hosts this interface specification and conformance checklist
    only; it does **not** depend on `PythonCall` at runtime for CUDA-Q, import
    `cudaq`, or bundle GPU/vendor SDKs in core `QUBODrivers.jl` or `QUBO.jl`.
    Once the standalone repository is bootstrapped and passes conformance, it
    will be added to the [External Sampler Packages](@ref) table in
    [`docs/src/manual/3-samplers.md`](3-samplers.md).

## Ownership and Package Placement

- **Proposed package and module**: A standalone optional wrapper package,
  `CUDAQOpt.jl` (hosted under `JuliaQUBO` or `SECQUOIA`), exposing
  `CUDAQOpt.QAOA.Optimizer{T} <: QUBODrivers.AbstractSampler{T}` generated via
  [`QUBODrivers.@setup`](@ref).
- **Zero vendor leakage into core packages**: `QUBODrivers.jl`, `QUBOTools.jl`,
  `ToQUBO.jl`, and `QUBODecomposition.jl` remain free of CUDA, `CUDA.jl`, or
  Python `cudaq` dependencies.
- **Decomposition compatibility**: `CUDAQOpt.QAOA.Optimizer` must compose as a
  child solver of `QUBODecomposition.Optimizer` through the standard
  zero-argument child factory `() -> ...` and public `MOI.copy_to` /
  [`QUBODrivers.sample`](@ref) interface, without CUDA-specific branches in the
  decomposition controller (see [Public composition pattern](@ref)).
- **Relationship to instructional notebooks**: Existing Python CUDA-Q QAOA
  material in `QUBONotebooks`
  ([`tests/test_cudaq_qaoa.py`](https://github.com/JuliaQUBO/QUBONotebooks/blob/ebbe663a390fccd2695e31f360f50df4c3d2e422/tests/test_cudaq_qaoa.py),
  tracked under `JuliaQUBO/QUBONotebooks#137`) remains instructional Python code
  and is not the Julia MOI driver.
- **Upstream reference attribution**: Where Hamiltonian assembly, parameter
  optimization, or bitstring decoding adapts patterns from
  [`alpha-unito/QSplit`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/nvidia/cudaq_qaoa.py)
  and
  [`qsplit/adapters/nvidia/util.py`](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/adapters/nvidia/util.py),
  the wrapper repository must preserve the
  [QSplit MIT license notice](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/LICENSE)
  and record the adapted revision (`4da64b072e702953038addd51cdf54f97f0f9516`).

## Minimum Sampler Surface and Attributes

The optimizer must be declared with [`QUBODrivers.@setup`](@ref) and expose
explicit MOI / raw optimizer attributes for circuit depth, target selection,
precision, shot budgets, classical optimization budget, and seeding:

| Attribute / Raw Key | Type & Default | Contract |
| :-- | :-- | :-- |
| `"p"` | `Integer = 1` | QAOA circuit depth ($p \ge 1$), parameterizing $2p$ variational angles $(\gamma_1, \dots, \gamma_p, \beta_1, \dots, \beta_p)$. |
| `"target"` | `String = "qpp-cpu"` | Explicit CUDA-Q simulation or hardware target (for example `"qpp-cpu"`, `"nvidia"`, `"tensornet"`). |
| `"target_option"` | `Union{String,Nothing} = nothing` | Explicit target option or floating-point precision selector (such as `"fp32"` or `"fp64"` when supported by the target). |
| `"allow_target_fallback"` | `Bool = false` | Whether the driver may fall back according to an explicit target list when the requested GPU target or precision is unavailable at target-initialization time. |
| `"num_reads"` | `Integer = 1_024` | Shot count (`shots_count`) per circuit evaluation during variational parameter optimization. |
| [`QUBODrivers.FinalNumberOfReads()`](@ref) / `"final_num_reads"` | `Union{Integer,Nothing} = nothing` | Shot count used to sample the final optimized QAOA circuit (`honors_final_reads(::Type{<:Optimizer}) = true`; defaults to `"num_reads"` when unset). |
| `"optimizer"` | `String = "COBYLA"` | Classical outer-loop optimizer name (`cudaq.optimizers` or `scipy.optimize.minimize`). |
| `"max_iterations"` | `Integer = 100` | Maximum classical optimizer iterations (`max_iterations >= 1`). |
| `"initial_point"` | `Union{Vector{Float64},Nothing} = nothing` | Optional length-$2p$ initial parameter vector; when `nothing`, initialized deterministically from `"seed"`. |
| [`QUBODrivers.RandomSeed()`](@ref) / `"seed"` | `Union{Integer,Nothing} = nothing` | Seed forwarded to `cudaq.set_random_seed(seed)` and initial-point / classical-optimizer RNG (`supports_seed(::Type{<:Optimizer}) = true`). |

## Model Lowering, Bit Ordering, and Objective Evaluation

1. **Variable ordering and isolated variables**:
   Retrieve the internal model in `QUBOTools.variables(sampler)` order (`1:n`)
   using `n, h, J, α, β = QUBOTools.ising(sampler, :dict; sense = :min)` (or
   `QUBOTools.qubo(sampler, :dict; sense = :min)` mapped via $x_i = (1 - z_i)/2$
   with $z_i \in \{+1, -1\}$). All $n$ free logical variables—including isolated
   variables with zero linear and quadratic coefficients—must be allocated a
   qubit index $q_{i-1}$ (`0:(n - 1)`), initialized in $|+\rangle = H|0\rangle$,
   acted on by the mixer unitary $U_B(\beta_l) = \prod_{i=0}^{n-1} R_X(2\beta_l, q_i)$,
   and measured.
2. **Cost Hamiltonian**:
   Build the spin Hamiltonian
   ```math
   H_C = \sum_{i=1}^{n} h_i Z_{i-1} + \sum_{1 \le i < j \le n} J_{ij} Z_{i-1} Z_{j-1}
   ```
   using `cudaq.SpinOperator` terms (`spin.z(i - 1)` and
   `spin.z(i - 1) * spin.z(j - 1)`). For $n = 0$ (all variables fixed or empty
   model), bypass CUDA-Q circuit execution and emit a single `Sample{T,Int}` with
   empty state `Int[]`, objective value $\alpha \beta$, and `final_num_reads`
   reads.
3. **Bitstring decoding and independent energy scoring**:
   CUDA-Q `cudaq.sample(kernel, ...; shots_count = final_num_reads)` returns a
   `SampleResult` mapping measured bitstrings $b \in \{0, 1\}^n$ in register
   declaration order (`q[0]` through `q[n - 1]`) to shot counts $c_b \ge 1$ with
   $\sum_b c_b = \text{final\_num\_reads}$.
   - Map each bit $b_k \in \{\text{'0'}, \text{'1'}\}$ to the sampler's working
     domain (`z_k = b_k == '0' ? 1 : -1` in `:spin` under $|0\rangle \mapsto +1,
     |1\rangle \mapsto -1$, or `x_k = b_k == '1' ? 1 : 0` in `:bool`).
   - Compute the sample objective value $\lambda = \text{QUBOTools.value}(\psi, h, J, \alpha, \beta)$
     directly with `QUBOTools.value` so that sense (`:min` / `:max`), scaling
     $\alpha$, constant offset $\beta$, and fixed-variable contributions are
     preserved identically to other JuliaQUBO drivers.
   - Construct `QUBOTools.Sample{T,Int}(ψ, λ, count)` so shot multiplicities are
     preserved as sample read counts.

## Target Isolation, Precision Policy, and Error Semantics

1. **Global target-state isolation**:
   In Python `cudaq`, `cudaq.set_target(...)` mutates process-global state. The
   Julia wrapper must guard target selection, seed assignment, parameter
   optimization, and final sampling with a module-level `ReentrantLock` (and
   explicitly set the configured target at the start of every
   `QUBODrivers.sample(sampler)` call) so sequential or multi-task solves in the
   same Julia process cannot leak target or precision state across optimizer
   instances.
2. **No silent precision or hardware downgrade**:
   Unlike QSplit's automatic `nvidia (fp64) -> nvidia (fp32) -> qpp-cpu` loop,
   `CUDAQOpt.QAOA.Optimizer` defaults to `"allow_target_fallback" = false`:
   - If the caller requests `"target" = "nvidia"` and `"target_option" = "fp64"`,
     any missing-target, unsupported-precision, or GPU out-of-memory failure
     must **not** silently switch to `"fp32"` or `"qpp-cpu"`.
   - Only when `"allow_target_fallback" = true` is explicitly set may target
     initialization fall back across a documented candidate sequence, recording
     both `"requested_target"`, `"selected_target"`, `"fallback_applied" = true`,
     and `"fallback_reason"` in `metadata["cudaq"]`.
   - Mid-solve execution failures (such as GPU out-of-memory during circuit
     simulation or invalid kernel parameters) must never trigger a silent retry
     on a different target.
3. **Actionable GPU memory and capacity failures**:
   Before and during execution, if `cudaq` raises an out-of-memory, device-capacity,
   or invalid-target error, the wrapper must clear any stale solution on the
   optimizer, set `MOI.TerminationStatus()` to `MOI.MEMORY_LIMIT` (for memory /
   qubit-capacity exhaustion) or `MOI.OTHER_ERROR`, and rethrow an exception
   whose message includes the requested `"target"`, `"target_option"`, logical
   variable count $n$, and underlying CUDA-Q error text.

## Metadata Contract

Every normal solve must pass [`QUBODrivers.validate_metadata`](@ref) with zero
violations and populate:

- `"origin"`: `"CUDAQOpt.QAOA @ cudaq"`
- `"algorithm"`: `Dict("name" => "QAOA", "p" => p, "optimizer" => optimizer_name)`
- `"backend"`: `Dict("name" => "cudaq", "version" => cudaq_version)`
- `"execution"`: `Dict("mode" => selected_target == "qpp-cpu" ? "local_cpu_simulator" : "cudaq_target")`
- `"optimizer"`: `Dict("iterations" => iterations_performed, "evaluations" => circuit_evaluations)`
- `"reads"`: `Dict("number_of_reads" => num_reads, "final_number_of_reads" => final_num_reads)`
- `"seeds"`: `Dict("sampler" => seed)` when seeded
- `"cudaq"`:
  ```julia
  Dict{String,Any}(
      "requested_target" => requested_target,
      "selected_target"  => selected_target,
      "target_option"    => target_option,
      "precision"        => resolved_precision,
      "fallback_applied" => fallback_applied,
      "fallback_reason"  => fallback_reason,
      "num_qubits"       => n,
  )
  ```

## Credential-Free CPU Test Route and Environment Probe

### Supported Python / CUDA-Q Environment Probe

Before running wrapper conformance tests or GPU smoke checks, verify the local
Python and `cudaq` installation with the following standalone probe (requiring
no quantum hardware credentials):

```julia
using PythonCall

function probe_cudaq_environment()
    sys = pyimport("sys")
    py_version = pyconvert(String, sys.version)
    cudaq = try
        pyimport("cudaq")
    catch err
        error(
            "Python package `cudaq` is not installed in the active PythonCall environment " *
            "(Python $py_version). Install `cudaq >= 0.8` on a supported platform " *
            "(Linux x86_64/aarch64 or macOS arm64 for CPU targets) before running CUDAQOpt.",
        )
    end

    cudaq_version = hasproperty(cudaq, :__version__) ?
        pyconvert(String, cudaq.__version__) : "unknown"
    has_qpp_cpu = pyconvert(Bool, cudaq.has_target("qpp-cpu"))
    has_nvidia  = pyconvert(Bool, cudaq.has_target("nvidia"))
    num_gpus    = hasproperty(cudaq, :num_available_gpus) ?
        pyconvert(Int, cudaq.num_available_gpus()) : 0

    return (
        python_version = py_version,
        cudaq_version  = cudaq_version,
        has_qpp_cpu    = has_qpp_cpu,
        has_nvidia     = has_nvidia,
        num_gpus       = num_gpus,
    )
end
```

### Conformance Test Plan for the Standalone Package

1. **Credential-free CPU conformance (`"qpp-cpu"`)**:
   - Run `QUBODrivers.test(CUDAQOpt.QAOA.Optimizer; examples = true, benchmark_conformance = true)`
     configured with `"target" => "qpp-cpu"`, `"p" => 1`, `"num_reads" => 64`,
     `"max_iterations" => 5`, and `"seed" => 42`.
   - Verify tiny 2- to 4-variable QUBO and Ising models with non-zero scale and
     offset, `MOI.MIN_SENSE` and `MOI.MAX_SENSE`, isolated variables, fixed
     variables, and non-monotonic `MOI.VariableIndex` insertion order against
     [`QUBODrivers.ExactSampler.Optimizer`](@ref).
2. **Target-isolation and fallback unit tests**:
   - Verify that two optimizer instances configured with different targets or
     options preserve their respective `"selected_target"` and `"precision"` in
     `metadata["cudaq"]`.
   - Verify that requesting a nonexistent target or unavailable GPU target with
     `"allow_target_fallback" = false` throws an actionable error and sets
     `MOI.TerminationStatus()` to `MOI.OTHER_ERROR` (or `MOI.MEMORY_LIMIT` on
     simulated capacity errors) without silently falling back to `"qpp-cpu"`.
3. **Decomposition child integration test**:
   - Verify that `CUDAQOpt.QAOA.Optimizer` works as the child factory of
     `QUBODecomposition.Optimizer` on a small multi-component and sweep model.
4. **Opt-in GPU smoke test**:
   - Gate `"target" => "nvidia"` tests behind `probe.has_nvidia && probe.num_gpus > 0`
     (and an explicit CI/local environment variable such as
     `JULIA_CUDAQ_TEST_GPU=true`) so standard CPU CI remains deterministic and
     credential-free.

