# Revamping error and none handling

## Abstract
This RFC proposes to change the current error handling mechanism, because the current `Option` type allows three values, `none`, `IError` and `T`. Handling three different kinds of values in every `or{}` block is confusing and could lead to unwanted behavior.

## Introduction
It was several times discussed to change the current error handling / none handling mechanism because `Option` allows three values.
It would be better to break them down into two types and the developer specifies which one he actually wants to use.

```v
fn foo() ?T {...}

foo() or {
  // should I return a default value when none is returned or panic when an error is returned?
}
```
The above example currently returns either a `T`, `none` or an `IError`, even if the function only returns `none` and `T` the end user might have to write code that also works with `IError` because the function could return it.

## Specification
---
**NOTE**

In the new examples `?` stands for `T | none` and `!` for `T | error`.

---

If the `foo()` function would specify if the result is either an `Option`/`?` or `Result`/`!`, the end user also knows how to handle it correctly
```v
fn foo() !string {...}

foo() or {
  // Ok, I know this is error here, just log it or panic. No none case happened that needs to be handled.
}
```

In case all three values could be possible, `T`, `none` or `error`, implementing anonymous sum types could help allowing the developer to define the return type as:
```v
fn foo() T | none | Error {...}
```

### Downsides of this specification
- Anonymous sum types are not yet implemented and needs to be implemented first

### Syntax
In most languages the questionmark `?` stands for optional values and could be used for the `Option` type. The equivalent operator would be the excalamtion mark `!` that could be used for `Result`.
That means `?string` would mean `Option<string>` and `!string` would mean `Result<string>`. Having the syntax of `?` and `!` would help indicating that's a compiler feature and is not related to generics or another language feature.

### Handling the results
Handling `?T` and `!T` is very easy and it will stay as it currently is:
```v
foo() or {...}
```
for both cases. But the `!T` adds an `err` variable to the `or {}` context. The downside of this is that the user would need to know which result arrives and he is dependent on a language sever to know it.

Since `T | none | error` is a sum type it can easily matched:
```v
match foo() {
  error {/* result is an error */} // IError will be renamed to error
  none {/* result is none */}
  else {/* result is the wanted value */}
}
```
---
**NOTE**

We can decide to use `it` or `foo() as x`

---

## Open Issues
Since this was discussed several times and is still an unsolved issue we would need to change it as long V is in alpha stage.
This change also brings breaking changes no matter which syntax will be chosen.

We need to decide which syntax to use in match either `it` or `foo() as x`

