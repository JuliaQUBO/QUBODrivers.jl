# Specifications to be extracted from macro call
struct _AttrSpec
    opt_attr::Union{Symbol,Nothing}
    raw_attr::String
    val_type::Any
    default::Any

    function _AttrSpec(;
        opt_attr::Union{Symbol,Nothing} = nothing,
        raw_attr::Union{String,Nothing} = nothing,
        val_type::Union{Symbol,Expr}    = :Any,
        default::Any,
    )
        @assert !isnothing(opt_attr) || !isnothing(raw_attr)

        if isnothing(raw_attr)
            raw_attr = "□/$(opt_attr)"
        else
            @assert !isempty(raw_attr)
        end

        Base.remove_linenums!(val_type)
        Base.remove_linenums!(default)

        return new(opt_attr, raw_attr, val_type, default)
    end
end

function Base.:(==)(x::_AttrSpec, y::_AttrSpec)
    return x.opt_attr === y.opt_attr &&
           x.raw_attr == y.raw_attr &&
           x.val_type == y.val_type &&
           x.default == y.default
end

struct _SamplerSpec
    id::Symbol
    name::Any
    version::Any
    attributes::Vector{_AttrSpec}

    function _SamplerSpec(;
        id::Symbol                    = :Optimizer,
        name::Any                     = "",
        version::Any                  = QUBODrivers.__version__(),
        attributes::Vector{_AttrSpec} = _AttrSpec[],
    )
        @assert Base.isidentifier(id)

        return new(id, name, version, attributes)
    end
end

function Base.:(==)(x::_SamplerSpec, y::_SamplerSpec)
    return x.id === y.id &&
           x.name == y.name &&
           x.version == y.version &&
           x.attributes == y.attributes
end