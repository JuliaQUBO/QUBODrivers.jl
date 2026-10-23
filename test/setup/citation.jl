const __CITATION_ROOT__ = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(__CITATION_ROOT__, "scripts", "release_check.jl"))
include(joinpath(__CITATION_ROOT__, "scripts", "verify_zenodo_release.jl"))

function _copy_citation_fixture(fn::Function; canonical::Bool = true)
    mktempdir() do dir
        for rel in (
            ("Project.toml",),
            ("CHANGELOG.md",),
            ("LICENSE",),
            ("CITATION.cff",),
            ("CITATION.bib",),
            ("README.md",),
            ("RELEASE.md",),
            ("docs", "Project.toml"),
            ("docs", "src", "index.md"),
            ("test", "Project.toml"),
            (".github", "workflows", "zenodo.yml"),
        )
            src = joinpath(__CITATION_ROOT__, rel...)
            dst = joinpath(dir, rel...)
            mkpath(dirname(dst))
            cp(src, dst)
        end
        if canonical
            _normalize_canonical_fixture!(dir)
        end
        fn(dir)
    end
end

function _normalize_canonical_fixture!(dir::AbstractString)
    canonical_version = "0.6.6"
    canonical_date = "2026-10-15"
    canonical_doi = "10.5281/zenodo.23420133"

    project_path = joinpath(dir, "Project.toml")
    project_text = replace(read(project_path, String), "\r\n" => "\n")
    write(
        project_path,
        replace(project_text, r"(?m)^version\s*=\s*\"[^\"]+\"$" => "version = \"$canonical_version\""),
    )

    docs_project_path = joinpath(dir, "docs", "Project.toml")
    docs_project_text = replace(read(docs_project_path, String), "\r\n" => "\n")
    write(
        docs_project_path,
        replace(
            docs_project_text,
            r"(?m)^QUBODrivers\s*=\s*\"[0-9]+\.[0-9]+(?:\.[0-9]+)?\"$" => "QUBODrivers = \"0.6\"",
        ),
    )

    cff_path = joinpath(dir, "CITATION.cff")
    cff_text = replace(read(cff_path, String), "\r\n" => "\n")
    live_id = ReleaseCheck.cff_version_identifier(cff_text)
    cff_text = replace(cff_text, r"(?m)^version:\s*\"[^\"]+\"$" => "version: \"$canonical_version\"")
    cff_text = replace(cff_text, r"(?m)^date-released:\s*.*$" => "date-released: $canonical_date")
    if live_id.doi !== nothing
        cff_text = replace(cff_text, live_id.doi => canonical_doi)
    end
    if live_id.version !== nothing
        cff_text = replace(
            cff_text,
            "Zenodo DOI for version $(live_id.version)" => "Zenodo DOI for version $canonical_version",
        )
    end
    write(cff_path, cff_text)

    for rel in (("CITATION.bib",), ("README.md",), ("docs", "src", "index.md"))
        path = joinpath(dir, rel...)
        text = replace(read(path, String), "\r\n" => "\n")
        if live_id.doi !== nothing
            text = replace(text, live_id.doi => canonical_doi)
        end
        if live_id.version !== nothing
            text = replace(text, "v$(live_id.version)" => "v$canonical_version")
        end
        write(path, text)
    end

    return nothing
end

function _mutate_file!(
    dir::AbstractString,
    rel::Tuple,
    target::AbstractString,
    replacement::AbstractString,
)
    path = joinpath(dir, rel...)
    content = replace(read(path, String), "\r\n" => "\n")
    occursin(target, content) || error("Target string not found in $(joinpath(rel...)): $target")
    write(path, replace(content, target => replacement; count = 1))
    return nothing
end

function _assert_repository_citation_consistent(root::AbstractString)
    result = ReleaseCheck.check_repository(root)
    @test isempty(result.failures)

    cff_text = ReleaseCheck.read_text(root, "CITATION.cff")
    live_id = ReleaseCheck.cff_version_identifier(cff_text)
    @test live_id.version !== nothing
    @test live_id.doi !== nothing
    @test result.concept_doi == ReleaseCheck.CONCEPT_DOI
    @test result.version_doi == live_id.doi

    archived_version = VersionNumber(live_id.version)
    @test archived_version <= result.version
    if archived_version == result.version
        @test isempty(result.warnings)
    else
        @test !isempty(result.warnings)
        @test all(
            w -> occursin("Exact-version citation metadata currently references v$(live_id.version)", w),
            result.warnings,
        )
    end

    workflow = ReleaseCheck.read_text(root, ".github", "workflows", "zenodo.yml")
    @test occursin(r"(?m)^\s*release:\s*$", workflow)
    @test occursin(r"(?m)^\s*-\s*published\s*$", workflow)
    @test occursin(r"(?m)^\s*workflow_run:\s*$", workflow)
    @test occursin(r"(?m)^\s*-\s*TagBot\s*$", workflow)
    @test occursin(r"(?m)^\s*-\s*completed\s*$", workflow)
    @test occursin(r"(?m)^\s*workflow_dispatch:\s*$", workflow)
    @test occursin("scripts/verify_zenodo_release.jl", workflow)

    return result
end

function _zenodo_record(; concept = "7811951", version = "v0.6.6", doi = "10.5281/zenodo.23420133")
    return Dict{String,Any}(
        "conceptrecid" => concept,
        "doi" => doi,
        "metadata" => Dict{String,Any}("version" => version),
    )
end

