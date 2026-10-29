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
        if haskey(time, "preprocess")
            _require_nonnegative_real_metadata!(
                violations,
                time,
                "metadata[\"time\"]",
                "preprocess",
            )
        end
    end

    if haskey(metadata, "preprocess")
        prep = _require_dict_metadata!(violations, metadata, "metadata", "preprocess")
        if !isnothing(prep)
            if haskey(prep, "enabled") && !(prep["enabled"] isa Bool)
                push!(violations, "metadata[\"preprocess\"][\"enabled\"] must be a boolean")
            elseif !haskey(prep, "enabled")
                push!(violations, "metadata[\"preprocess\"] must contain key \"enabled\"")
            end
            _require_string_metadata!(violations, prep, "metadata[\"preprocess\"]", "rules")
            _require_nonnegative_integer_metadata!(
                violations,
                prep,
                "metadata[\"preprocess\"]",
                "original_variables",
            )
            _require_nonnegative_integer_metadata!(
                violations,
                prep,
                "metadata[\"preprocess\"]",
                "reduced_variables",
            )
            _require_nonnegative_integer_metadata!(
                violations,
                prep,
                "metadata[\"preprocess\"]",
                "removed_variables",
            )
            _require_nonnegative_integer_metadata!(
                violations,
                prep,
                "metadata[\"preprocess\"]",
                "reduction_steps",
            )
            _require_nonnegative_real_metadata!(
                violations,
                prep,
                "metadata[\"preprocess\"]",
                "time",
            )
        end
    end

    if haskey(metadata, "auto_configure")
        auto_cfg = _require_dict_metadata!(violations, metadata, "metadata", "auto_configure")
        if !isnothing(auto_cfg)
            if haskey(auto_cfg, "enabled") && !(auto_cfg["enabled"] isa Bool)
                push!(violations, "metadata[\"auto_configure\"][\"enabled\"] must be a boolean")
            elseif !haskey(auto_cfg, "enabled")
                push!(violations, "metadata[\"auto_configure\"] must contain key \"enabled\"")
            end
            if haskey(auto_cfg, "supported") && !(auto_cfg["supported"] isa Bool)
                push!(violations, "metadata[\"auto_configure\"][\"supported\"] must be a boolean")
            elseif !haskey(auto_cfg, "supported")
                push!(violations, "metadata[\"auto_configure\"] must contain key \"supported\"")
            end
            _require_nonnegative_integer_metadata!(
                violations,
                auto_cfg,
                "metadata[\"auto_configure\"]",
                "num_variables",
            )
            params = _require_dict_metadata!(
                violations,
                auto_cfg,
                "metadata[\"auto_configure\"]",
                "parameters",
            )
            if !isnothing(params)
                _require_string_keys_metadata!(
                    violations,
                    params,
                    "metadata[\"auto_configure\"][\"parameters\"]",
                )
            end
        end
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
    rules = preprocess_rules(sampler)

    if rules === :none
        results = @timed sample(sampler)

        _sample!(sampler, results.value, results.time)

        return nothing
    end

    if _has_nonbinary_or_heterogeneous_domains(sampler) ||
       _has_higher_order_polynomial_objective(sampler)
        throw(
            ArgumentError(
                "QUBOPreprocessing only supports quadratic binary (`:bool`) or spin (`:spin`) models.",
            ),
        )
    end

    orig_model = QUBOTools.backend(sampler)::QUBOTools.Model{VI,T,Int}
    orig_scope_sig = get(
        QUBOTools.metadata(QUBOTools.solution(orig_model)),
        "__mip_solve_scope_signature__",
        nothing,
    )
    prep_results = @timed _preprocess_sampler_model(orig_model, rules)
    exported, reduced_model = prep_results.value
    preprocess_time = prep_results.time

    sample_ok = false
    sample_results = try
        set_model!(sampler, reduced_model)
        res = @timed sample(sampler)
        sample_ok = true
        res
    finally
        if !sample_ok
            reduced_sol = QUBOTools.solution(reduced_model)
            reduced_meta = QUBOTools.metadata(reduced_sol)
            if !isempty(reduced_meta)
                if !isnothing(orig_scope_sig) &&
                   haskey(reduced_meta, "__mip_solve_scope_signature__")
                    reduced_meta["__mip_solve_scope_signature__"] = orig_scope_sig
                end
                QUBOTools.attach!(orig_model, reduced_sol)
            end
        end
        set_model!(sampler, orig_model)
    end

    recon_results = @timed _reconstruct_preprocessed_sampleset(
        orig_model,
        reduced_model,
        exported,
        sample_results.value,
        rules,
        preprocess_time,
    )
    lifted_sampleset = recon_results.value
    total_time = preprocess_time + sample_results.time + recon_results.time

    _sample!(sampler, lifted_sampleset, total_time)

    return nothing
