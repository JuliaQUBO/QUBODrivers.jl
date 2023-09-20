function test_setup_macro()
    test_setup_spec_parser()

    return nothing
end

macro setup_spec(raw_args...)
    args = map(a -> macroexpand(__module__, a), raw_args)
    spec = QUBODrivers.__setup_parse(args...)

    return :($(esc(spec)))
end

function test_setup_spec_parser()
    spec = @setup_spec Optimizer begin
        name       = "Super Sampler"
        version    = v"1.2.3"
        attributes = begin
            SuperAttribute("super_attr")::Union{Integer,Nothing} = nothing
            UltraAttribute["ultra_attr"]::Union{String,Nothing}  = ""
            MegaAttribute                                        = (1, 2, 3)
            "simple_attr"::Float64                               = 1.2
        end
    end

    @show spec

    return nothing
end
