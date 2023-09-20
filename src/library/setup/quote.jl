function __setup_quote_sampler(spec::_SamplerSpec)
    return quote
        
    end
end

function __setup_quote_attr(spec::_AttrSpec)

    if !isnothing(opt_attr) && !isnothing(raw_attr)
        return quote
            struct $(esc(opt_attr)) <: QUBODrivers.AbstractSamplerAttribute end

            push!(
                __ATTRIBUTES,
                QUBODrivers.AttributeWrapper{$(esc(opt_attr)),$(esc(val_type))}(
                    $(esc(default));
                    raw_attr = $(esc(raw_attr)),
                    opt_attr = $(esc(opt_attr))(),
                ),
            )
        end
    elseif !isnothing(opt_attr)
        return quote
            struct $(esc(opt_attr)) <: QUBODrivers.AbstractSamplerAttribute end

            push!(
                __ATTRIBUTES,
                QUBODrivers.AttributeWrapper{$(esc(opt_attr)),$(esc(val_type))}(
                    $(esc(default));
                    opt_attr = $(esc(opt_attr))(),
                ),
            )
        end
    elseif !isnothing(raw_attr)
        return quote
            push!(
                __ATTRIBUTES,
                QUBODrivers.AttributeWrapper{Nothing,$(esc(val_type))}(
                    $(esc(default));
                    raw_attr = $(esc(raw_attr)),
                ),
            )
        end
    else
        error("Looks like some assertions were skipped. Did you turn any optimizations on?")
    end


    return quote
        
    end
end
