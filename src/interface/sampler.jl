@doc raw"""
    AbstractSampler{T} <: MOI.AbstractOptimizer

Abstract supertype for QUBODrivers sampler optimizers.

Concrete sampler optimizers are usually generated with [`QUBODrivers.@setup`](@ref).
They are MathOptInterface optimizers that accept QUBO or Ising models with
binary or spin variables and return one or more sampled states through standard
MOI result attributes.

The type parameter `T` is the numeric coefficient type used by the internal
`QUBOTools.Model`.
"""
abstract type AbstractSampler{T} <: MOI.AbstractOptimizer end

@doc raw"""
    sample(::AbstractSampler{T})::SampleSet{T} where {T}

Run the backend sampler and return a `QUBOTools.SampleSet`.

Sampler packages implement this method for their optimizer type. The method
should read the model from the sampler, read any MOI or raw optimizer
attributes it needs, call the backend, and return a `SampleSet{T}` whose
samples use the same sense and domain as the backend output.

`MOI.optimize!` calls this method and attaches the returned sample set to the
optimizer. If the returned metadata does not include a `"time"` dictionary with
a `"total"` entry, or does not include `"status"`, QUBODrivers fills those
fields with default values. It then validates the benchmarking metadata schema
and emits a warning, not an error, for missing or malformed fields.
"""
function sample end

function sample(::S) where {S<:AbstractSampler}
    error("`QUBODrivers.sample` is not implemented for '$S'")
end

function _sampler_metadata(;
    origin::String,
    algorithm_name::String,
    backend_name = "QUBODrivers.jl",
    backend_version = __version__(),
    execution_mode::String,
    optimizer_iterations = nothing,
    optimizer_evaluations = nothing,
    number_of_reads = nothing,
    final_number_of_reads = nothing,
    seeds::Dict{String,Any} = Dict{String,Any}(),
    status::String = "",
    termination_status = nothing,
)
    metadata = Dict{String,Any}(
        "origin"    => origin,
        "algorithm" => Dict{String,Any}(
            "name" => algorithm_name,
        ),
        "backend"   => Dict{String,Any}(
            "name"    => backend_name,
            "version" => backend_version,
        ),
        "execution" => Dict{String,Any}(
            "mode" => execution_mode,
        ),
        "optimizer" => Dict{String,Any}(
            "iterations"  => optimizer_iterations,
            "evaluations" => optimizer_evaluations,
        ),
        "reads"     => Dict{String,Any}(
            "number_of_reads"       => number_of_reads,
            "final_number_of_reads" => final_number_of_reads,
        ),
        "seeds"     => seeds,
        "status"    => status,
    )

    if !isnothing(termination_status)
        metadata["termination_status"] = termination_status
    end

    return metadata
end

@doc raw"""
    validate_metadata(sampleset::SampleSet)
    validate_metadata(metadata::AbstractDict)

Return a list of benchmarking metadata schema violations.

The validator is intentionally non-throwing so driver authors can use it while
migrating metadata. `MOI.optimize!` calls it after QUBODrivers stamps framework
metadata and emits a warning when the returned list is not empty.
"""
function validate_metadata(sampleset::SampleSet)
    return validate_metadata(QUBOTools.metadata(sampleset))
end

function validate_metadata(metadata::AbstractDict)
    violations = String[]

    _require_string_metadata!(violations, metadata, "metadata", "origin")
    _require_string_metadata!(violations, metadata, "metadata", "status")

    algorithm = _require_dict_metadata!(violations, metadata, "metadata", "algorithm")
    if !isnothing(algorithm)
        _require_string_metadata!(violations, algorithm, "metadata[\"algorithm\"]", "name")
    end

    backend = _require_dict_metadata!(violations, metadata, "metadata", "backend")
    if !isnothing(backend)
        _require_string_metadata!(violations, backend, "metadata[\"backend\"]", "name")
        _require_backend_version_metadata!(
            violations,
            backend,
            "metadata[\"backend\"]",
            "version",
        )
    end

    reads = _require_dict_metadata!(violations, metadata, "metadata", "reads")
    if !isnothing(reads)
        _require_nonnegative_integer_metadata!(
            violations,
            reads,
            "metadata[\"reads\"]",
            "number_of_reads",
        )
        _require_nonnegative_integer_metadata!(
            violations,
            reads,
            "metadata[\"reads\"]",
            "final_number_of_reads",
        )
    end

    seeds = _require_dict_metadata!(violations, metadata, "metadata", "seeds")
    if !isnothing(seeds)
        _require_string_keys_metadata!(violations, seeds, "metadata[\"seeds\"]")
    end

    time = _require_dict_metadata!(violations, metadata, "metadata", "time")
    if !isnothing(time)
        _require_nonnegative_real_metadata!(
            violations,
            time,
            "metadata[\"time\"]",
            "total",
        )
        _require_nonnegative_real_metadata!(
            violations,
            time,
            "metadata[\"time\"]",
            "effective",
        )
    end

    return violations
