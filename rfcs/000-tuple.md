- Topic Name: `tuple`
- Start Date: `2022-07-12`
- RFC PR: [vlang/rfcs#00000](https://github.com/vlang/rfcs/pull/26)
- V Issue: *not applicable*

# Summary

Add a `tuple` type. In programming, a tuple is generally a finite ordered list of elements not necessarily of the same type[^1].

# Motivation

Having a `tuple` type would assuredly be useful. This will fix the weird non-type output of a function returning multiple values. Moreover, this will also allow more specific usages for variadic functions.

# Guide-level explanation

A tuple will use a pretty well spread syntax: between parentheses.

```v
mut foo := ('hello', 42, true) // initialize a mutable tuple of a `string`, an `int` and a `bool`
println(foo[1]) // use an array-like syntax to access its elements, this will print `42`
foo[1] = 123 // `foo` will now equal `('hello', 123, true)`
foo[1] = 'world' // checker error: the second element of this tuple must be an `int`
println(foo.len) // prints `3`
println(foo) // prints `('hello', 123, true)`
```

## Multiple return values functions

The first use one would think of would be for functions returning multiple values.

```v
fn foo() (string, int, bool) {
    return 'hello', 42, true
}
```

Currently, the return values of the above function can **only** be used once assigned to different variables like below.

```v
str, num, yes := foo()
```

This means that if we only want one of the multiple returned values, we have to do like below.

```v
_, num, _ := foo()
println(num)
```

With this proposal, functions returning multiple values will no longer return a "pack" on values (which pack is specific to only this context), instead they will return a real type, a tuple.
Consequently, the above verbose code snippet can be replaced with the one below.

```v
println(foo()[1])
```

The above snippet is less verbose and doesn't require creating a new one-use variable (avoids allocations...).

## Variadic functions

In programming, a variadic function is a function of indefinite arity, i.e., one which accepts a variable number of arguments[^2].
See [here](https://github.com/vlang/v/blob/master/doc/docs.md#variable-number-of-arguments) for their usage in V.

As [@spytheman said on Discord](https://canary.discord.com/channels/592103645835821068/939724928419262545/995564582494011532), the arguments of a variadic function are converted to an array under the hoods. While this is great because it allows the arguments to be used just like an array, it makes it impossible to use arguments of different types.

Thanks to this proposal, the arguments could be translated to a tuple, making it possible to use arguments of different types. The syntax when the arguments can be of different type will be as below.

```v
fn foo(args ...) {}
```

Below is a minimal example implementing a [Python's `.format()`](https://docs.python.org/3/library/stdtypes.html#str.format)-like function.

```v
fn main() {
    python_format('{} said he was nearly {} years old.', 'Jalon', 99)
}

fn python_format(str string, args ...) {
    mut out := str
    for arg in args {
        out = str.replace_once('{}', arg)
    }
    println(out)
}
```

---

Supporting `fn foo(a ...)` is necessary[^3] for [Go2V](https://github.com/vlang/go2v). Go2V needs to reimplement the [Go's `fmt.Printf()` function](https://pkg.go.dev/fmt#Printf), which signature in V would be `fn printf(str string, args ...)`.

# Reference-level explanation

V could also be smart about using an array or a tuple under the hoods. V could also enforce developers to precise the type when possible by printing a warning (or an error in `-prod`).

 function signature | all arguments of the same type | V checker | V uses a/an
--------------------|--------------------------------|-----------|------------
`fn foo(a ...type)` | yes                            | ok        | fixed array
`fn foo(a ...type)` | no                             | error     | -
`fn foo(a ...)`     | yes                            | warning   | fixed array
`fn foo(a ...)`     | no                             | ok        | tuple


# Drawbacks

To be found.

# Rationale and alternatives

To be found.

# Prior art

Tuples are a very common in multiple languages such as Python ([doc](https://docs.python.org/3/library/stdtypes.html#tuple)), C++ ([doc](https://en.cppreference.com/w/cpp/utility/tuple)), C# ([doc](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/value-tuples)), Dart via an official package ([doc](https://pub.dev/packages/tuple)) and probably others.

This is also widely used and necessary in Minecraft modding, to override default behaviors of the game.

# Unresolved questions

- Should a tuple of one element be allowed? Python allows it and uses a trailing comma `(a, )` syntax.

```v
a := ('hey', )
// or
b := tuple('hey')
```

- Should a tuple can be sliced? And should it give another tuple or an array if the elements are all of the same type?

```v
a := ('hey', 42)
println(a[..1])
```

- Should it be possible to use a tuple as multiple arguments of a function?

```v
fn foo(a string, b int)

fn main() {
    c := ('hey', 42)
    foo(c)
}
```

# Future possibilities

To be found.

# References

[^1]: https://en.wikipedia.org/wiki/Tuple
[^2]: https://en.wikipedia.org/wiki/Variadic_function
[^3]: https://discord.com/channels/592103645835821068/939724928419262545/995444090504220792
