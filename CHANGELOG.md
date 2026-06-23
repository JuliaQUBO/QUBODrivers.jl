# Changelog

## Unreleased

## v0.6.3 - 2026-06-22

### Added / Changed / Maintenance

- Allow QUBOTools 0.14 while retaining QUBOTools 0.10, 0.11, 0.12, and
  0.13 compatibility.

## v0.6.2 - 2026-06-22

### Added / Changed / Maintenance

- Document public external sampler packages with solver types and source paths,
  and add the registration workflow for future sampler documentation updates.
- Add issue and pull request templates for external sampler documentation
  changes.
- Harden TagBot permissions for issue-comment release automation.
- Add release process guardrails and a static release preflight check.

## v0.6.1 - 2026-06-11

### Added / Changed / Maintenance

- Add the benchmark metadata contract used by driver release-wave
  conformance: `QUBODrivers.RandomSeed`, `validate_metadata`,
  `total_time`, `effective_time`, and conservative capability traits.
- Update ExactSampler, IdentitySampler, MIPSampler, and RandomSampler to
  validate against the benchmark metadata schema.
- Add default-on benchmark conformance checks to `QUBODrivers.test`,
  including metadata, timing, seed determinism, read semantics, time-limit
  acceptance, and termination-status assertions.
- Document the metadata schema, seed/read/time-limit semantics, and the new
  test-suite conformance controls.

## v0.6.0 - 2026-06-08

### Breaking changes

- No intentional behavior-breaking changes are included. This is a pre-1.0
  minor release because final-read semantics, sampler metadata conventions, and
  post-sampling callback hooks are part of the public driver-interface API.

### Added / Changed / Maintenance

- Add `QUBODrivers.FinalNumberOfReads()` and the raw `"final_num_reads"`
  attribute so wrappers can distinguish backend search reads from the number of
  reads returned in the final `SampleSet`.
- Standardize sampler metadata conventions for algorithm, backend, execution,
  optimizer, read counts, seeds, raw status, and structured termination status.
- Add `QUBODrivers.PostSampleCallback()` and
  `QUBODrivers.PostSampleTransform()` for metadata-only post-processing and
  explicit sample transformations, including raw-sample preservation when a
  transform is emitted.
- Document the QUBODrivers/QUBOTools/ToQUBO boundary for objective
  bookkeeping, reformulation metadata, original-variable projection, and repair.
- Allow QUBOTools 0.13 while retaining QUBOTools 0.10, 0.11, and 0.12
  compatibility.

## v0.5.1 - 2026-06-03

- Add Dependabot dependency maintenance for Julia environments and GitHub
  Actions workflows.
- Skip documentation preview deployment for Dependabot pull requests so docs
  builds can still validate dependency updates without requiring write access
  to `gh-pages`.
- Add `TOML` compatibility bounds for the root package environment and build
  documentation against QUBODrivers 0.5.

## v0.5.0 - 2026-05-27

- Add `MIPSampler.Optimizer`, an MOI-native exact MIP-backed baseline sampler
  using a user-supplied MOI optimizer.
- Document MIP sampler usage and the binary-product linearization reference.
- Add GLPK-backed MIPSampler parity tests against `ExactSampler`.

## v0.4.0 - 2026-05-22

- Raise the minimum supported Julia version to 1.10.
- Add QUBOTools 0.12 compatibility and build the docs against QUBOTools 0.12.
- Test Julia 1.10 and latest stable Julia in CI.
- Add `QUBODrivers.benchmark` for sampler smoke benchmarks and user-provided
  MOI benchmark models, including read-weighted objective summaries.
