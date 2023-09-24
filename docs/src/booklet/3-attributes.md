# Attributes

## API

```@docs
QUBODrivers.SamplerAttribute
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