function test_citation()
    @testset "□ Citation & Release Verification" verbose = true begin
        @testset "→ Repository citation metadata is consistent" begin
            _assert_repository_citation_consistent(__CITATION_ROOT__)
        end

        @testset "→ Release preflight rejects citation drift mutations" begin
            _copy_citation_fixture() do dir
                _mutate_file!(dir, ("CITATION.cff",), "version: \"0.6.6\"", "version: \"0.6.5\"")
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("CITATION.cff version must match Project.toml", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(dir, ("CITATION.cff",), "license: MPL-2.0", "license: MIT")
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("CITATION.cff license must match the MPL-2.0 source LICENSE", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(dir, ("CITATION.cff",), "doi: \"10.5281/zenodo.7811951\"", "doi: \"10.5281/zenodo.9999999\"")
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("CITATION.cff must use the concept DOI", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(dir, ("CITATION.cff",), "date-released: 2026-10-15", "date-released: 2026-10-16")
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("CITATION.cff date-released must match", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(
                    dir,
                    ("CITATION.bib",),
                    "doi          = {10.1080/10556788.2026.2702926}",
                    "doi          = {10.1080/10556788.2026.0000000}",
                )
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("The CITATION.bib @article entry must set doi", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(
                    dir,
                    ("CITATION.bib",),
                    "doi          = {10.5281/zenodo.23420133}",
                    "doi          = {10.5281/zenodo.99999999}",
                )
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("The CITATION.bib @software entry must set doi", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(
                    dir,
                    ("CITATION.bib",),
                    "note         = {Evergreen concept DOI: 10.5281/zenodo.7811951}",
                    "note         = {Evergreen concept DOI: 10.5281/zenodo.9999999}",
                )
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("The CITATION.bib @software entry must name the evergreen concept DOI", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(
                    dir,
                    ("docs", "src", "index.md"),
                    "For a direct software citation",
                    "For a package software citation",
                )
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("README.md and docs/src/index.md citation sections must remain synchronized", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(
                    dir,
                    ("README.md",),
                    "10.5281/zenodo.23420133",
                    "10.5281/zenodo.13840948",
                )
                res = ReleaseCheck.check_repository(dir)
                @test any(f -> occursin("Historical version DOI 10.5281/zenodo.13840948 must not be used", f), res.failures)
            end

            _copy_citation_fixture() do dir
                _mutate_file!(dir, ("Project.toml",), "version = \"0.6.6\"", "version = \"0.6.7\"")
                _mutate_file!(
                    dir,
                    ("CHANGELOG.md",),
                    "# Changelog\n",
                    "# Changelog\n\n## v0.6.7 - 2026-10-23\n\n- Maintenance release.\n",
                )
                _mutate_file!(dir, ("CITATION.cff",), "version: \"0.6.6\"", "version: \"0.6.7\"")
                _mutate_file!(dir, ("CITATION.cff",), "date-released: 2026-10-15", "date-released: 2026-10-23")
                res = _assert_repository_citation_consistent(dir)
                @test any(w -> occursin("Exact-version citation metadata currently references v0.6.6", w), res.warnings)
            end
        end

        @testset "→ Zenodo release verification detects archive drift and parses JSON" begin
            parsed = ZenodoReleaseVerification.parse_json(
                """
                {
                  "conceptrecid": "7811951",
                  "doi": "10.5281/zenodo.23420133",
                  "flag": true,
                  "empty": null,
                  "tags": ["qubo", "ising\\nmodel", "\\u03bb", "\\ud83d\\ude80"],
                  "metadata": {
                    "version": "v0.6.6",
                    "count": 24,
                    "ratio": 1.5e-2
                  }
                }
                """,
            )
            @test parsed["conceptrecid"] == "7811951"
            @test parsed["flag"] === true
            @test parsed["empty"] === nothing
            @test parsed["tags"] == Any["qubo", "ising\nmodel", "λ", "🚀"]
            @test parsed["metadata"]["version"] == "v0.6.6"
            @test parsed["metadata"]["count"] == 24
            @test parsed["metadata"]["ratio"] ≈ 0.015

            current = ZenodoReleaseVerification.check_record(_zenodo_record(), "v0.6.6")
            stale = ZenodoReleaseVerification.check_record(
                _zenodo_record(; version = "v0.6.5"),
                "v0.6.6",
            )
            wrong_concept = ZenodoReleaseVerification.check_record(
                _zenodo_record(; concept = "9999999"),
                "v0.6.6",
            )
            missing_version = ZenodoReleaseVerification.check_record(
                Dict{String,Any}("conceptrecid" => "7811951", "metadata" => Dict{String,Any}()),
                "v0.6.6",
            )

            @test current.ok
            @test current.doi == "10.5281/zenodo.23420133"
            @test !stale.ok
            @test occursin("v0.6.5", stale.message)
            @test !wrong_concept.ok
            @test occursin("9999999", wrong_concept.message)
            @test !missing_version.ok
            @test occursin("metadata.version", missing_version.message)

            responses = Any[_zenodo_record(; version = "v0.6.5"), _zenodo_record()]
            recovered = ZenodoReleaseVerification.verify_release(
                "v0.6.6";
                attempts = 2,
                delay_seconds = 0,
                record_fetcher = _ -> popfirst!(responses),
            )
            @test recovered.ok
            @test isempty(responses)

            @test_throws ErrorException ZenodoReleaseVerification.verify_release(
                "v0.6.6";
                attempts = 1,
                delay_seconds = 0,
                record_fetcher = _ -> _zenodo_record(; version = "v0.6.5"),
            )

            transport_error = try
                ZenodoReleaseVerification.verify_release(
                    "v0.6.6";
                    attempts = 1,
                    delay_seconds = 0,
                    record_fetcher = _ -> error("network unavailable"),
                )
                nothing
            catch error
                sprint(showerror, error)
            end
            @test occursin("network unavailable", transport_error)
        end
    end

    return nothing
end
