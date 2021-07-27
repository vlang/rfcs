# Revamping error and none handling

## Abstract
This RFC proposes to change the current error handling mechanism, because the current `Option` type allows three values, `none`, `IError` and `T`. Handling three different kinds of values in every `or{}` block is confusing and could lead to unwanted behavior.

## Introduction
It was several times discussed to change the current error handling / none handling mechanism because `Option` allows three values.
It would be better to break them down into two types and the developer specifies which one he actually wants to use.

```v
fn foo() ?string {...}

foo() or {
  // should I return a default value when none is returned or panic when an error is returned?
}
```
The above example currently returns either a `string`, `none` or an `IError`, even if the function only returns `none` and `string` the end user might have to write code that also works with `IError` because the function could return it.

---
**NOTE**

The new examples will use `Option` and `Result` to distinguish between `?` syntax. It's not the final syntax yet.

---

If the `foo()` function would specify if the result is either an `Option` or `Result`, the end user also knows how to handle it correctly
```v
fn foo() Option<string> {...}

foo() or {
  // Ok, I know this is none here, just provide a default value. No error happened that needs to be panicked.
}
```

## Specification
Implementing anonymous sum types could help allowing the developer to define the return type as:
```v
fn foo() string | none | Error {...}
```
whereas the part `string | none` can be shortened with `?string`.
It would result in
```v
fn foo() ?string | Error {...}
```
where `?` is a shortcut for a sum type `Option` whose implementation could look like this:
```
type Option<T> = T | none
``` 
Error wouldn't have a syntax sugar in this case.

### Downsides of this specification
- Anonymous sum types are not yet implemented and needs to be implemented first
- Generic sum types are not yet implemented and needs to be implemented first
- The Option sum type needs to be compiler generated rather than syntax generated to make it possible to be used inside `builtin`. Caching generics isn't possible yet.
- `or{}` block would be the Jack of all trades because it is used for two special kinds of sum types that are not related to each other and doesn't share anything.
- It would be possible to define variables like `x := Option<string>('foo') // or ?string('foo')` (it's obviously a sum type that can be used everywhere) but this feature should only be used for return types of functions and struct fields. One solution would be to restrict this sum type.

### Or interface
Since both, `Option` and `Result` would be handled by an `or{}` block, both types could implement a compiler internal interface `Or` that implements the syntax sugar `or {...}`.

### Syntax
In most languages the questionmark `?` stands for optional values and could be used for `Option`. The equivalent operator would be the excalamtion mark `!` that could be used for `Result`.
That means `?string` would mean `Option<string>` and `!string` would mean `Result<string>`. Having the syntax of `?` and `!` would help indicating that's a compiler feature and it wouldn't be needed to use sum types that obviously has some overhead.

There is only one tricky part: `?!string` or `!?string`. What would it mean? Which ordner is needed? One solution would be to define that the order doesn't matter.
`!?` or `?!` always results in `Result<Option<T>>` or `T | none | Error`. But V fmt could always reformat it to `!?` for example.

---
**NOTE**

This is even a rare case. It's complexity isn't that awful.

---

### Handling `Result<Option<T>>`
Handling `?T` and `!T` is very easy and it will stay as it currently is:
```v
foo() or {...}
```
for both cases. But the `!T` adds an `err` variable to the `or{}` context. The downside of this is that the user would need to know which result arrives and he is dependent on a language sever to know it.
An alternative approach would be `or{}` for `Option` and `catch{}` for `Result`. A catch block always has the `err` variable and the `or{}` block nerver has it.

Handling the `!?T`/`Result<Option<T>>` with `or{}` would result in the initial behavior, we already have. For this a solution would be to extend the functionality of `match`.
Matching the `!?T` type would always look like this:
```v
match foo() {
  error {/* result is an error */} // Currently there is no "error" type but Error/IError. Maybe it would be nice to mark error as an internal type by writing it lowercase.
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

Currently there is no final syntax decision for this but some suggestions we have to choose from.

