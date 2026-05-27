# Changelog

## Unreleased

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
