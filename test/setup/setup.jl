function test_setup_macro()
    @testset "□ @setup macro" verbose = true begin
        test_project_version()
        test_project_compat()
        test_setup_spec_parser()
        test_random_seed_attribute_defaults()
        test_final_number_of_reads_fallbacks()
        test_capability_traits()
        test_post_sample_attribute_defaults()
        test_post_sample_callback_optimize_fallbacks()
    end

    return nothing
end

function test_project_version()
    @testset "→ Project Version" begin
        project = QUBODrivers.TOML.parsefile(joinpath(QUBODrivers.__project__(), "Project.toml"))
        version = VersionNumber(project["version"])

        @test QUBODrivers.__version__() == version
        @test MOI.get(ExactSampler.Optimizer(), MOI.SolverVersion()) == version
        @test MOI.get(RandomSampler.Optimizer(), MOI.SolverVersion()) == version
        @test MOI.get(IdentitySampler.Optimizer(), MOI.SolverVersion()) == version
    end

    return nothing
end

function test_project_compat()
    @testset "→ Project compat" begin
        project_dir = QUBODrivers.__project__()
        root_project = QUBODrivers.TOML.parsefile(joinpath(project_dir, "Project.toml"))
        test_project = QUBODrivers.TOML.parsefile(joinpath(project_dir, "test", "Project.toml"))
        docs_project = QUBODrivers.TOML.parsefile(joinpath(project_dir, "docs", "Project.toml"))
        version = VersionNumber(root_project["version"])
        root_compat = root_project["compat"]
        test_compat = test_project["compat"]
        docs_compat = docs_project["compat"]

        @test docs_compat["MathOptInterface"] == root_compat["MathOptInterface"]
        @test docs_compat["QUBOTools"] == root_compat["QUBOTools"]
        @test test_compat["PythonCall"] == root_compat["PythonCall"]
        @test docs_compat["QUBODrivers"] == "$(version.major).$(version.minor)"
        @test !haskey(root_project["deps"], "ToQUBO")
        @test !haskey(root_compat, "ToQUBO")
    end

    return nothing
end

function test_random_seed_attribute_defaults()
    @testset "→ RandomSeed attribute" begin
        sampler = RandomSampler.Optimizer()

        @test QUBODrivers.supports_seed(sampler)
        @test QUBODrivers.supports_seed(RandomSampler.Optimizer)
        @test isdefined(RandomSampler, :RandomSeed)
        @test MOI.supports(sampler, QUBODrivers.RandomSeed())
        @test MOI.supports(sampler, RandomSampler.RandomSeed())
        @test MOI.supports(sampler, MOI.RawOptimizerAttribute("seed"))
        @test MOI.get(sampler, QUBODrivers.RandomSeed()) === nothing
        @test MOI.get(sampler, RandomSampler.RandomSeed()) === nothing
        @test QUBODrivers.random_seed(sampler) === nothing

        MOI.set(sampler, RandomSampler.RandomSeed(), 13)
        @test MOI.get(sampler, RandomSampler.RandomSeed()) == 13
        @test MOI.get(sampler, QUBODrivers.RandomSeed()) == 13

        MOI.set(sampler, QUBODrivers.RandomSeed(), 11)
        @test MOI.get(sampler, QUBODrivers.RandomSeed()) == 11
        @test MOI.get(sampler, RandomSampler.RandomSeed()) == 11
        @test MOI.get(sampler, MOI.RawOptimizerAttribute("seed")) == 11
        @test QUBODrivers.random_seed(sampler) == 11

        MOI.set(sampler, MOI.RawOptimizerAttribute("seed"), nothing)
        @test MOI.get(sampler, QUBODrivers.RandomSeed()) === nothing
        @test MOI.get(sampler, RandomSampler.RandomSeed()) === nothing

        @test_throws ErrorException MOI.set(sampler, QUBODrivers.RandomSeed(), -1)
        @test_throws ErrorException MOI.set(sampler, RandomSampler.RandomSeed(), -1)
        @test_throws ErrorException MOI.set(sampler, MOI.RawOptimizerAttribute("seed"), -1)

        exact_sampler = ExactSampler.Optimizer()
        @test !QUBODrivers.supports_seed(exact_sampler)
        @test !MOI.supports(exact_sampler, QUBODrivers.RandomSeed())
        @test QUBODrivers.random_seed(exact_sampler) === nothing
    end

    return nothing
end