end

function _model_to_float64(
    model::QUBOTools.Model{VI,Float64,Int},
)::QUBOTools.Model{VI,Float64,Int}
    return model
end

function _model_to_float64(
    model::QUBOTools.Model{VI,T,Int},
)::QUBOTools.Model{VI,Float64,Int} where {T}
    V_set = Set{VI}(QUBOTools.variables(model))
    L_f64 = Dict{VI,Float64}(
        QUBOTools.variable(model, i) => Float64(v)
        for (i, v) in QUBOTools.linear_terms(model)
    )
    Q_f64 = Dict{Tuple{VI,VI},Float64}(
        (QUBOTools.variable(model, i), QUBOTools.variable(model, j)) => Float64(v)
        for ((i, j), v) in QUBOTools.quadratic_terms(model)
    )

    return QUBOTools.Model{VI,Float64,Int}(
        V_set,
        L_f64,
        Q_f64;
        scale  = Float64(QUBOTools.scale(model)),
        offset = Float64(QUBOTools.offset(model)),
        sense  = QUBOTools.sense(model),
        domain = QUBOTools.domain(model),
    )
end

const _QUBOPREPROCESSING_PKGID = Base.PkgId(
    Base.UUID("ce9b04da-6a94-4a97-978a-34bf3f916ed2"),
    "QUBOPreprocessing",
)

function _qubopreprocessing_module()
    return Base.require(_QUBOPREPROCESSING_PKGID)
end

function _run_preprocessing_workspace(
    qp::Module,
    f64_model::QUBOTools.Model{VI,Float64,Int},
    rules::Symbol;
    integerize_scale::Bool = true,
)
    if rules === :strong || rules === :weak
        allow_weak = rules === :weak
        ws = Base.invokelatest(
            qp.Workspace,
            f64_model;
            rules            = :mixed,
            integerize_scale = integerize_scale,
        )
        Base.invokelatest(
            qp.schedule_reductions!,
            ws;
            enable_dominance     = true,
            enable_elimination   = true,
            enable_relations     = true,
            enable_star_triangle = true,
            allow_weak_dominance = allow_weak,
            allow_weak_relations = allow_weak,
        )
        Base.invokelatest(qp.apply_roof_duality!, ws)
        Base.invokelatest(qp.apply_submodular_cut!, ws; allow_weak = allow_weak)
        Base.invokelatest(qp.apply_maxcut!, ws; allow_weak = allow_weak)
        Base.invokelatest(qp.probe_variables!, ws; order = :coercive)
        Base.invokelatest(
            qp.schedule_reductions!,
            ws;
            enable_dominance     = true,
            enable_elimination   = true,
            enable_relations     = true,
            enable_star_triangle = true,
            allow_weak_dominance = allow_weak,
            allow_weak_relations = allow_weak,
        )
        return ws
    else
        res = Base.invokelatest(
            qp.preprocess,
            f64_model;
            rules            = rules,
            integerize_scale = integerize_scale && (rules !== :identity),
        )
        return res isa Tuple ? first(res) : res
    end
end

function _can_convert_to_coeff_type(::Type{T}, val::Float64)::Bool where {T}
    if T <: Integer
        return isfinite(val) && isinteger(val) &&
               typemin(T) <= val <= typemax(T)
    else
        return isfinite(val)
    end
end

function _convert_to_coeff_type(::Type{T}, val::Float64)::T where {T}
    if T <: Integer
        return round(T, val)
    else
        return convert(T, val)
    end
end

