# Compile-time execution

# Summary 

This RFC proposes to entirely change the current implementation of compile-time that will allow to run V language itself at comptime.

# Motivation

 The main purpose to do so is current limitation of compile-time evaluation:
- No way to invoke arbitrary V functions
- No way to choose function at compile time: 
```v
$if flag_a {
    fn foo() {
        println('bar')
    }
} $else {
    fn foo() {
        println('foo')
    }
}
```
^ Compiler cannot handle this code 

- It limits our generics and compile-time reflection. With proper comptime it would be possible to generate complex serialization/deserialization functions without compiler support. 
- Implementing proper comptime in fact would simplify our compiler pipelines, at the moment there is a lot of edge-cases for handling current limited comptime. 
- Proper metaprogramming is must have in every modern language 


# Guide-level explanation 

With this RFC the main change is that all expressions and statements prefixed with `comptime` will be treated as compile-time and all of them can be executed *before* codegen. Current compile-time is quite limited and allows only a few statements (`$if`,`$for`) and only specific calls.

You can compare new way of handling comtime to Zig comptime functionality. It would allow us not only to perform some computations at compile-time but also generate new structures and functions at compile-time. All generic types would not be just some compiler magic but `v.ast.Type` and you should be able to invoke all of its methods at compile-time, get type symbol from it and even create new `v.ast.Type`s at compile-time.  

First where comptime can be used is automatic generation of serialization/deserialization functions. Here's small example of how we can implement automatic `str()` for types: 
```v
fn to_str<T>(val T) string {
    // Type of `T` in compile-time context is `v.ast.TypeSymbol`
    comptime if T.kind == .int {
        return int_string(val)
    } else if T.kind == .array {
        mut out := '['
        for i,elem in val {
            out = '${out}${elem}'
            if i != val.len - 1 {
                out = '${out},'
            }
        }
        return '${out}]'
    } else if T.kind == .struct_ {
        out = '${$T.name} {'
        comptime for field in T.fields {
            field := val.$field 
            out = '${out} ${$field}: ${field}'
        }
        return '${out}}'
    } else {
        // and so on...
    }
}
```


And here is simple example of factorial that is executed fully at compile-time! 
```v
fn factorial(x int) int {
    if x < 2 {
        return x 
    } 

    return factorial(x - 1) * x
}

fn main() {
    cx := comptime factorial(5) // in this case variable `cx` exists in generated code and only result of evaluating factorial is stored in it
    comptime cy := factorial(6) // and in this case variable `cy` exists only at compile-time, every time you try to use it from non
                                // comptime context its value is simply inserted into AST tree: `ast.Comptime(ast.Ident('cy'))` becomes `ast.Int(720)`
    println(cx) // 120 
    println($cy) // 720
}
```

# Reference-level explanation 

To add parser support for CTE we can just add `comtpime` keyword support and everything that comes after it is treated as `ast.ComptimeExpr(ast.Expr)` or `ast.ComptimeStmt(ast.Stmt)`. 

In order to implement proper evaluation mechanism we want to have `mx1` and `mx`-like evaluation in our compiler pipeline. In our case it might look like this:
```
eval1(code):
    check(code) // type check code
    return interp(code) // evaluate all comptime nodes in `code`

eval(code):
    output = eval1(code) 
    expanded = 0 
    // if output has comptime expressions or statements evaluate it once again
    while output.has_cte() && expanded < cte_limit:
        output = eval1(output)
    if expanded == cte_limit:
        error('CTE limit reached')
    return output
```

As we can see we also can limit CTE expansion so it is impossible to create infinite loop at compile-time (unless user manually overwrites CTE limit through compiler flags). 

## How would `eval1` work? 

It should simply use `v.eval` functionality to evaluate all `comptime` AST nodes, result of evaluation should replace these comptime nodes:
```v

fn bar(a int,b int) int {
    return a + b
}

fn foo() {
    // before eval1
    x := comptime bar(40,2) // or ast.Var('x', ast.Comptime(ast.Call('bar', 40,2)))
    // after eval1
    x := 42 // or `ast.Var('x',ast.Int(42))`
}

```

# Drawbacks 
This would break a lot of code that depends on current implementation of compile-time and it would take quite a lot of time to switch to new comptime and implement it. 

# Rationale and alternatives 

This design allows to execute entire V language at comptime and it makes it possible to:
- Implement serializers/deserializers
- Write code that would produce new code a-la Lisp macros 
- Write code that would generate new types for example generating Matrix struct with demensions known at compile-time.
*Changes suggested by dumblob*
- Overall improvement of safey: compile-time assertions, ahead-of-time proving of correctness of certains properties of passed data to a function etc.
- Optimization. Proving certain aspects of given data etc. For example regex module that compiles regular expressions to bytecode at compile-time instead of wasting time at runtime.
If we would not implement proper comptime until `1.0`, we probably would never manage to do so after the `1.0` release. Rust for example still does not have full `const fn` support in stable release. Also if we would not implement this, it would limit our compile-time reflection by a lot. 

# Prior art 

Main inspiration comes from Zig comptime. They use `comptime` to implement generics, implement serialization/deserialization and do compile-time reflection. You can read about it there: [What is Zig's Comptime?](https://kristoff.it/blog/what-is-zig-comptime/). 

Compile-time execution is great thing. Without it we have to use current ***very*** limited comptime implementation in V or resort to code that will generate V code or do useless computations at runtime. 

# Unresolved questions

- ~~How would we handle generic types?~~ Just use `v.ast.TypeSymbol` to handle generics
- How would we handle imports at compile-time? 
- How would we handle calls to extenral functions?
- How would we handle raw memory? 
- What syntax we should have for generating new types?
