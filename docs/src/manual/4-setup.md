# Sampler Setup

This guide aims to provide a tutorial on how to implement new sampler interfaces using [QUBODrivers.jl](https://github.com/psrenergy/QUBODrivers.jl).
To get your QUBO sampler running right now, [QUBODrivers.jl](https://github.com/psrenergy/QUBODrivers.jl) will require only two main ingredients: a [`QUBODrivers.@setup`](@ref) macro call and a [`QUBODrivers.sample`](@ref) method implementation.

## Imports

First things first, we are going to import both [QUBODrivers.jl](https://github.com/psrenergy/QUBODrivers.jl) and also [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl), commonly aliased as `MOI`.
Although not strictly necessary, we recommend that you also import [QUBOTools.jl](https://github.com/psrenergy/QUBOTools.jl)for convenience, as it provides many useful functions for QUBO manipulation.
It is readly available in the `QUBODrivers` module.

```julia
import QUBODrivers
import QUBODrivers: QUBOTools
import MathOptInterface as MOI
```

## The [`QUBODrivers.@setup`](@ref) macro

```@docs
QUBODrivers.@setup
```

This macro takes two arguments: the identifier of the sampler's `struct` (usually `Optimizer`), and a `begin...end` block containing configuration parameters as *key-value* pairs.

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

We expect that most users will be happy with this approach and it is likely that it will fit most use cases.

### Attributes

The `attributes` parameter is also given by a `begin...end` block and contains the sampler's attributes.
These attributes are used to configure the sampler's behavior and are accessed by the `MOI.get` method.

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

## The [`QUBODrivers.sample`](@ref) method

```@docs
QUBODrivers.sample
```

### The [`QUBODrivers.SampleSet`] collection

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
    super_attr = MOI.get(sampler, SuperAttribute())

    # ~ Do some sampling ~ #
    samples = QUBOTools.Sample{T,Int}[]

    clock = @timed for _ = 1:num_reads
        ψ = super_sample(n, h, J, super_attr)
        λ = QUBOTools.value(ψ, h, J, α, β)

        s = QUBOTools.Sample{T,Int}(ψ, λ)

        push!(samples, s)
    end

    # ~ Store some metadata ~ #
    metadata = Dict{String,Any}(
        "num_reads"  => num_reads,
        "super_attr" => super_attr,
        "time"       => clock.time,
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