function _reduced_model_fits_type(
    ::Type{T},
    reduced_f64::QUBOTools.Model{VI,Float64,Int},
)::Bool where {T}
    _can_convert_to_coeff_type(T, QUBOTools.scale(reduced_f64)) || return false
    _can_convert_to_coeff_type(T, QUBOTools.offset(reduced_f64)) || return false

    for (_, v) in QUBOTools.linear_terms(reduced_f64)
        _can_convert_to_coeff_type(T, v) || return false
    end
    for (_, v) in QUBOTools.quadratic_terms(reduced_f64)
        _can_convert_to_coeff_type(T, v) || return false
    end

    return true
end

function _convert_reduced_model(
    ::Type{T},
    orig_model::QUBOTools.Model{VI,T,Int},
    reduced_f64::QUBOTools.Model{VI,Float64,Int},
)::QUBOTools.Model{VI,T,Int} where {T}
    V_set = Set{VI}(QUBOTools.variables(reduced_f64))
    L_T = Dict{VI,T}(
        QUBOTools.variable(reduced_f64, i) => _convert_to_coeff_type(T, v)
        for (i, v) in QUBOTools.linear_terms(reduced_f64)
    )
    Q_T = Dict{Tuple{VI,VI},T}(
        (QUBOTools.variable(reduced_f64, i), QUBOTools.variable(reduced_f64, j)) =>
            _convert_to_coeff_type(T, v)
        for ((i, j), v) in QUBOTools.quadratic_terms(reduced_f64)
    )
    start = Dict{VI,Int}()
    for vi in V_set
        orig_idx = QUBOTools.index(orig_model, vi)
        s_val = QUBOTools.start(orig_model, orig_idx)
        if !isnothing(s_val)
            start[vi] = s_val
        end
    end

    return QUBOTools.Model{VI,T,Int}(
        V_set,
        L_T,
        Q_T;
        scale  = _convert_to_coeff_type(T, QUBOTools.scale(reduced_f64)),
        offset = _convert_to_coeff_type(T, QUBOTools.offset(reduced_f64)),
        sense  = QUBOTools.sense(reduced_f64),
        domain = QUBOTools.domain(reduced_f64),
        start  = start,
    )
end

function _preprocess_sampler_model(
    orig_model::QUBOTools.Model{VI,T,Int},
    rules::Symbol,
) where {T}
    qp = _qubopreprocessing_module()
    f64_model = _model_to_float64(orig_model)
    integerize = !(T <: Integer)
    ws = _run_preprocessing_workspace(qp, f64_model, rules; integerize_scale = integerize)

    exported = try
        Base.invokelatest(qp.materialize, ws)
    catch err
        err isa ArgumentError || rethrow()
        id_ws = Base.invokelatest(
            qp.Workspace,
            f64_model;
            rules            = :identity,
            integerize_scale = false,
        )
        Base.invokelatest(qp.materialize, id_ws)
    end

    reduced_f64 = Base.invokelatest(qp.export_model, exported)

    if !_reduced_model_fits_type(T, reduced_f64)
        id_ws = Base.invokelatest(
            qp.Workspace,
            f64_model;
            rules            = :identity,
            integerize_scale = false,
        )
        exported = Base.invokelatest(qp.materialize, id_ws)
        reduced_f64 = Base.invokelatest(qp.export_model, exported)
    end

    reduced_model = _convert_reduced_model(T, orig_model, reduced_f64)

    return exported, reduced_model
end

