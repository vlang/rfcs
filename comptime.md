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

With this RFC the main change is that all expressions and statements prefixed with `$` will be treated as compile-time and all of them can be executed *before* codegen. Current compile-time is quite limited and allows only a few statements (`$if`,`$for`) and only specific calls.

You can compare new way of handling comtime to Zig comptime functionality. It would allow us not only to perform some computations at compile-time but also generate new structures and functions at compile-time. All generic types would not be just some compiler magic but `v.ast.Type` and you should be able to invoke all of its methods at compile-time, get type symbol from it and even create new `v.ast.Type`s at compile-time.  

First where comptime can be used is automatic generation of serialization/deserialization functions. Here's small example of how we can implement automatic `str()` for types: 
```v
fn to_str<T>(val T) string {
    // FIXME: Decide if generic type is `v.ast.Type` or `v.ast.TypeSymbol`
    $if T.kind == .int {
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
        $for field in T.fields {
            field := val.$field 
            out = '${out} ${$field}: ${field}'
        }
        return '${out}}'
    } else {
        // and so on...
    }
}
```

Notice that we do not have `$else` anymore, that is because with this proposal if parser sees `$` it simply continues parsing V statements or expressions *but* parsed statement and expression will be marked with `comptime` flag.

And here is simple example of factorial that is executed fully at compile-time! 
```v
fn factorial(x int) int {
    if x < 2 {
        return x 
    } 

    return factorial(x - 1) * x
}

fn main() {
    cx := $factorial(5) // call prefixed with `$` becomes compile-time call
    $cy := factorial(6) // variable assignment prefixed with `$` puts it to compile-time environment 
    println(cx) // 120 
    println($cy) // 720
}
```

# Reference-level explanation 

In parsing we should change our handling of `$` symbol. Instead of parsing specific comptime cases we should simply continue parsing expression or statement but in the end mark it with `comptime`. `comtpime` mark can be stored in each of AST nodes. 

To implement this we would not need to significantly change checker, we would just need to add additional compile-time environment for comptime variables (generics will be treated as comptime variables too!). After code is checked we would just continue to codegen and each of `v.gen.*` implementations *must* evaluate expressions and statements marked with `comptime`. This is where it might get complex but to solve this we will simply use `v.eval`, `v.eval.Eval` will be stored per generation context. We should also find a way to pass generation context to eval context so we can for example implement `include` builtin call that would include C/JS file into output file. Something like this:

```v
gen.eval.add_func('include', fn (gen cgen.Gen, args []Value) {
    gen.includes.write_string(args[0].str())
})

// used like this in toplevel:
$include("header.h")
```

# Drawbacks 
This would break a lot of code that depends on current implementation of compile-time and it would take quite a lot of time to switch to new comptime and implement it. 

# Rationale and alternatives 

This design allows to execute entire V language at comptime and it makes it possible to:
- Implement serializers/deserializers
- Write code that would produce new code a-la Lisp macros 
- Write code that would generate new types for example generating Matrix struct with demensions known at compile-time.

If we would not implement proper compotime until `1.0` we probably would never manage to do so after `1.0` release. Rust for example still does not have full `const fn` support in stable release. Also if we would not implement this it would limit our compile-time reflection by a lot. 

# Prior art 

Main inspiration comes from Zig comptime. They use `comptime` to implement generics, implement serialization/deserialization and do compile-time reflection. You can read about it there: [What is Zig's Comptime?](https://kristoff.it/blog/what-is-zig-comptime/). 

Compile-time execution is great thing. Without it we have to use current ***very*** limited comptime implementation in V or resort to code that will generate V code or do useless computations at runtime. 

# Unresolved questions

- How would we handle generic types? 
- How would we handle imports at compile-time? 
- How would we handle calls to extenral functions?
- How would we handle raw memory? 

