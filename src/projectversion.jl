const __PROJECT__ = Ref{Union{String,Nothing}}(nothing)

function __project__()
    if isnothing(__PROJECT__[])
        proj_path = abspath(dirname(@__DIR__))
    
        @assert isdir(proj_path)
    
        __PROJECT__[] = proj_path
    end

    return __PROJECT__[]::String
end

const __VERSION__ = Ref{Union{VersionNumber,Nothing}}(nothing)

function __version__()::VersionNumber
    if isnothing(__VERSION__[])
        proj_file_path = abspath(__project__(), "Project.toml")

        @assert isfile(proj_file_path)

        proj_file_data = TOML.parsefile(proj_file_path)

        __VERSION__[] = VersionNumber(proj_file_data["version"])
    end

    return __VERSION__[]::VersionNumber
end