function _reconstruct_preprocessed_sampleset(
    orig_model::QUBOTools.Model{VI,T,Int},
    reduced_model::QUBOTools.Model{VI,T,Int},
    exported,
    raw_sampleset::SampleSet{T,Int},
    rules::Symbol,
    preprocess_time::Float64,
)::SampleSet{T,Int} where {T}
    qp = _qubopreprocessing_module()
    n_orig = QUBOTools.dimension(orig_model)
    n_reduced = QUBOTools.dimension(reduced_model)
    orig_sense = QUBOTools.sense(orig_model)
    orig_domain = QUBOTools.domain(orig_model)
    raw_domain = QUBOTools.domain(raw_sampleset)

    recon_t0 = time()
    lifted_samples = Vector{Sample{T,Int}}(undef, length(raw_sampleset))
    for (idx, sample) in enumerate(raw_sampleset)
        y_raw = QUBOTools.state(sample)
        y_domain =
            raw_domain === orig_domain ? y_raw :
            QUBOTools.cast(raw_domain => orig_domain, y_raw)
        rec = Base.invokelatest(qp.reconstruct, exported, y_domain)
        full_state = getfield(rec, :state)::Vector{Int}
        val_orig = QUBOTools.value(orig_model, full_state)
        lifted_samples[idx] = Sample{T,Int}(
            full_state,
            val_orig,
            QUBOTools.reads(sample),
        )
    end
    total_preprocess_time = preprocess_time + (time() - recon_t0)

    cert = getfield(exported, :certificate)
    chain_len = length(getfield(cert, :reduction_chain))
    metadata = deepcopy(QUBOTools.metadata(raw_sampleset))
    metadata["preprocess"] = Dict{String,Any}(
        "enabled"            => true,
        "rules"              => String(rules),
        "original_variables" => n_orig,
        "reduced_variables"  => n_reduced,
        "removed_variables"  => n_orig - n_reduced,
        "reduction_steps"    => chain_len,
        "time"               => total_preprocess_time,
    )

    time_meta = get(metadata, "time", nothing)
    if time_meta isa AbstractDict
        time_meta["preprocess"] = total_preprocess_time
        eff = get(time_meta, "effective", nothing)
        if eff isa Real
            time_meta["effective"] = Float64(eff) + total_preprocess_time
        end
    else
        metadata["time"] = Dict{String,Any}(
            "preprocess" => total_preprocess_time,
            "effective"  => total_preprocess_time,
        )
    end

    if n_reduced == 0 && !isempty(lifted_samples)
        opt_val = QUBOTools.value(first(lifted_samples))
        bound_meta = get(metadata, "bound", nothing)
        if bound_meta isa AbstractDict &&
           get(metadata, "termination_status", nothing) === MOI.OPTIMAL
            if isnothing(get(bound_meta, "value", nothing))
                bound_meta["value"] = opt_val
                bound_meta["raw_mip_min_bound"] =
                    orig_sense === QUBOTools.Min ? opt_val : -opt_val
                metadata["objective_bound"] = opt_val
            end
            if n_orig > 0 && isnothing(get(bound_meta, "relative_gap", nothing))
                bound_meta["relative_gap"] = zero(T)
                bound_meta["relative_gap_definition"] = "preprocessed_exact"
                metadata["relative_gap"] = zero(T)
            end
        end
    end

    return SampleSet{T,Int}(
        lifted_samples;
        metadata = metadata,
        sense    = orig_sense,
        domain   = orig_domain,
    )
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
    _record_auto_configure_metadata!(sampler, metadata)
    _warn_metadata_violations(sampleset)

    if _has_nonbinary_or_heterogeneous_domains(sampler) &&
       QUBOTools.domain(sampleset) !== QUBOTools.domain(sampler)
        throw(
            ArgumentError(
                "SampleSet returned for a model with non-binary or heterogeneous variable domains " *
                "must use `domain = :bool` (`QUBOTools.BoolDomain`) so integer sample states are preserved without spin casting, " *
                "got `$(QUBOTools.domain(sampleset))`.",
            ),
        )
    end

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

function _record_auto_configure_metadata!(
    sampler::AbstractSampler,
    metadata::Dict{String,Any},
)
    auto_configure(sampler) || return nothing

    if haskey(metadata, "auto_configure") && metadata["auto_configure"] isa AbstractDict
        auto_cfg = metadata["auto_configure"]
        get!(auto_cfg, "enabled", true)
        get!(auto_cfg, "supported", supports_auto_configure(sampler))
        get!(auto_cfg, "num_variables", QUBOTools.dimension(sampler))
        get!(auto_cfg, "parameters", Dict{String,Any}())
        return nothing
    end

    metadata["auto_configure"] = Dict{String,Any}(
        "enabled"       => true,
        "supported"     => supports_auto_configure(sampler),
        "num_variables" => QUBOTools.dimension(sampler),
        "parameters"    => Dict{String,Any}(),
    )

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
