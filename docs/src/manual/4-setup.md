# Sampler Setup

This guide explains the pieces needed to define a sampler interface with
QUBODrivers. The smallest useful wrapper has two parts:

- a [`QUBODrivers.@setup`](@ref) macro call that declares the optimizer type and
  attributes;
- a [`QUBODrivers.sample`](@ref) method that reads the internal model, calls the
  backend, and returns a `QUBOTools.SampleSet`.

## Imports

Import QUBODrivers, MathOptInterface, and QUBOTools. QUBOTools is available
through the `QUBODrivers` module and provides model conversion, objective
evaluation, sample containers, and metadata helpers.

```julia
import QUBODrivers
import QUBODrivers: QUBOTools
import MathOptInterface as MOI
```

## The [`QUBODrivers.@setup`](@ref) macro

```@docs
QUBODrivers.@setup
```

This macro usually takes two arguments: the identifier of the sampler's `struct`
(usually `Optimizer`) and a `begin ... end` block containing configuration
parameters as key-value pairs.

The first parameter of the configuration block is the sampler's name, which will be used to identify it in the `MOI.SolverName` attribute.

The next entry is the `version` assignment, which is accessed by the `MOI.SolverVersion` attribute.
In order to consistently support [semantic versioning](https://semver.org/) it is required that the version number comes as a *v-string* e.g. `v"major.minor.patch"`.

!!! note
    If missing, the `version` parameter matches the current version of `QUBODrivers.jl`.

A simple yet valid `@setup` call would look like this:

```julia
QUBODrivers.@setup Optimizer begin
    name    = "Super Sampler"
    version = v"1.0.2"
end
```

The generated optimizer has storage for the current QUBOTools model, raw
attributes, the original MOI variable order, and fixed-variable metadata. If a
sampler needs additional fields, define the optimizer type manually and
implement the same methods described in the [API Reference](@ref).

### Attributes

The `attributes` parameter is also a `begin ... end` block. Each entry declares
a default value and optional type for a sampler option. Attributes are accessed
with `MOI.get`, `MOI.set`, `MOI.RawOptimizerAttribute`, JuMP's
`set_optimizer_attribute`, or the generated typed attribute.

```julia
QUBODrivers.@setup Optimizer begin
    name    = "Super Sampler"
    version = v"1.0.2"
    attributes = begin
        NumberOfReads["num_reads"]::Integer = 1_000
        SuperAttribute::String = "super"
    end
end
```

In the example above, users can write either:

```julia
MOI.set(sampler, NumberOfReads(), 2_000)
MOI.set(sampler, MOI.RawOptimizerAttribute("num_reads"), 2_000)
```

Every generated optimizer also supports
`QUBODrivers.FinalNumberOfReads()` and the raw key `"final_num_reads"`.
`"num_reads"` controls reads used by a sampler's internal search or optimizer
evaluations. `"final_num_reads"` controls the reads used to build the returned
`SampleSet`. If `"final_num_reads"` is unset, call
`QUBODrivers.final_number_of_reads(sampler)` to get the effective value; it
defaults to `"num_reads"` when that attribute is supported.

## The [`QUBODrivers.sample`](@ref) method

```@docs
QUBODrivers.sample
```

### The `SampleSet` collection

The [`QUBODrivers.sample`](@ref) method must return a `QUBOTools.SampleSet{T}`.
A `SampleSet` collects `QUBOTools.Sample` entries together with metadata about the sampling run.

Build a `SampleSet` from a vector of samples and an optional metadata dictionary:

```julia
samples = QUBOTools.Sample{T,Int}[
    QUBOTools.Sample{T,Int}(ψ, λ)   # state vector ψ, objective value λ
    for (ψ, λ) in zip(states, values)
]

metadata = Dict{String,Any}(
    "time" => Dict{String,Any}("total" => elapsed),
)

return QUBOTools.SampleSet(samples, metadata; sense = :min, domain = :bool)
```

The `sense` keyword (`:min` or `:max`) and `domain` (`:bool` or `:spin`) tell QUBOTools how to interpret the samples.

The metadata dictionary is the place to record backend status, timing, and
diagnostics. QUBODrivers will add a total time and empty status string if they
are missing, but backend-specific wrappers should provide as much useful
metadata as their solver exposes.

QUBODrivers recommends these top-level metadata keys for driver attributes:

- `"algorithm"`: dictionary with at least `"name"`;
- `"backend"`: dictionary with backend `"name"` and `"version"` when known;
- `"execution"`: dictionary with `"mode"`;
- `"optimizer"`: dictionary with `"iterations"` and `"evaluations"` when known;
- `"reads"`: dictionary with `"number_of_reads"` and
  `"final_number_of_reads"`;
- `"seeds"`: dictionary of sampler, model, optimizer, or backend seeds;
- `"status"` and `"termination_status"`: raw and structured termination status.

## A complete example

```julia
module SuperSampler

import QUBODrivers
import QUBODrivers: QUBOTools
import MathOptInterface as MOI

@doc raw"""
    SuperSampler.Optimizer

This sampler is super!
"""
QUBODrivers.@setup Optimizer begin
    name    = "Super Sampler"
    version = v"1.0.2"
    attributes = begin
        NumberOfReads["num_reads"]::Integer = 1_000
        SuperAttribute::String = "super"
    end
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    # ~ Is your annealer running on the Ising Model? Have this:
    n, h, J, α, β = QUBOTools.ising(
        sampler,
        :dense; # Here we opt for a dense matrix representation
        sense = :max,
    )

    # ~ Retrieve Attributes using MathOptInterface ~ #
    num_reads  = MOI.get(sampler, NumberOfReads())
    final_reads = MOI.get(sampler, QUBODrivers.FinalNumberOfReads())
    super_attr = MOI.get(sampler, SuperAttribute())

    # ~ Do some sampling ~ #
    samples = QUBOTools.Sample{T,Int}[]

    clock = @timed for _ = 1:final_reads
        ψ = super_sample(n, h, J, super_attr)
        λ = QUBOTools.value(ψ, h, J, α, β)

        s = QUBOTools.Sample{T,Int}(ψ, λ)

        push!(samples, s)
    end

    # ~ Store some metadata ~ #
    metadata = Dict{String,Any}(
        "algorithm" => Dict{String,Any}("name" => "Super Sampler"),
        "backend"   => Dict{String,Any}("name" => "SuperBackend", "version" => nothing),
        "execution" => Dict{String,Any}("mode" => "sampling"),
        "optimizer" => Dict{String,Any}("iterations" => nothing, "evaluations" => num_reads),
        "reads"     => Dict{String,Any}(
            "number_of_reads"       => num_reads,
            "final_number_of_reads" => final_reads,
        ),
        "seeds"     => Dict{String,Any}(),
        "status"    => "locally_solved",
        "super_attr" => super_attr,
        "time"      => Dict{String,Any}("effective" => clock.time),
    )

    # ~ Return a SampleSet ~ #
    return QUBOTools.SampleSet(samples, metadata; sense=:max, domain=:spin)
end

function super_sample(n, h, J, super_attr)
    # ~ Do some super sampling (using C/C++) ~ #
    ψ = ccall(
        :super_sample,
        Vector{Int},
        (
            Cint,
            Ptr{Float64},
            Ptr{Ptr{Float64}},
            Cstring
        ),
        n,
        h,
        J,
        super_attr,
    )

    return ψ
end

end # module
```
