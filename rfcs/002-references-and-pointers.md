- Topic Name: `references-and-pointers`
- Start Date: 2023-11-7
- RFC PR: [vlang/rfcs#29](https://github.com/vlang/rfcs/pull/29)
<!-- - V Issue: [vlang/v#00000](https://github.com/vlang/v/issues/00000) -->

# Summary

Standardise the current functionality with pointers and references, and remove ambiguities.

# Motivation

There are ambiguities to do with pointers inside V. Auto-deref and `mut` arguments often cause issues. This document aims to standardise what is and what isn't.

# Guide-level explanation

Currently, V operates on pointers with auto-deref. Assume the variable `v` below is a pointer to a `Struct`, these two expressions below, auto-deref will always overwrite memory and never set a pointer value.

```vlang
v := &Struct{}

v = value  // are we overwriting memory?
v = value  // do we set pointer address to address?
```

To be explicit with pointers, this is now mandatory.

```vlang
*v = Struct{}  // we are overwriting here
v = &Struct{}  // we are setting pointer values
```

**To understand this RFC, stop thinking of `mut` parameters as pointers, this is merely an implementation detail and should not be exposed to V.**

**`mut` parameters are just variables whos origin lies outside of the function, as far as users are concerned, it is not a pointer and should not act like one.**

Mutable non-pointer parameters should function as references in C++, or an `inout` parameter in other languages. 

```vlang
struct Struct {
	/* ... */
}

fn take_struct(mut v Struct) {
	ptr := &Struct(/* ... */)

	// no pointer arithmetic, never nil.
	// it's just a variable in the sense of the function, not a pointer here.
	v = Struct{/* ... */}

	field := v.field // auto "deref" on fields, this is normal
	v = *ptr         // need to deref here, overwrite memory
}
```

Below is a pointer, it functions equivalently with mutability however assignments are different. This is the current behavior in V.

```vlang
struct Struct {
	/* ... */
}

fn take_struct(mut v &Struct) {
	ptr := &Struct(/* ... */)

	// pointer arithmetic, may be nil in unsafe contexts.
	// it's a pointer, overwrite memory using *
	*v = Struct{/* ... */}

	field := v.field // auto deref on fields, this is normal
	v = ptr          // assigning integers to integers..
}
```

With the above, it's understood that the second example now explicitly takes a pointer, and the first example is just a variable that can be edited.

---

Instead of thinking of `mut params` as pointers, we can be explicit here.

The parameter of the `fn send` is mutable, it's a mutable binding to a variable outside of the function. We can take the address of it with the `&` operator, and it's the address of that outside variable.

```vlang
struct AA {/* ... */}

// the `mut AA` doesn't make sense for external C functions.
// fn C.external(mut AA)

fn C.external(mut &AA)

fn send(mut value AA) {
	C.external(&value)
}
```

You can't cast a `mut param` to a pointer, because it isn't a pointer. You must take the address of it.

No need to explicitly construct a pointer value, if you allow V to promote it's allocation you won't leave auto-deref territory.

You shouldn't even think in "promotion of allocations." At the end of the day a variable is a variable, and pointers are hidden.

```vlang
struct AA {/* ... */}

fn return_aa(value AA) &AA {
	mut a := AA{}
	a.field = 10
	a = value     // "auto deref" -- this isn't a pointer to users
	return a
}
```

**What about immutable `&T` ?**

When a `T` is immutable, it doesn't matter if it is passed by value or by reference. There is zero difference in underlying assembly code. Immutability plays a big part here.

**90% of the time, you will never use a `&T` in V code. It should be discouraged.**

If you're working with linked lists, need to set pointer values, that's fine. However, if you're working with an immutable receiver it doesn't matter.

Specifying a `&T` or `mut &T` will turn off auto-deref, for 90% of V usage, we should keep this. Keeping auto-deref means a `&T` shouldn't be used.

```vlang
fn (ref T) test0() {
	// ref is just a variable
	// it's immutable anyway, we don't need &T
}

fn (ref &T) test1() {
	// ref is a pointer, do arithmetic, etc
}
```

**You still want to work on pointers with auto-deref?**

Auto-deref is the current behavior with pointers, to keep operations on them the same as normal variables. Using the `[heap]` attribute or allowing the local variable to escape will promote them to become heap allocated, therefore you can still work on them just like normal variables.

```vlang
[heap]
struct AA {}

fn test() {
	// a is a variable, pointers are abstracted away.
	mut a := AA{}
}

struct BB {}

fn test_ptr() &BB {
	mut b := BB{}

	// use b, it's just a variable to V users.
	// however under the hood, it's heap allocated.

	return b
}
```

---

**Recap**

- A bare `mut param` to a function, as far as users are concerned, isn't a raw pointer. These should act like references in C++ or `inout` parameters in modern programming languages. \
A `mut param` being a pointer is merely an implementation detail.
- When you treat a `mut param` as a variable and not a pointer, auto-deref makes sense on assignments now, it's just a variable. \
Auto-deref should not be applied on explicit `mut param &T`, these are pointers.
- `&T` and `mut &T` should be discouraged in 90% of V code. \
Code that isn't working on linked lists, unsafe pointer operations, C interop, and so on.
- **This will not compromise existing V code.** \
No V code uses `mut param &T`, and 90% of them don't treat a `mut param` as a pointer anyway.
- In C code, a `mut param T` and a `mut param &T` are equivalent. \
Taking the address of a `mut param T` will return the backing pointer.

**Examples and Errors**

```vlang
struct AA {/* ... */}

fn needs_pointer(v &AA) {}

fn mut_aa(mut v AA) {
	needs_pointer(v)   // error: `v` is not a pointer
	needs_pointer(&v)  // fine.
}
```

```vlang
struct AA {/* ... */}

fn C.external(mut AA)  // error: cannot pass mutable variable (binding?)
fn C.external(mut &AA) // fine.

fn mut_aa(mut v AA) {
	C.external(&v)     // refers to the internal pointer
}
```

```vlang
struct AA {/* ... */}

fn zero0(mut v AA) {
	v = AA{}   // fine.
	*v = AA{}  // error: can't deref, `v` is not a pointer

	field := v.field
}

fn zero1(mut v &AA) {
	*v = AA{}  // fine.
	v = AA{}   // error: `AA{}` is not a pointer

	field := v.field
}
```

implementation details, only implement in v2

# Reference-level explanation

In V, we keep things simple. Pointers are abstracted away entirely.

When lowering to C, in certain cases the `&` operator when operating on mutable variable "bindings" will just return the pointer. This is behavior is in C++ as well with it's references.

```vlang
// src
fn C.external(mut &AA)

fn test0(mut v AA) {
	C.external(&v)
}
```

```c
// lowered
void external(main__AA*)

void main__test0(main__AA *v) {
	external(v)
}
```

**Remember, a `mut AA` when lowered to C is equivalent to a `mut &AA`. It just has different semantics inside V.**

V code won't change much with these additions, they just lay out an explicit standard on how these variables and pointers work together.

**Why discourage immutable `&T` ?**

There is zero functional difference when passing an immutable parameter by value or by reference, you're not editing the backing value at all. We should encourage passing immutable values without using a pointer, and let the compiler decide.

Letting the compiler decide, in my eyes, makes sense when doing optimisations when compiling with TCC. TCC throws all arguments on the stack, if it's a large immutable struct, it doesn't matter and will make a large copy. TCC doesn't know mutability information ahead of time, we do.

```vlang
struct AA {/* large struct, >= 16 bytes */}

fn take(a AA) {
	// ...
}
```

This will take a pointer here.

```c
void main__take(AA *a) {
	// ...
}
```

This is only an optimisation, we doesn't matter and we don't need to implement it. It's just an example of what we can do when we're in control.

**In 90% of V code, below should be used:**

```vlang
fn (v T) test()
fn (mut v T) test()
```

When you need pointers for C interop, linked lists, unsafe operations, be explicit here:

```vlang
fn (v &T) test()
fn (mut v &T) test()
```

# Rationale and alternatives, Drawbacks

I don't see a reason to not implement this, we can do it in a backwards compatible way. Currently V has many corner cases to using a `mut param` as a pointer, auto-deref getting in the way, etc. We need to standardise what we can and can't do otherwise, in my opinion, the language will not move forward.

I don't see any alternatives to this.

# Prior art

`mut param` should work like variables. C++, C#, and Swift have these in the form of references, `ref` parameters, and `inout` parameters respectively.

C++ can also allow you to take the raw pointer of a value below, this is what we're specifying here too.

```c++
// c++
void modify(int& ref) {
	ref = 42;
}

// take raw pointer with &
void modify_pointer_of(int& ref) {
	int* ptr = &ref;

	*ptr = 42
}
```

```c#
// c#
void modify(ref int value) {
	value = 42;
}

int number = 20;
modify(ref number)
```

```swift
func change(_ number: inout Int){
	number = 2
}

var number = 1
change(&number)
```

**Once we start treating references as references, and raw pointers as pointers, things will get a lot simpler.**

# Unresolved questions

As of now, I believe this design to be up to standard. I do not know of anything out of scope, or not covered. This will be updated or the RFC made clearer as more contributors take note.
