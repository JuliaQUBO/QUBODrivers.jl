function __setup_quote(spec::_SamplerSpec)
    Optimizer        = esc(spec.id)
    OptimizerName    = esc(spec.name)
    OptimizerVersion = esc(spec.version)

    return quote
        mutable struct $(Optimizer){T} <: QUBODrivers.AbstractSampler{T}
            model::QUBOTools.Model{VI,T,Int}
            attributes::Dict{Symbol,Any}

            function $(Optimizer){T}() where {T}
                return new{T}(
                    QUBOTools.Model{VI,T,Int}(),
                    Dict{Symbol,Any}(),
                )
            end
        end

        # MOI interface
        MOI.get(::$(Optimizer), ::MOI.SolverName)    = $(OptimizerName)
        MOI.get(::$(Optimizer), ::MOI.SolverVersion) = $(OptimizerVersion)

        # Attributes - get
        function MOI.get(sampler::$(Optimizer), attr::MOI.RawOptimizerAttribute)
            return MOI.get(sampler, RawSamplerAttribute(attr.value))
        end

        function MOI.get(sampler::$(Optimizer), attr::RawSamplerAttribute)
            return QUBODrivers.get_raw_attr(sampler, attr)
        end

        # Attributes - set
        function MOI.set(sampler::$(Optimizer), attr::MOI.RawOptimizerAttribute, value::Any)
            return MOI.set(sampler, RawSamplerAttribute(attr.value), value)
        end

        function MOI.set(sampler::$(Optimizer), attr::RawSamplerAttribute, value::Any)
            QUBODrivers.set_raw_attr!(sampler, attr, value)

            return nothing
        end

        # Attributes - support
        function MOI.supports(sampler::$(Optimizer), attr::RawOptimizerAttribute)::Bool
            return MOI.supports(sampler::$(Optimizer), RawSamplerAttribute(attr.value))
        end

        function MOI.supports(sampler::$(Optimizer), attr::RawSamplerAttribute)::Bool
            return false
        end

        # Attributes - specific dispatch
        $((map(attr_spec -> __setup_quote_attribute(spec, attr_spec), spec.attributes))...)
    end
end

function __setup_quote_attribute(spec::_SamplerSpec, attr_spec::_AttrSpec)
    Optimizer = esc(spec.id)
    attr_key  = Symbol(attr_spec.raw_attr)
    attr_type = RawSamplerAttribute{attr_key}
    attr      = attr_type()
    default   = esc(attr_spec.default)
    val_type  = esc(attr_spec.val_type)

    attr_code = quote
        # Attributes - get
        function QUBODrivers.get_raw_attr(sampler::$(Optimizer), ::attr_type)
            if haskey(sampler.attributes, $(attr_key))
                return sampler.attributes[$(attr_key)]
            else
                return QUBODrivers.default_raw_attr(sampler, $(attr))
            end
        end

        # Attributes - set
        function QUBODrivers.set_raw_attr!(sampler::$(Optimizer), ::attr_type, value) where {key}
            sampler.attributes[$(attr_key)] = convert($(val_type), value)
            
            return nothing
        end

        # Attributes - default
        function QUBODrivers.default_raw_attr(sampler::$(Optimizer), ::attr_type)
            return $(default)::$(val_type)
        end

        # Attributes - support
        function MOI.supports(sampler::$(Optimizer), ::attr_type)
            return true
        end
    end

    if !isnothing(attr_spec.opt_attr)
        Attribute = esc(attr_spec.opt_attr)

        return quote
            $(attr_code)

            struct $(Attribute) <: QUBODrivers.SamplerAttribute end

            function MOI.get(sampler::$(Optimizer), ::$(Attribute))
                return MOI.get(sampler, $(attr_type()))
            end

            function MOI.set(sampler::$(Optimizer), ::$(Attribute), value::val_type)
                MOI.set(sampler, $(attr_type()), value)

                return nothing
            end
        end
    else
        return attr_code
    end
end

    # if !isnothing(opt_attr) && !isnothing(raw_attr)
    #     return quote
    #         struct $(esc(opt_attr)) <: QUBODrivers.AbstractSamplerAttribute end

    #         push!(
    #             __ATTRIBUTES,
    #             QUBODrivers.AttributeWrapper{$(esc(opt_attr)),$(esc(val_type))}(
    #                 $(esc(default));
    #                 raw_attr = $(esc(raw_attr)),
    #                 opt_attr = $(esc(opt_attr))(),
    #             ),
    #         )
    #     end
    # elseif !isnothing(opt_attr)
    #     return quote
    #         struct $(esc(opt_attr)) <: QUBODrivers.AbstractSamplerAttribute end

    #         push!(
    #             __ATTRIBUTES,
    #             QUBODrivers.AttributeWrapper{$(esc(opt_attr)),$(esc(val_type))}(
    #                 $(esc(default));
    #                 opt_attr = $(esc(opt_attr))(),
    #             ),
    #         )
    #     end
    # elseif !isnothing(raw_attr)
    #     return quote
    #         push!(
    #             __ATTRIBUTES,
    #             QUBODrivers.AttributeWrapper{Nothing,$(esc(val_type))}(
    #                 $(esc(default));
    #                 raw_attr = $(esc(raw_attr)),
    #             ),
    #         )
    #     end
    # else
    #     error("Looks like some assertions were skipped. Did you turn any optimizations on?")
    # end    
