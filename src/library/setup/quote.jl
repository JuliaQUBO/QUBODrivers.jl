function __setup_quote(spec::_SamplerSpec)
    Optimizer = esc(spec.id)

    return quote
        Base.@__doc__ mutable struct $(Optimizer){T} <: QUBODrivers.AbstractSampler{T}
            model::QUBOTools.Model{VI,T,Int}
            attributes::Dict{Symbol,Any}

            function $(Optimizer){T}() where {T}
                return new{T}(QUBOTools.Model{VI,T,Int}(), Dict{Symbol,Any}())
            end
        end

        # Default constructor
        $(Optimizer)() = $(Optimizer){Float64}()

        # Interface definition
        $(__setup_quote_interface(spec))
    end
end

function __setup_quote_interface(spec::_SamplerSpec)
    Optimizer        = esc(spec.id)
    OptimizerName    = esc(spec.name)
    OptimizerVersion = esc(spec.version)
    
    return quote
        # QUBOTools interface
        QUBOTools.backend(sampler::$(Optimizer)) = sampler.model

        function QUBODrivers.set_model!(
            sampler::$(Optimizer){T},
            model::QUBOTools.Model{VI,T,Int},
        ) where {T}
            sampler.model = model

            return model
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

        function QUBODrivers.get_raw_attr(
            sampler::$(Optimizer),
            attr::QUBODrivers.RawSamplerAttribute{key},
        ) where {key}
            if haskey(sampler.attributes, key)
                return sampler.attributes[key]
            else
                return QUBODrivers.default_raw_attr(sampler, attr)
            end
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

        function QUBODrivers.set_raw_attr!(
            sampler::$(Optimizer),
            ::QUBODrivers.RawSamplerAttribute{key},
            value,
        ) where {key}
            sampler.attributes[key] = value

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

        # Attributes - MOI
        $(__setup_quote_moi_attrs(spec))

        # Attributes - specific dispatch
        $((map(attr_spec -> __setup_quote_attribute(spec, attr_spec), spec.attributes))...)
    end
end