function test_post_sample_attribute_defaults()
    @testset "→ Post-sample callback attributes" begin
        sampler = RandomSampler.Optimizer()
        callback = (_, _) -> nothing

        @test MOI.supports(sampler, QUBODrivers.PostSampleCallback())
        @test MOI.supports(sampler, MOI.RawOptimizerAttribute("post_sample_callback"))
        @test MOI.supports(sampler, QUBODrivers.PostSampleTransform())
        @test MOI.supports(sampler, MOI.RawOptimizerAttribute("post_sample_transform"))
        @test MOI.get(sampler, QUBODrivers.PostSampleCallback()) === nothing
        @test MOI.get(sampler, MOI.RawOptimizerAttribute("post_sample_callback")) === nothing
        @test MOI.get(sampler, QUBODrivers.PostSampleTransform()) === false
        @test MOI.get(sampler, MOI.RawOptimizerAttribute("post_sample_transform")) === false
        @test QUBODrivers.post_sample_callback(sampler) === nothing
        @test QUBODrivers.post_sample_transform(sampler) === false

        MOI.set(sampler, QUBODrivers.PostSampleCallback(), callback)
        @test MOI.get(sampler, QUBODrivers.PostSampleCallback()) === callback

        MOI.set(sampler, MOI.RawOptimizerAttribute("post_sample_transform"), true)
        @test MOI.get(sampler, QUBODrivers.PostSampleTransform()) === true
        @test QUBODrivers.post_sample_transform(sampler) === true

        @test_throws ErrorException MOI.set(
            sampler,
            QUBODrivers.PostSampleTransform(),
            "true",
        )
    end

    return nothing
end

function test_capability_traits()
    @testset "→ Capability traits" begin
        @test QUBODrivers.supports_seed(RandomSampler.Optimizer)
        @test !QUBODrivers.supports_seed(ExactSampler.Optimizer)
        @test !QUBODrivers.supports_seed(IdentitySampler.Optimizer)
        @test !QUBODrivers.supports_seed(MIPSampler.Optimizer)

        @test QUBODrivers.honors_final_reads(RandomSampler.Optimizer)
        @test !QUBODrivers.honors_final_reads(ExactSampler.Optimizer)
        @test !QUBODrivers.honors_final_reads(IdentitySampler.Optimizer)
        @test !QUBODrivers.honors_final_reads(MIPSampler.Optimizer)

        @test !QUBODrivers.enforces_time_limit(RandomSampler.Optimizer)
        @test !QUBODrivers.enforces_time_limit(ExactSampler.Optimizer)
        @test !QUBODrivers.enforces_time_limit(IdentitySampler.Optimizer)
        @test !QUBODrivers.enforces_time_limit(MIPSampler.Optimizer)
    end

    return nothing
end

mutable struct NoRawAttributeSampler <: QUBODrivers.AbstractSampler{Float64}
    model::QUBOTools.Model{VI,Float64,Int}

    NoRawAttributeSampler() = new(QUBOTools.Model{VI,Float64,Int}())
end

mutable struct ThrowingRawAttributeSampler <: QUBODrivers.AbstractSampler{Float64}
    model::QUBOTools.Model{VI,Float64,Int}

    ThrowingRawAttributeSampler() = new(QUBOTools.Model{VI,Float64,Int}())
end

QUBOTools.backend(sampler::NoRawAttributeSampler) = sampler.model
QUBOTools.backend(sampler::ThrowingRawAttributeSampler) = sampler.model

function QUBODrivers.set_model!(
    sampler::Union{NoRawAttributeSampler,ThrowingRawAttributeSampler},
    model::QUBOTools.Model{VI,Float64,Int},
)
    sampler.model = model

    return model
end

function _custom_sampleset()
    metadata = QUBODrivers._sampler_metadata(
        origin                = "Custom Sampler",
        algorithm_name        = "Custom Sampler",
        execution_mode        = "test",
        optimizer_iterations  = 1,
        optimizer_evaluations = 1,
        number_of_reads       = 1,
        final_number_of_reads = 1,
        status                = "locally_solved",
    )
    metadata["time"] = Dict{String,Any}("effective" => 0.0)
    samples = [QUBOTools.Sample{Float64,Int}([0], 0.0)]

    return QUBOTools.SampleSet{Float64,Int}(samples, metadata; sense = :min, domain = :bool)
end

QUBODrivers.sample(::NoRawAttributeSampler) = _custom_sampleset()
QUBODrivers.sample(::ThrowingRawAttributeSampler) = _custom_sampleset()

function MOI.get(::ThrowingRawAttributeSampler, ::QUBODrivers._RawFinalNumberOfReads)
    error("raw final reads failure")
end

function MOI.get(::ThrowingRawAttributeSampler, ::QUBODrivers._RawPostSampleCallback)
    error("raw post-sample callback failure")
end

function test_final_number_of_reads_fallbacks()
    @testset "→ FinalNumberOfReads fallbacks" begin
        @test QUBODrivers.final_number_of_reads(NoRawAttributeSampler()) === nothing
        @test_throws ErrorException QUBODrivers.final_number_of_reads(
            ThrowingRawAttributeSampler(),
        )
    end

    return nothing
end

function test_post_sample_callback_optimize_fallbacks()
    @testset "→ PostSampleCallback optimize fallbacks" begin
        sampler = NoRawAttributeSampler()

        MOI.optimize!(sampler)

        metadata = QUBOTools.metadata(QUBOTools.solution(sampler))

        @test QUBODrivers.post_sample_callback(sampler) === nothing
        @test QUBODrivers.post_sample_transform(sampler) === false
        @test !haskey(metadata, "postprocess")

        throwing_sampler = ThrowingRawAttributeSampler()
        err = try
            MOI.optimize!(throwing_sampler)

            nothing
        catch err
            err
        end
        msg = sprint(showerror, err)

        @test err isa ErrorException
        @test occursin("raw post-sample callback failure", msg)
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
