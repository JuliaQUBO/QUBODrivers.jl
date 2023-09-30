function test_moi_pythoncall_ext()
    @testset "⚠ MathOptInterface-PythonCall ⚠" begin
        py_objs = [
            PythonCall.pylist([1, 2, 3]),
            PythonCall.pydict(Dict("a" => 1, "b" => 2, "c" => 3)),
            PythonCall.pytuple((1, 2, 3)),
            PythonCall.pyset(Set([1, 2, 3])),
            PythonCall.pyint(1),
            PythonCall.pyfloat(1.0),
            PythonCall.pycomplex(1.0 + 1.0im),
            PythonCall.pystr("1"),
            PythonCall.pybool(true),
        ]

        for py_obj in py_objs
            @test MOI.Utilities.map_indices(identity, py_obj) === py_obj
        end
    end

    return nothing
end
