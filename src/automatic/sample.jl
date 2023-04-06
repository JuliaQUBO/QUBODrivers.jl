function _sample!(sampler::AutomaticSampler{T}) where {T}
    results   = @timed sample(sampler)::SampleSet{T}
    sampleset = results.value
    metadata  = QUBOTools.metadata(sampleset)::Dict{String,Any}

    if !haskey(metadata, "time")
        metadata["time"] = Dict{String,Any}("total" => results.time)
    elseif !haskey(metadata["time"], "total")
        metadata["time"]["total"] = results.time
    end

    sampleset = QUBOTools.cast(
        sampler.sense,                  # source
        QUBOTools.sense(sampler.model), # target
        
        sampler.domain,                  # source
        QUBOTools.domain(sampler.model), # target

        sampleset,
    )

    copy!(QUBOTools.sampleset(sampler.model), sampleset)

    return nothing
end