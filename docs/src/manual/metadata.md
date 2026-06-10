# Metadata Schema

Sampler metadata is the contract between a driver and benchmarking or
conformance tooling. Every `SampleSet` returned through `MOI.optimize!` should
carry the fields below. QUBODrivers validates this schema after it stamps
framework metadata and emits a warning, not an error, for violations.

Use `QUBODrivers.validate_metadata(sampleset)` to check a result directly. The
function returns a vector of human-readable violations; an empty vector means
the metadata satisfies the current schema.

## Required Fields

| Field | Type | Required | Stamped by | Meaning |
| --- | --- | --- | --- | --- |
| `metadata["origin"]` | `String` | yes | driver | Human-readable driver or backend origin. |
| `metadata["algorithm"]["name"]` | `String` | yes | driver | Algorithm or sampler name used for grouping benchmark rows. |
| `metadata["backend"]["name"]` | `String` | yes | driver | Backend package, service, or solver name. |
| `metadata["backend"]["version"]` | `VersionNumber`, `String`, or `nothing` | yes | driver | Backend version when known. Use `nothing` only when the backend cannot report one. |
| `metadata["status"]` | `String` | yes | driver or QUBODrivers fallback | Raw status string suitable for logs and reports. |
| `metadata["reads"]["number_of_reads"]` | non-negative `Integer` | yes | driver | Reads, evaluations, or backend samples actually consumed by the sampler. |
| `metadata["reads"]["final_number_of_reads"]` | non-negative `Integer` | yes | driver | Number of reads represented in the final emitted `SampleSet`. |
| `metadata["seeds"]` | dictionary with string keys | yes | driver and QUBODrivers seed recorder | Seed values used by the sampler, backend, model generator, or optimizer. Empty is valid for deterministic solvers. |
| `metadata["time"]["total"]` | non-negative `Real` | yes | QUBODrivers | Wall-clock seconds around `sample`, post-sample callbacks, and attachment preparation. |
| `metadata["time"]["effective"]` | non-negative `Real` | yes | driver | Backend solve or sampling seconds, excluding framework overhead when the backend exposes that split. |

Drivers may include additional metadata fields for backend diagnostics. Prefer
string keys and stable, machine-readable values.

## Timing

`metadata["time"]` has two standardized entries:

- `"total"` is QUBODrivers wall-clock time. It is always stamped by the
  framework when `MOI.optimize!` attaches a result.
- `"effective"` is backend solve or sampling time. The driver must stamp it.

Additional timing fields are optional. Use concise names such as `"build"`,
`"queue"`, or `"decode"` when their meaning is clear for the backend, or a
nested dictionary when a driver needs a namespaced breakdown.

`MOI.get(sampler, MOI.SolveTimeSec())` returns
`QUBODrivers.effective_time(sampler)`, not total wall-clock time. Use
`QUBODrivers.total_time(sampler)` or `QUBODrivers.total_time(sampleset)` when a
benchmark needs framework-inclusive wall time.

## Seeds

Generated optimizers opt into the standard seed contract by declaring raw
`"seed"` in their `@setup` attributes:

```julia
QUBODrivers.@setup Optimizer begin
    name = "Example Sampler"
    attributes = begin
        "seed"::Union{Integer,Nothing} = nothing
    end
end
```

Users can then call `MOI.set(sampler, QUBODrivers.RandomSeed(), 123)` or set
the raw optimizer attribute `"seed"`. When a non-`nothing` seed is configured,
QUBODrivers records it as `metadata["seeds"]["sampler"]` after sampling.

Use `QUBODrivers.supports_seed(sampler)` to decide whether a benchmark harness
can set `QUBODrivers.RandomSeed()` without driver-specific special cases.

## Capability Traits

QUBODrivers exposes conservative trait functions for benchmark harnesses:

- `QUBODrivers.supports_seed(sampler)` reports support for
  `QUBODrivers.RandomSeed()`.
- `QUBODrivers.honors_final_reads(sampler)` reports whether
  `QUBODrivers.FinalNumberOfReads()` controls the final emitted read count.
- `QUBODrivers.enforces_time_limit(sampler)` reports whether
  `MOI.TimeLimitSec()` is enforced by the sampler contract.

The default for each trait is `false`. Drivers should define a method returning
`true` only when the behavior is part of their public contract. Forwarding a
time limit to a backend is not the same as guaranteeing enforcement unless the
driver can rely on that backend behavior.

## Validation

```julia
violations = QUBODrivers.validate_metadata(sampleset)
isempty(violations) || @warn "metadata is not benchmark-ready" violations
```

`MOI.optimize!` runs the same validation after framework metadata is stamped.
Violations are warnings so existing drivers have a migration path, but
conformance tests can choose to fail on any non-empty violation list.

## API

```@docs
QUBODrivers.RandomSeed
QUBODrivers.random_seed
QUBODrivers.total_time
QUBODrivers.effective_time
QUBODrivers.validate_metadata
QUBODrivers.supports_seed
QUBODrivers.honors_final_reads
QUBODrivers.enforces_time_limit
```
