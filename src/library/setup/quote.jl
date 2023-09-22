function __setup_quote(spec::_SamplerSpec)
    Optimizer        = esc(spec.id)
    OptimizerName    = esc(spec.name)
    OptimizerVersion = esc(spec.version)

    return quote
        Base.@__doc__ mutable struct $(Optimizer){T} <: QUBODrivers.AbstractSampler{T}
            model::QUBOTools.Model{VI,T,Int}
            attributes::Dict{Symbol,Any}

            function $(Optimizer){T}() where {T}
                return new{T}(QUBOTools.Model{VI,T,Int}(), Dict{Symbol,Any}())
            end
        end

        # MOI interface
        MOI.get(::$(Optimizer), ::MOI.SolverName)    = $(OptimizerName)
        MOI.get(::$(Optimizer), ::MOI.SolverVersion) = $(OptimizerVersion)

        # Attributes - get
        function MOI.get(sampler::$(Optimizer), attr::MOI.RawOptimizerAttribute)
            return MOI.get(sampler, QUBODrivers.RawSamplerAttribute(attr.name))
        end

        function MOI.get(sampler::$(Optimizer), attr::QUBODrivers.RawSamplerAttribute)
            return QUBODrivers.get_raw_attr(sampler, attr)
        end

        # Attributes - set
        function MOI.set(sampler::$(Optimizer), attr::MOI.RawOptimizerAttribute, value::Any)
            return MOI.set(sampler, QUBODrivers.RawSamplerAttribute(attr.name), value)
        end

        function MOI.set(
            sampler::$(Optimizer),
            attr::QUBODrivers.RawSamplerAttribute,
            value::Any,
        )
            QUBODrivers.set_raw_attr!(sampler, attr, value)

            return nothing
        end

        # Attributes - support
        function MOI.supports(sampler::$(Optimizer), attr::MOI.RawOptimizerAttribute)::Bool
            return MOI.supports(
                sampler::$(Optimizer),
                QUBODrivers.RawSamplerAttribute(attr.name),
            )
        end

        function MOI.supports(sampler::$(Optimizer), attr::QUBODrivers.RawSamplerAttribute)
            return false
        end

        # Attributes - specific dispatch
        $((map(attr_spec -> __setup_quote_attribute(spec, attr_spec), spec.attributes))...)
    end
end

function __setup_quote_attribute(spec::_SamplerSpec, attr_spec::_AttrSpec)
    Optimizer = esc(spec.id)
    attr_name = Symbol(attr_spec.raw_attr)
    attr_key  = QuoteNode(attr_name)
    attr_type = RawSamplerAttribute{attr_name}
    attr      = attr_type()
    default   = esc(attr_spec.default)
    val_type  = esc(attr_spec.val_type)

    attr_code = quote
        # Attributes - get
        function QUBODrivers.get_raw_attr(sampler::$(Optimizer), ::$(attr_type))
            if haskey(sampler.attributes, $(attr_key))
                return sampler.attributes[$(attr_key)]
            else
                return QUBODrivers.default_raw_attr(sampler, $(attr))
            end
        end

        # Attributes - set
        function QUBODrivers.set_raw_attr!(
            sampler::$(Optimizer),
            ::$(attr_type),
            value,
        )
            sampler.attributes[$(attr_key)] = convert($(val_type), value)

            return nothing
        end

        # Attributes - default
        function QUBODrivers.default_raw_attr(sampler::$(Optimizer), ::$(attr_type))
            return $(default)::$(val_type)
        end

        # Attributes - support
        function MOI.supports(sampler::$(Optimizer), ::$(attr_type))
            return true
        end
    end

    if !isnothing(attr_spec.opt_attr)
        Attribute = esc(attr_spec.opt_attr)

        return quote
            $(attr_code)

            struct $(Attribute) <: QUBODrivers.SamplerAttribute end

            function MOI.get(sampler::$(Optimizer), ::$(Attribute))
                return MOI.get(sampler, $(attr))
            end

            function MOI.set(sampler::$(Optimizer), ::$(Attribute), value)
                MOI.set(sampler, $(attr), value)

                return nothing
            end

            function MOI.supports(sampler::$(Optimizer), ::$(Attribute))
                return true
            end
        end
    else
        return attr_code
    end
end
