function MOI.get(sampler::AbstractSampler{T}, nr::QUBOTools_MOI.NumberOfReads) where {T}
    i = nr.result_index
    ω = QUBOTools.solution(sampler)
    m = length(ω)

    if isempty(ω)
        error("Invalid result index '$i'; There are no solutions")
    elseif !(1 <= i <= m)
        error("Invalid result index '$i'; There are $(m) solutions")
    end

    return QUBOTools.reads(ω, i)
end