end

function _has_metadata_key!(violations::Vector{String}, metadata::AbstractDict, path, key)
    if haskey(metadata, key)
        return true
    else
        push!(violations, "$(path) must contain key \"$(key)\"")

        return false
    end
end

function _require_dict_metadata!(violations::Vector{String}, metadata::AbstractDict, path, key)
    _has_metadata_key!(violations, metadata, path, key) || return nothing

    value = metadata[key]

    if value isa AbstractDict
        return value
    else
        push!(violations, "$(path)[\"$(key)\"] must be a dictionary")

        return nothing
    end
end

function _require_string_metadata!(violations::Vector{String}, metadata::AbstractDict, path, key)
    _has_metadata_key!(violations, metadata, path, key) || return nothing

    value = metadata[key]
    value isa AbstractString || push!(violations, "$(path)[\"$(key)\"] must be a string")

    return nothing
end

function _require_backend_version_metadata!(
    violations::Vector{String},
    metadata::AbstractDict,
    path,
    key,
)
    _has_metadata_key!(violations, metadata, path, key) || return nothing

    value = metadata[key]
    if !(isnothing(value) || value isa VersionNumber || value isa AbstractString)
        push!(
            violations,
            "$(path)[\"$(key)\"] must be a VersionNumber, string, or nothing",
        )
    end

    return nothing
end

function _require_nonnegative_integer_metadata!(
    violations::Vector{String},
    metadata::AbstractDict,
    path,
    key,
)
    _has_metadata_key!(violations, metadata, path, key) || return nothing

    value = metadata[key]
    if !(value isa Integer && value >= zero(value))
        push!(violations, "$(path)[\"$(key)\"] must be a non-negative integer")
    end

    return nothing
end

function _require_nonnegative_real_metadata!(
    violations::Vector{String},
    metadata::AbstractDict,
    path,
    key,
)
    _has_metadata_key!(violations, metadata, path, key) || return nothing

    value = metadata[key]
    if !(value isa Real && value >= zero(value))
        push!(violations, "$(path)[\"$(key)\"] must be a non-negative real number")
    end

    return nothing
end

function _require_string_keys_metadata!(
    violations::Vector{String},
    metadata::AbstractDict,
    path,
)
    for key in keys(metadata)
        key isa AbstractString || push!(violations, "$(path) keys must be strings")
    end

    return nothing
end

@doc raw"""
    set_model!(sampler::AbstractSampler{T}, model::QUBOTools.Model{VI,T,Int}) where {T}

Store the QUBOTools model backing a sampler.

The [`@setup`](@ref) macro provides this method for generated optimizer types.
Custom sampler types that do not use `@setup` must provide it so that
`MOI.copy_to` can transfer JuMP/MOI models into the sampler before
optimization.
"""
function set_model! end

function _sample!(sampler::AbstractSampler{T}) where {T}
    results = @timed sample(sampler)

    _sample!(sampler, results.value, results.time)

    return nothing
end

function _sample!(sampler::AbstractSampler{T}, sampleset::SampleSet{T}, total_time::Float64) where {T}
    sampleset, post_sample_time = _apply_post_sample_callback(sampler, sampleset)
    total_time += post_sample_time

    metadata = QUBOTools.metadata(sampleset)::Dict{String,Any}

    if !haskey(metadata, "time")
        metadata["time"] = Dict{String,Any}("total" => total_time)
    elseif !haskey(metadata["time"], "total")
        metadata["time"]["total"] = total_time
    end

    if !haskey(metadata, "status")
        metadata["status"] = ""
    end

    _record_random_seed_metadata!(sampler, metadata)
    _warn_metadata_violations(sampleset)

    QUBOTools.attach!(sampler, sampleset)

    return nothing
end

function _record_random_seed_metadata!(
    sampler::AbstractSampler,
    metadata::Dict{String,Any},
)
    seed = random_seed(sampler)

    isnothing(seed) && return nothing

    seeds = get(metadata, "seeds", nothing)
    if seeds isa Dict{String,Any}
        metadata_seeds = seeds
    elseif seeds isa AbstractDict
        metadata_seeds = Dict{String,Any}(string(key) => value for (key, value) in seeds)
    else
        metadata_seeds = Dict{String,Any}()
    end

    metadata_seeds["sampler"] = seed
    metadata["seeds"] = metadata_seeds

    return nothing
end

function _warn_metadata_violations(sampleset::SampleSet)
    violations = validate_metadata(sampleset)

    isempty(violations) && return nothing

    @warn "SampleSet metadata does not conform to the QUBODrivers benchmarking schema" violations

    return nothing
end

