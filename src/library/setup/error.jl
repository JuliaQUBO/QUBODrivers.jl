struct DriverSetupError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::DriverSetupError)
    print(io, "Invalid usage of @setup: $(e.msg)")

    return nothing
end

function setup_error(msg::AbstractString)
    throw(DriverSetupError(msg))
end