function __setup_quote_moi_attrs(spec::_SamplerSpec)
    Optimizer = esc(spec.id)

    return quote
        # MOI.Name - get
        function MOI.get(sampler::$(Optimizer), ::MOI.Name)
            return MOI.get(sampler, RawSamplerAttribute("moi/name"))
        end

        QUBODrivers.default_raw_attr(::$(Optimizer), ::raw_attr"moi/name") = ""

        # MOI.Name - set
        function MOI.set(sampler::$(Optimizer), ::MOI.Name, value)
            return MOI.set(sampler, RawSamplerAttribute("moi/name"), value)
        end

        function MOI.set(sampler::$(Optimizer), attr::raw_attr"moi/name", value)
            value isa AbstractString || error("Value for 'MOI.Name' must be a string")

            QUBODrivers.set_raw_attr!(sampler, attr, convert(String, value))

            return nothing
        end

        # MOI.Name - Support
        MOI.supports(::$(Optimizer), ::Union{MOI.Name, raw_attr"moi/name"}) = true

        # MOI.Silent - get
        function MOI.get(sampler::$(Optimizer), ::MOI.Silent)
            return MOI.get(sampler, RawSamplerAttribute("moi/silent"))
        end

        QUBODrivers.default_raw_attr(::$(Optimizer), ::raw_attr"moi/silent") = false

        # MOI.Silent - set
        function MOI.set(sampler::$(Optimizer), ::MOI.Silent, value)
            return MOI.set(sampler, RawSamplerAttribute("moi/silent"), value)
        end

        function MOI.set(sampler::$(Optimizer), attr::raw_attr"moi/silent", value)
            value isa Bool || error("Value for 'MOI.Silent' must be a boolean")

            QUBODrivers.set_raw_attr!(sampler, attr, value)

            return nothing
        end

        # MOI.Silent - Support
        MOI.supports(::$(Optimizer), ::Union{MOI.Silent, raw_attr"moi/silent"}) = true

        # MOI.TimeLimitSec - get
        function MOI.get(sampler::$(Optimizer), ::MOI.TimeLimitSec)
            return MOI.get(sampler, RawSamplerAttribute("moi/timelimitsec"))
        end

        QUBODrivers.default_raw_attr(::$(Optimizer), ::raw_attr"moi/timelimitsec") = nothing

        # MOI.TimeLimitSec - set
        function MOI.set(sampler::$(Optimizer), ::MOI.TimeLimitSec, value)
            return MOI.set(sampler, RawSamplerAttribute("moi/timelimitsec"), value)
        end

        function MOI.set(sampler::$(Optimizer), attr::raw_attr"moi/timelimitsec", value)
            if !(isnothing(value) || (value isa Real && value > zero(value)))
                error("Value for 'MOI.TimeLimitSec' must be a positive number, or 'nothing'")
            end

            QUBODrivers.set_raw_attr!(sampler, attr, convert(Union{Float64, Nothing}, value))

            return nothing
        end

        # MOI.NumberOfThreads - Support
        MOI.supports(::$(Optimizer), ::Union{MOI.NumberOfThreads, raw_attr"moi/NumberOfThreads"}) = true

        # MOI.NumberOfThreads - get
        function MOI.get(sampler::$(Optimizer), ::MOI.NumberOfThreads)
            return MOI.get(sampler, RawSamplerAttribute("moi/numberofthreads"))
        end

        QUBODrivers.default_raw_attr(::$(Optimizer), ::raw_attr"moi/numberofthreads") = 1

        # MOI.NumberOfThreads - set
        function MOI.set(sampler::$(Optimizer), ::MOI.NumberOfThreads, value)
            return MOI.set(sampler, RawSamplerAttribute("moi/numberofthreads"), value)
        end

        function MOI.set(sampler::$(Optimizer), attr::raw_attr"moi/numberofthreads", value)
            if !(value isa Real && isinteger(value) && value > zero(value))
                error("Value for 'MOI.NumberOfThreads' must be a positive integer")
            end

            QUBODrivers.set_raw_attr!(sampler, attr, convert(Union{Integer, Nothing}, value))

            return nothing
        end

        # MOI.NumberOfThreads - Support
        MOI.supports(::$(Optimizer), ::Union{MOI.NumberOfThreads, raw_attr"moi/numberofthreads"}) = true

        # MOI.VariablePrimalStart - get
        function MOI.get(sampler::$(Optimizer), ::MOI.VariablePrimalStart, vi::VI)
            i = QUBOTools.index(sampler, vi)

            return QUBOTools.start(sampler, i)
        end

        # MOI.VariablePrimalStart - set
        function MOI.set(sampler::$(Optimizer){T}, ::MOI.VariablePrimalStart, vi::VI, value) where {T}
            if !(isnothing(value) || value isa Real)
                error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")

                return nothing
            end

            if !isnothing(value)
                if !(value isa Real && isinteger(value))
                    error("Value for 'MOI.VariablePrimalStart' must be an integer, or 'nothing'")

                    return nothing
                end

                X = QUBOTools.domain(sampler)

                if X === QUBOTools.BoolDomain && !(value == zero(value) || value == one(value))
                    error("Integer value for 'MOI.VariablePrimalStart' must be either '0' or '1'")

                    return nothing
                elseif X === QUBOTools.SpinDomain && !(value == -one(value) || value == one(value))
                    error("Integer value for 'MOI.VariablePrimalStart' must be either '-1' or '1'")

                    return nothing
                end
            end

            QUBOTools.attach!(sampler, vi => convert(Union{Integer, Nothing}, value))

            return nothing
        end

        function MOI.set(sampler::$(Optimizer), attr::raw_attr"moi/variableprimalstart", value)
            if !(value isa Integer && value > zero(value))
                error("Value for 'MOI.VariablePrimalStart' must be a positive integer")
            end

            QUBODrivers.set_raw_attr!(sampler, attr, convert(Union{Integer, Nothing}, value))

            return nothing
        end

        # MOI.VariablePrimalStart - Support
        MOI.supports(::$(Optimizer), ::Union{MOI.VariablePrimalStart, raw_attr"moi/variableprimalstart"}) = true
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
        # Attributes - set
        function QUBODrivers.set_raw_attr!(sampler::$(Optimizer), ::$(attr_type), value)
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
