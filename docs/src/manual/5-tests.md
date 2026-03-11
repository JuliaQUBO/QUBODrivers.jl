# Test Suite

Besides establishing the connection between QUBO solvers and JuMP, this package also provides a test suite to ensure that the interface is implemented correctly.

`QUBODrivers.test` is the public entry point. Its methods are provided by the
`QUBODrivers_Test_Ext` package extension, which Julia loads automatically when
both `QUBODrivers` and `Test` are present in the active environment. This keeps
`Test` out of QUBODrivers' hard dependencies while still exposing a stable
testing API.

The extension module names themselves, such as `QUBODrivers_Test_Ext` and
`MOI_PythonCall_Ext`, are internal implementation details. Users should call the
public APIs they enable, like `QUBODrivers.test`, instead of importing those
extension modules directly.

```@docs
QUBODrivers.test
```
