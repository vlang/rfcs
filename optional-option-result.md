- Topic Name: Optional Option/Result
- Start Date: 2022-06-25
- RFC PR: [vlang/rfcs#00000](https://github.com/vlang/rfcs/pull/00000)
- V Issue: [vlang/v#00000](https://github.com/vlang/v/issues/00000)

# Summary

The language currently does not provide a way to let developers handle memory allocation issues.
Many developers are happy with the state of things: memory allocation failures are rare and a panic is acceptable.
However the language could (and probably should) provide a way to handle these issues.

A way to achieve this goal would be to return option/result without requiring the caller to handle failure scenarios.

# Motivation

V aims to provide developers the tools required to write solid applications however panicing on memory allocation can leave the application and its data in a invalid state.

The developers should be able to handle these border cases without causing undue complexity on simpler applications.

# Guide-level explanation

Looking at this code:
```v

fn new_thingy () {
 return &Thingy{
  buffer: []int{len: 10000, cap: 30000}
 }
}

```

The code could fail as the underlying `malloc` code could fail as array is calling malloc which can panic

```v

[unsafe]
pub fn malloc(n isize) &u8 {
 ...
 if res == 0 {
  panic('malloc($n) failed')
 }
 ...
}

```

The syntax could be changed to allow a new operator ?? returning an option/result but leaving it up to the caller to handle it or not.

```v

fn new_thingy () ??{
	return &Thingy{
		buffer: []int{len: 10000, cap: 30000}
	}
}

```

```v

fn new_unsafe_thingy() {
  return new_thingy()
}

```

```v

fn new_safe_thingy() ? {
  return new_thingy() or {
    error('memory allocation failed')
  }
}

```

V may require an new "stricter" compilation option forcing developers to handle all possible optional option/result.

It may be that `??` could be used when the absence of handling is fine and `!?` used when the handling of the `or` case must be performed when compiling using the stricter mode.

# Reference-level explanation

This part is left out as my understanding of V does not allow me to correctly provide an answer.

# Drawbacks

It could lead to many code path not checked. It makes the language more complex.

If the AST is not trimmed, the generated C code may be slower due to the extra error handling.

# Rationale and alternatives

It may not be the best possible design, I have not considered any alternatives.

# Prior art

AFAIK, this is a "novel" idea (it may exist elsewhere but I am not aware of it)

# Unresolved questions

Not answered

# Future possibilities

The concept could be extended to allow the return of default value on failure:

```v

fn to_integer (s string) ??int {
 if isnumeric(s) {
  return string_to_integer(s)
 }
 return error_with_default('this is not a number', 0)
}

```

```v

a := to_integer('10') // 10
b := to_integer('abc') // 0
c := to_integer('abc') or { 100 } // 100
d := to_integer('abc') or { print(err); return } // displays 'this is not a number'

```
