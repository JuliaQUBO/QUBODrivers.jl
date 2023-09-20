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

    @test spec == QUBODrivers._SamplerSpec(;
        id      = :Optimizer,
        name    = "Super Sampler",
        version = v"1.2.3",
        attributes = [
            QUBODrivers._AttrSpec(;
                opt_attr = :SuperAttribute,
                raw_attr = "super_attr",
                val_type = :(Union{Integer,Nothing}),
                default  = quote nothing end,
            ),
            QUBODrivers._AttrSpec(;
                opt_attr = :UltraAttribute,
                raw_attr = "ultra_attr",
                val_type = :(Union{String,Nothing}),
                default  = "",
            ),
            QUBODrivers._AttrSpec(;
                opt_attr = :MegaAttribute,
                default  = :((1, 2, 3)),
            ),
            QUBODrivers._AttrSpec(;
                raw_attr = "simple_attr",
                val_type = :(Float64),
                default  = 1.2,
            ),
        ]
    )

    return nothing
end
