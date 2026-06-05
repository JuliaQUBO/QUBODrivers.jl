# Attributes

## API

```@docs
QUBODrivers.SamplerAttribute
QUBODrivers.FinalNumberOfReads
QUBODrivers.final_number_of_reads
```

```@docs
QUBODrivers.RawSamplerAttribute
QUBODrivers.@raw_attr_str
```

```@docs
QUBODrivers.get_raw_attr
QUBODrivers.set_raw_attr!
QUBODrivers.default_raw_attr
```

## Standard sampler attributes

Generated optimizers created with [`QUBODrivers.@setup`](@ref) support
`QUBODrivers.FinalNumberOfReads()` and the raw key `"final_num_reads"`.

Use `"num_reads"` for reads spent during a sampler's internal search,
optimization, or objective evaluations. Use `"final_num_reads"` for reads used
to build the returned `SampleSet`. If `"final_num_reads"` is unset, the
effective final read count defaults to `"num_reads"` when the sampler supports
that attribute.

Built-in samplers that do not have a separate final sampling phase document the
attribute as ignored and report their fixed returned read count in metadata.

## An advanced example

```julia
module SuperSampler

import QUBODrivers
import QUBODrivers: QUBOTools
import MathOptInterface as MOI

QUBODrivers.@setup Optimizer begin
    name    = "Super Sampler"
    version = v"1.0.2"
    attributes = begin
        NumberOfReads["num_reads"]::Integer  = 100_000
        SuperAttribute["super_attr"]::String = "super"
    end
end

function MOI.set(sampler::Optimizer, attr::raw_attr"", value)
    if !(value isa Integer)
        error("'num_reads' must be an integer")
    else
        QUBODrivers.set_raw_attr!(sampler, attr, value)
    end

    return nothing
end

function MOI.set(sampler::Optimizer, attr::raw_attr"super_attr", value)
    if !(value isa AbstractString)
        error("'super_attr' must be a string")
    elseif !(value ∈ ("super", "ultra", "mega"))
        error("'super_attr' must be one of the following: 'super', 'ultra', 'mega'")
    else
        QUBODrivers.set_raw_attr!(sampler, attr, value)
    end

    return nothing
end

end # SuperSampler module
```