function _apply_post_sample_callback(
    sampler::AbstractSampler{T},
    sampleset::SampleSet{T},
) where {T}
    callback = post_sample_callback(sampler)

    isnothing(callback) && return sampleset, 0.0

    transform = post_sample_transform(sampler)
    working_sampleset = _copy_sampleset(sampleset)
    results = @timed _call_post_sample_callback(callback, working_sampleset, sampler)
    processed_sampleset = _post_sample_result(results.value, working_sampleset)
    transformed = !_same_samples(sampleset, processed_sampleset)

    if transformed && !transform
        error(
            "PostSampleCallback changed sample states, values, reads, sense, or domain, " *
            "but PostSampleTransform is false",
        )
    end

    _record_post_sample_metadata!(
        processed_sampleset,
        callback;
        transform,
        transformed,
        time = results.time,
        raw_sampleset = transformed ? sampleset : nothing,
    )

    return processed_sampleset, results.time
end

struct _PostSampleCallbackError <: Exception
    error
    backtrace
end

function Base.showerror(io::IO, err::_PostSampleCallbackError)
    print(io, "PostSampleCallback failed: ")
    showerror(io, err.error, err.backtrace)

    return nothing
end

function _call_post_sample_callback(callback, sampleset, sampler)
    try
        return callback(sampleset, sampler)
    catch err
        throw(_PostSampleCallbackError(err, catch_backtrace()))
    end
end

function _post_sample_result(result, fallback::SampleSet{T,U}) where {T,U}
    if isnothing(result)
        return fallback
    elseif result isa SampleSet{T,U}
        return result
    elseif result isa SampleSet
        error(
            "PostSampleCallback returned '$(typeof(result))', expected " *
            "'SampleSet{$T,$U}'",
        )
    else
        error(
            "PostSampleCallback returned '$(typeof(result))', expected " *
            "'nothing' or 'SampleSet{$T,$U}'",
        )
    end
end

function _copy_sampleset(sampleset::SampleSet{T,U}) where {T,U}
    samples = [
        Sample{T,U}(
            copy(QUBOTools.state(sample)),
            QUBOTools.value(sample),
            QUBOTools.reads(sample),
        ) for sample in sampleset
    ]

    return SampleSet{T,U}(
        samples;
        metadata = deepcopy(QUBOTools.metadata(sampleset)),
        sense    = QUBOTools.sense(sampleset),
        domain   = QUBOTools.domain(sampleset),
    )
end

function _same_samples(left::SampleSet, right::SampleSet)
    QUBOTools.sense(left) === QUBOTools.sense(right) || return false
    QUBOTools.domain(left) === QUBOTools.domain(right) || return false
    length(left) == length(right) || return false

    for (left_sample, right_sample) in zip(left, right)
        QUBOTools.state(left_sample) == QUBOTools.state(right_sample) || return false
        QUBOTools.value(left_sample) == QUBOTools.value(right_sample) || return false
        QUBOTools.reads(left_sample) == QUBOTools.reads(right_sample) || return false
    end

    return true
end

function _record_post_sample_metadata!(
    sampleset::SampleSet,
    callback;
    transform::Bool,
    transformed::Bool,
    time::Float64,
    raw_sampleset::Union{SampleSet,Nothing},
)
    metadata = QUBOTools.metadata(sampleset)::Dict{String,Any}
    postprocess = _post_sample_metadata(metadata)

    postprocess["callback"] = Dict{String,Any}(
        "type"        => string(typeof(callback)),
        "transform"   => transform,
        "transformed" => transformed,
        "time"        => time,
    )

    if !isnothing(raw_sampleset)
        postprocess["raw_samples"] = _sampleset_record(raw_sampleset)
    end

    return nothing
end

function _post_sample_metadata(metadata::Dict{String,Any})
    current = get(metadata, "postprocess", nothing)

    postprocess = if current isa Dict{String,Any}
        current
    elseif current isa AbstractDict
        Dict{String,Any}(string(key) => value for (key, value) in current)
    elseif isnothing(current)
        Dict{String,Any}()
    else
        Dict{String,Any}("user" => current)
    end

    metadata["postprocess"] = postprocess

    return postprocess
end

function _sampleset_record(sampleset::SampleSet)
    return Dict{String,Any}(
        "format"         => "QUBODrivers.raw_samples",
        "schema_version" => 1,
        "sense"          => String(QUBOTools.sense(sampleset)),
        "domain"         => String(QUBOTools.domain(sampleset)),
        "samples"        => _sample_records(sampleset),
    )
end

function _sample_records(sampleset::SampleSet)
    return [
        Dict{String,Any}(
            "rank"  => i,
            "state" => copy(QUBOTools.state(sample)),
            "value" => QUBOTools.value(sample),
            "reads" => QUBOTools.reads(sample),
        ) for (i, sample) in enumerate(sampleset)
    ]
end
