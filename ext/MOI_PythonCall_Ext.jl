module MOI_PythonCall_Ext

import MathOptInterface as MOI
import PythonCall

if !hasmethod(MOI.Utilities.map_indices, Tuple{<:Function,PythonCall.Py})
    MOI.Utilities.map_indices(::Function, obj::PythonCall.Py) = obj
end

end # module MOI_PythonCall_Ext
