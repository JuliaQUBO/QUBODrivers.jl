@doc raw"""
    QUBODrivers.@setup Optimizer begin
        name = "Solver Name"
        version = v"1.0.0"
        attributes = begin
            NumberOfReads["num_reads"]::Integer = 1_000
        end
    end

Declare a QUBODrivers sampler optimizer type.

The macro creates a mutable `Optimizer{T} <: QUBODrivers.AbstractSampler{T}`,
QUBOTools model storage, MOI optimizer metadata, raw attribute storage, and
`MOI.get`/`MOI.set`/`MOI.supports` methods for declared attributes.

The setup block accepts:

- `name`: required solver name returned by `MOI.SolverName`;
- `version`: optional `VersionNumber`, defaulting to the QUBODrivers package
  version;
- `attributes`: optional block of solver attributes.

Attributes are assignments to default values. They may be typed with `::T`,
exposed as typed MOI attributes, exposed as raw string attributes, or exposed as
both:

- `"num_reads" = 1_000`
- `"num_reads"::Integer = 1_000`
- `NumberOfReads = 1_000`
- `NumberOfReads::Integer = 1_000`
- `NumberOfReads["num_reads"] = 1_000`
- `NumberOfReads["num_reads"]::Integer = 1_000`

### Example

```
QUBODrivers.@setup Optimizer begin
    name       = "Super Sampler"
    version    = v"1.0.2"
    attributes = begin
        NumberOfReads["num_reads"]::Integer  = 1_000
        SuperAttribute["super_attr"]         = nothing
        MegaAttribute::Union{String,Nothing} = "mega"
    end
end
```

After setup, implement [`QUBODrivers.sample`](@ref) for the generated optimizer.
"""
macro setup(raw_args...)
    # Parse parameters
    args = map(a -> macroexpand(__module__, a), raw_args)
    spec = __setup_parse(args...)

    return __setup_quote(spec)
end
