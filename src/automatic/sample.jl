function _sample!(sampler::AutomaticSampler{T}) where {T}
    results = @timed sample(sampler)::SampleSet{T}
    _sample!(sampler, results.value, results.time)

    return nothing
end

function _sample!(sampler::AutomaticSampler{T}, sampleset::SampleSet{T}, total_time::Float64) where {T}
    metadata = QUBOTools.metadata(sampleset)::Dict{String,Any}

    if !haskey(metadata, "time")
        metadata["time"] = Dict{String,Any}("total" => total_time)
    elseif !haskey(metadata["time"], "total")
        metadata["time"]["total"] = total_time
    end

    if !haskey(metadata, "status")
        metadata["status"] = ""
    end

    sampleset = QUBOTools.cast(
        target_sense(sampler) => source_sense(sampler),
        QUBOTools.cast(
            target_domain(sampler) => source_domain(sampler),
            sampleset,
        )
    )

    copy!(QUBOTools.sampleset(sampler.model), sampleset)

    return nothing
end
