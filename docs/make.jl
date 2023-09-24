using Documenter
using QUBODrivers

# Set up to run docstrings with jldoctest
DocMeta.setdocmeta!(QUBODrivers, :DocTestSetup, :(using QUBODrivers); recursive = true)

makedocs(;
    modules  = [QUBODrivers, QUBODrivers.QUBOTools],
    doctest  = true,
    clean    = true,
    warnonly = [:missing_docs],
    format   = Documenter.HTML(
        assets = ["assets/extra_styles.css"], #, "assets/favicon.ico"],
        mathengine = Documenter.KaTeX(),
        sidebar_sitename = false,
    ),
    sitename = "QUBODrivers.jl",
    authors = "Pedro Xavier and Pedro Ripper and Tiago Andrade and Joaquim Garcia and David Bernal",
    pages = [
        "Home"   => "index.md",
        "Manual" => [
            "Introduction"  => "manual/1-intro.md",
            "Solving QUBO"  => "manual/2-solve.md",
            "Samplers"      => "manual/3-samplers.md",
            "Sampler Setup" => "manual/4-setup.md",
            "Test Suite"    => "manual/5-tests.md",
            "Benchmarking"  => "manual/6-benchmarks.md",
        ],
        "Booklet" => [
            "Itroduction"       => "booklet/1-intro.md",
            "Sampler Interface" => "booklet/2-interface.md",
            "Attribute System"  => "booklet/3-attributes.md",
        ],
    ],
    workdir = @__DIR__
)

if "--skip-deploy" ∈ ARGS
    @warn "Skipping deployment"
else
    deploydocs(; repo = raw"github.com/psrenergy/QUBODrivers.jl.git", push_preview = true)
end