function test_setup_macro()
    @testset "□ @setup macro" verbose = true begin
        test_setup_spec_parser()
    end

    return nothing
end

macro setup_spec(raw_args...)
    args = map(a -> macroexpand(__module__, a), raw_args)
    spec = QUBODrivers.__setup_parse(args...)

    return :($(esc(spec)))
end

function test_setup_spec_parser()
    @testset "▶ Parser" begin
        @testset "→ Standard" begin
            spec = @setup_spec Optimizer begin
                name       = "Super" * " " * "Sampler"
                version    = VersionNumber("1.2.3")
                attributes = begin
                    SuperAttribute("super_attr")::Union{Integer,Nothing} = nothing
                    UltraAttribute["ultra_attr"]::Union{String,Nothing}  = ""
                    MegaAttribute                                        = (1, 2, 3)
                    "simple_attr"::Float64                               = 1.2
                    NormalAttribute("normal_attr")                       = []
                end
            end

            @test spec == QUBODrivers._SamplerSpec(;
                id         = :Optimizer,
                name       = :("Super" * " " * "Sampler"),
                version    = :(VersionNumber("1.2.3")),
                attributes = [
                    QUBODrivers._AttrSpec(; #
                        opt_attr = :SuperAttribute,
                        raw_attr = "super_attr",
                        val_type = :(Union{Integer,Nothing}),
                        default  = quote nothing end,
                    ),
                    QUBODrivers._AttrSpec(; #
                        opt_attr = :UltraAttribute,
                        raw_attr = "ultra_attr",
                        val_type = :(Union{String,Nothing}),
                        default  = "",
                    ),
                    QUBODrivers._AttrSpec(; #
                        opt_attr = :MegaAttribute,
                        default  = :((1, 2, 3))
                    ),
                    QUBODrivers._AttrSpec(; #
                        raw_attr = "simple_attr",
                        val_type = :(Float64),
                        default  = 1.2,
                    ),
                    QUBODrivers._AttrSpec(; #
                        opt_attr = :NormalAttribute,
                        raw_attr = "normal_attr",
                        val_type = :Any,
                        default  = quote [] end,
                    ),
                ],
            )
        end

        @testset "→ Misuse" begin
            # Empty macro call
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec()

            # Too many arguments
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, 1, 2, 3)

            # Invalid single argument
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(0)

            # Invalid arguments
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, 0)
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(0, begin end)

            # Invalid keys
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                key = "Optimizer"
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                ! = "Optimizer"
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                "Optimizer"
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                0 => "Optimizer"
            end)

            # Duplicate entries
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                name    = "Optimizer"
                version = VersionNumber("1.2.3")
                name    = "Optimizer"
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                version = v"1.2.3"
                name    = "Optimizer"
                version = VersionNumber("1.2.3")
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                attributes = begin end
                name       = "Optimizer"
                version    = v"1.2.3"
                attributes = begin end
            end)

            # Invalid attribute block
            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                attributes = 0
                name       = "Optimizer"
                version    = v"1.2.3"
            end)

            @test_macro_throws QUBODrivers.DriverSetupError @setup_spec(Optimizer, begin
                attributes = begin
                    ! = 3
                end
                name       = "Optimizer"
                version    = v"1.2.3"
            end)
        end
    end

    return nothing
end
