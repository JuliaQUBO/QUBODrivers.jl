function __setup_parse()
    return _SamplerSpec()
end

function __setup_parse(args...)
    setup_error("macro takes exactly one or two arguments")

    return nothing
end

function __setup_parse(expr)
    if expr isa Symbol
        return _SamplerSpec(; id = __setup_parse_id(expr))
    elseif (expr isa Expr && expr.head === :block)
        return __setup_parse_block(expr)
    else
        setup_error(
            "Single argument must be either an identifier or a `begin ... end` block",
        )

        return nothing
    end
end

function __setup_parse(id, block)
    if !(id isa Symbol) || !Base.isidentifier(id)
        setup_error("First argument must be a valid identifier")

        return nothing
    end

    if !(block isa Expr && block.head === :block)
        setup_error("Second argument must be a `begin ... end` block")
    end

    return __setup_parse_block(block; id)
end

function __setup_parse_block(block; id = :Optimizer)
    if !(block.head === :block)
        setup_error("Sampler configuration must be provided within a `begin ... end` block")
    end

    name       = nothing
    version    = nothing
    attributes = nothing

    for item in block.args
        if item isa LineNumberNode # skip
            continue
        elseif item isa Expr && item.head === :(=)
            key, value = item.args

            if key isa Symbol
                if key === :name
                    if !isnothing(name)
                        setup_error("Duplicate entries for 'name'")

                        return nothing
                    end

                    if !(value isa String)
                        setup_error("Sampler 'name' must be a string")

                        return nothing
                    end

                    name = value
                elseif key === :version
                    if !isnothing(version)
                        setup_error("Duplicate entries for 'version'")

                        return nothing
                    end

                    if !(value isa VersionNumber)
                        setup_error("Sampler 'version' must be a valid version number, not '$value'")

                        return nothing
                    end

                    version = value
                elseif key === :attributes
                    if !isnothing(attributes)
                        setup_error("Duplicate entries for 'attributes' block")

                        return nothing
                    end

                    if !(value isa Expr && value.head === :block)
                        setup_error(
                            "Sampler attributes must be placed inside a `begin ... end` block",
                        )

                        return nothing
                    end

                    attributes = _AttrSpec[]

                    for stmt in value.args
                        attr_spec = __setup_parse_attr(stmt)

                        if !isnothing(attr_spec)
                            push!(attributes, attr_spec)
                        end
                    end
                else
                    setup_error(
                        "Sampler configuration keys must be either 'name', 'version' or 'attributes', not '$key'",
                    )

                    return nothing
                end
            else
                setup_error("Sampler configuration keys must be a valid identifiers")

                return nothing
            end
        else
            setup_error("sampler configuration must be provided by `key = value` pairs")

            return nothing
        end
    end

    if isnothing(name)
        setup_error("'name' entry is missing")

        return nothing
    end

    if isnothing(version)
        version = QUBODrivers.__VERSION__
    end

    if isnothing(attributes)
        attributes = _AttrSpec[]
    end

    return _SamplerSpec(; id, name, version, attributes)
end

function __setup_parse_attr(stmt)
    opt_attr = nothing
    raw_attr = nothing
    val_type = :Any
    default  = nothing

    if stmt isa LineNumberNode
        return nothing
    elseif !(stmt isa Expr && stmt.head === :(=))
        setup_error(
            "Each attribute definition must be an assignment to a default value ($stmt)",
        )

        return nothing
    end

    attr, default = stmt.args

    if attr isa Symbol # ~ MOI attribute only
        if !(Base.isidentifier(attr))
            setup_error("Attribute identifier '$attr' is not valid")

            return nothing
        end

        opt_attr = attr
    elseif attr isa String # ~ Raw attribute only
        if isempty(attr)
            setup_error("Raw attribute key can't be an empty string")

            return nothing
        end

        raw_attr = attr
    elseif attr isa Expr && attr.head === :(::)
        attr, val_type = attr.args

        if attr isa Symbol
            if !(Base.isidentifier(attr))
                setup_error("Attribute identifier '$attr' is not a valid one")

                return nothing
            end

            opt_attr = attr
        elseif attr isa String
            raw_attr = attr
        elseif attr isa Expr && (attr.head === :ref || attr.head === :call)
            opt_attr, raw_attr = attr.args

            if opt_attr isa Symbol && raw_attr isa String
                if !(Base.isidentifier(opt_attr))
                    setup_error("Attribute identifier '$opt_attr' is not a valid one")

                    return nothing
                end
            else
                setup_error("Invalid attribute identifier '$name($raw)'")

                return nothing
            end
        else
            setup_error("Invalid attribute identifier '$attr'")

            return nothing
        end
    elseif attr isa Expr && (attr.head === :ref || attr.head === :call)
        opt_attr, raw_attr = attr.args

        if opt_attr isa Symbol && raw_attr isa String
            if !(Base.isidentifier(opt_attr))
                setup_error("Attribute identifier '$opt_attr' is not a valid one")

                return nothing
            end
        else
            setup_error("Invalid attribute identifier '$name[$raw_attr]'")

            return nothing
        end
    else
        setup_error("Invalid attribute signature '$attr'")

        return nothing
    end

    if !isnothing(raw_attr)
        if startswith(raw_attr, "□/")
            setup_error("Raw attributes starting with '□/' are reserved for internal use")
        elseif startswith(raw_attr, "moi/")
            setup_error("Raw attributes starting with 'moi/' are reserved for internal use")
        end
    end

    return _AttrSpec(; opt_attr, raw_attr, val_type, default)
end