using Documenter
using QUBODrivers
using QUBOTools

# Set up to run docstrings with jldoctest
DocMeta.setdocmeta!(QUBODrivers, :DocTestSetup, :(using QUBODrivers); recursive = true)
DocMeta.setdocmeta!(QUBOTools, :DocTestSetup, :(using QUBOTools); recursive = true)

makedocs(;
    modules = [QUBODrivers],
    doctest = true,
    clean = true,
    format = Documenter.HTML(
        assets = ["assets/extra_styles.css"], #, "assets/favicon.ico"],
        mathengine = Documenter.KaTeX(),
        sidebar_sitename = false,
    ),
    sitename = "QUBODrivers.jl",
    authors = "Pedro Xavier and Pedro Ripper and Tiago Andrade and Joaquim Garcia and David Bernal",
    pages = [
        "Home" => "index.md",
        # "Manual" => "manual.md",
        # "Examples" => "examples.md",
        # "Samplers" => "samplers.md",
    ],
    workdir = @__DIR__,
)

if "--skip-deploy" ∈ ARGS
    @warn "Skipping deployment"
else
    deploydocs(repo = raw"github.com/psrenergy/QUBODrivers.jl.git", push_preview = true)
end