#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))

function release_line_compat(version::VersionNumber)
    if version.major == 0
        return version.minor == 0 ? "0.0.$(version.patch)" : "0.$(version.minor)"
    end

    return string(version.major)
end

function check!(failures::Vector{String}, condition::Bool, message::String)
    condition || push!(failures, message)
    return nothing
end

function project_file(parts...)
    return joinpath(ROOT, parts...)
end

function read_toml(parts...)
    return TOML.parsefile(project_file(parts...))
end

compat_entries(value::AbstractString) = Set(strip.(split(value, ',')))

function release_heading_matches(line::AbstractString, version::VersionNumber)
    prefix = "## v$(version)"
    startswith(line, prefix) || return false
    length(line) == length(prefix) && return true
    return line[length(prefix) + 1] in (' ', '-', '(')
end

function release_section(changelog::String, version::VersionNumber)
    lines = split(changelog, '\n')
    start = findfirst(line -> release_heading_matches(line, version), lines)
    start === nothing && return nothing

    next_heading = findnext(line -> startswith(line, "## "), lines, start + 1)
    stop = next_heading === nothing ? lastindex(lines) : next_heading - 1
    return join(lines[start:stop], "\n")
end

function main()
    failures = String[]
    warnings = String[]

    project = read_toml("Project.toml")
    docs_project = read_toml("docs", "Project.toml")
    test_project = read_toml("test", "Project.toml")

    version = VersionNumber(project["version"])
    expected_self_compat = release_line_compat(version)

    check!(
        failures,
        project["name"] == "QUBODrivers",
        "Project.toml name is not QUBODrivers.",
    )

    root_deps = project["deps"]
    docs_deps = docs_project["deps"]
    root_compat = project["compat"]
    docs_compat = docs_project["compat"]
    test_compat = test_project["compat"]

    check!(
        failures,
        get(docs_deps, "QUBODrivers", nothing) == project["uuid"],
        "docs/Project.toml must depend on this package UUID for QUBODrivers.",
    )
    check!(
        failures,
        get(docs_compat, "QUBODrivers", nothing) == expected_self_compat,
        "docs/Project.toml compat for QUBODrivers must be \"$expected_self_compat\" for version $version.",
    )
    check!(
        failures,
        issubset(
            compat_entries(docs_compat["MathOptInterface"]),
            compat_entries(root_compat["MathOptInterface"]),
        ),
        "docs/Project.toml MathOptInterface compat must be supported by Project.toml.",
    )
    check!(
        failures,
        issubset(
            compat_entries(docs_compat["QUBOTools"]),
            compat_entries(root_compat["QUBOTools"]),
        ),
        "docs/Project.toml QUBOTools compat must be supported by Project.toml.",
    )
    check!(
        failures,
        issubset(
            compat_entries(test_compat["PythonCall"]),
            compat_entries(root_compat["PythonCall"]),
        ),
        "test/Project.toml PythonCall compat must be supported by Project.toml.",
    )
    check!(
        failures,
        !haskey(root_deps, "ToQUBO") && !haskey(root_compat, "ToQUBO"),
        "QUBODrivers should not depend on ToQUBO.",
    )
    check!(
        failures,
        haskey(root_compat, "julia"),
        "Project.toml must declare Julia compat.",
    )

    changelog = read(project_file("CHANGELOG.md"), String)
    section = release_section(changelog, version)
    check!(
        failures,
        section !== nothing,
        "CHANGELOG.md must contain a release heading for v$version.",
    )

    if section !== nothing &&
       version.major == 0 &&
       iszero(version.patch) &&
       !occursin(r"(?i)\b(breaking|changelog)\b", section)
        push!(
            warnings,
            "CHANGELOG.md section for v$version does not mention `breaking` or `changelog`; General AutoMerge may require one of those words if the registry labels the release BREAKING.",
        )
    end

    if isempty(failures)
        println("Release preflight passed for QUBODrivers v$version.")
        println("Expected docs self-compat: QUBODrivers = \"$expected_self_compat\".")
    else
        println(stderr, "Release preflight failed:")
        foreach(message -> println(stderr, "- ", message), failures)
    end

    if !isempty(warnings)
        println(stderr, "\nWarnings:")
        foreach(message -> println(stderr, "- ", message), warnings)
    end

    return isempty(failures) ? 0 : 1
end

exit(main())
