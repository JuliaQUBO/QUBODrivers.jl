module MOI_PythonCall

import MathOptInterface as MOI
import PythonCall

if !hasmethod(MOI.Utilities.map_indices, Tuple{PythonCall.Py})
    MOI.Utilities.map_indices(::Function, obj::PythonCall.Py) = obj
end

end # module MOI_PythonCall
