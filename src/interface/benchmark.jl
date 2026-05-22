@doc raw"""
    benchmark(optimizer::Type{S}; objective_sense=MOI.MIN_SENSE) where {S<:AbstractSampler}
    benchmark(config!::Function, optimizer::Type{S}; objective_sense=MOI.MIN_SENSE) where {S<:AbstractSampler}
    benchmark(optimizer::Type{S}, source::MOI.ModelLike) where {S<:AbstractSampler}
    benchmark(config!::Function, optimizer::Type{S}, source::MOI.ModelLike) where {S<:AbstractSampler}

Run a QUBO benchmark problem with a sampler implementation.

When `source` is provided, benchmark the sampler on that MOI model. The
no-`source` methods use a small built-in QUBO instance as a smoke benchmark.

The optional `config!` function receives the raw sampler optimizer after the
source model is copied and before optimization. This is useful for setting
sampler attributes such as seeds, number of reads, time limits, or warm-starts.

The return value is a named tuple with solver metadata, benchmark problem size,
result count, objective values, objective-value summary statistics, the best
result, MOI solve time, measured wall time around `MOI.optimize!`, and solver
status fields.
"""
function benchmark end

function benchmark(::Type{S}; kwargs...) where {S<:AbstractSampler}
    return benchmark(identity, S; kwargs...)
end

function benchmark(config!::Function, ::Type{S}; kwargs...) where {S<:AbstractSampler}
    return benchmark(config!, S{Float64}; kwargs...)
end

function benchmark(::Type{S}, source::MOI.ModelLike) where {S<:AbstractSampler}
    return benchmark(identity, S, source)
end

function benchmark(config!::Function, ::Type{S}, source::MOI.ModelLike) where {S<:AbstractSampler}
    return benchmark(config!, S{Float64}, source)
end

function benchmark(
    config!::Function,
    ::Type{S};
    objective_sense = MOI.MIN_SENSE,
) where {T,S<:AbstractSampler{T}}
    _validate_benchmark_sense(objective_sense)

    return benchmark(config!, S, _default_benchmark_model(T, objective_sense))
end

function benchmark(
    config!::Function,
    ::Type{S},
    source::MOI.ModelLike,
) where {T,S<:AbstractSampler{T}}
    sampler = S()

    MOI.copy_to(sampler, source)

    variables = MOI.get(sampler, MOI.ListOfVariableIndices())
    objective_sense = MOI.get(sampler, MOI.ObjectiveSense())

    config!(sampler)

    solve = @timed MOI.optimize!(sampler)

    result_count = MOI.get(sampler, MOI.ResultCount())
    objective_values = Vector{T}(undef, result_count)

    for i = 1:result_count
        objective_values[i] = MOI.get(sampler, MOI.ObjectiveValue(i))
    end

    objective_summary = _benchmark_objective_summary(objective_values)
    best_index = _best_benchmark_index(objective_values, objective_sense)
    best_objective = isnothing(best_index) ? nothing : objective_values[best_index]
    best_state = if isnothing(best_index)
        nothing
    else
        MOI.get.(sampler, MOI.VariablePrimal(best_index), variables)
    end

    return (;
        solver             = MOI.get(sampler, MOI.SolverName()),
        version            = MOI.get(sampler, MOI.SolverVersion()),
        objective_sense,
        variables          = length(variables),
        result_count,
        objective_values,
        objective_summary,
        best_index,
        best_objective,
        best_state,
        solve_time         = MOI.get(sampler, MOI.SolveTimeSec()),
        wall_time          = solve.time,
        termination_status = MOI.get(sampler, MOI.TerminationStatus()),
        raw_status         = MOI.get(sampler, MOI.RawStatusString()),
    )
end

function _validate_benchmark_sense(objective_sense)
    if !(objective_sense == MOI.MIN_SENSE || objective_sense == MOI.MAX_SENSE)
        throw(ArgumentError("benchmark objective_sense must be MOI.MIN_SENSE or MOI.MAX_SENSE"))
    end

    return nothing
end

function _best_benchmark_index(objective_values::AbstractVector, objective_sense)
    isempty(objective_values) && return nothing

    return objective_sense == MOI.MAX_SENSE ? argmax(objective_values) : argmin(objective_values)
end

function _benchmark_objective_summary(objective_values::AbstractVector{T}) where {T}
    histogram = Dict{T,Int}()
    total = zero(T)

    for value in objective_values
        histogram[value] = get(histogram, value, 0) + 1
        total += value
    end

    if isempty(objective_values)
        return (; minimum = nothing, maximum = nothing, mean = nothing, histogram)
    end

    return (;
        minimum = minimum(objective_values),
        maximum = maximum(objective_values),
        mean    = total / length(objective_values),
        histogram,
    )
end

function _default_benchmark_model(::Type{T}, objective_sense) where {T}
    model = MOI.Utilities.Model{T}()
    Q = T[-1 2 2; 2 -1 2; 2 2 -1]
    n = size(Q, 1)
    x, _ = MOI.add_constrained_variables(model, fill(MOI.ZeroOne(), n))

    MOI.set(model, MOI.ObjectiveSense(), objective_sense)
    MOI.set(
        model,
        MOI.ObjectiveFunction{SQF{T}}(),
        SQF{T}(
            SQT{T}[SQT{T}(Q[i, j], x[i], x[j]) for i = 1:n for j = 1:n if i != j],
            SAT{T}[SAT{T}(Q[i, i], x[i]) for i = 1:n],
            zero(T),
        ),
    )

    return model
end
