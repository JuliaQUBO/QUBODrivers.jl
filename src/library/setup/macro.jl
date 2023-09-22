@doc raw"""
    @setup(expr)

The `@setup` macro receives a `begin ... end` block with an attribute definition on each of the block's statements.

## Sampler Attributes

All attributes must be presented as an assignment to the default value of that attribute.
To create a MathOptInterface optimizer attribute, an identifier must be present on the left hand side.
If a solver-specific, raw attribute is desired, its name must be given as a string, e.g. between double quotes.
In the special case where an attribute could be accessed in both ways, the identifier must be followed by the parenthesised raw attribute string. In any case, the attribute type can be specified typing the type assertion operator `::` followed by the type itself just before the equal sign.

For example, a list of the valid syntax variations for the *number of reads* attribute follows:
    - `"num_reads" = 1_000`
    - `"num_reads"::Integer = 1_000`
    - `NumberOfReads = 1_000`
    - `NumberOfReads::Integer = 1_000`
    - `NumberOfReads("num_reads") = 1_000`
    - `NumberOfReads("num_reads")::Integer = 1_000`

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

"""
macro setup(raw_args...)
    # Parse parameters
    args = map(a -> macroexpand(__module__, a), raw_args)
    spec = __setup_parse(args...)

    return __setup_quote(spec)
end
