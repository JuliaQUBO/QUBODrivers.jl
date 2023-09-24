macro test_macro_throws(error, expr)
    return quote
        @test_throws $(esc(error)) eval(@macroexpand $(esc(expr)))
    end
end
