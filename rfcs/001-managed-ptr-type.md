- Topic Name: managed_ptr_type
- Start Date: 2022-03-29
- RFC PR: [vlang/rfcs#23](https://github.com/vlang/rfcs/pull/23)

# Summary

This RFC is about annotating pointer types as appearing in function parameters and return values as well as struct members with a hint as to wether they are pointing to a heap object, or a stack object or member of a heap object. This is important since ideally we want to manage the lifetime of heap objects automatically through a combination of auto-free and reference counting. And while the compiler can infer all information it needs inside a function it cannot do so across functions or structs, hence the need arises for such an annotation.
The goal here is to strike a unique balance between poles like C/C++, Lobster, Rust, and others that fot the unique needs of of being easy to use, safe, but also allows some of the flexibility pointers give in C/C++ and other languages.

# Motivation

Implementing this proposal will enable us to automatically manage heap objects leaving and entering functions and living inside of structs, and thus prevent memory and resource leaks and free the programmer from manual resource/memory management.

# Guide-level explanation

This proposal introduces an alternative pointer syntax for function return values:

```
fn foo() ^Struct
{
    return &Struct{}
}

```

struct members:

```
struct Struct
{
    other ^Struct
};
```

 and function arguments:

 ```
 fn (s &Struct)(other ^Struct)
 {
    s.other = other
 }
 ```

or even

 ```
 fn (s ^Struct)(other &Struct)
 {
    other.other = other
 }
 ```

 where replacing `&` with `^` in struct pointers used as function arguments, returns or struct members signify that these are managed heap objects and the thusly annotated objects transport (possibly shared) ownership of these objects.

# Reference-level explanation

Having objects annotated as pointing to heap objects on the interfaces to functions and structs means the compiler can extend reasoning outside of single functions and insert automatic calls to (possibly user enriched) free functions.

# Drawbacks

It does make the syntax more complex. Especially it introduces a slight bit of confusion where explicit heap allocation will likely still use the old operator `&Struct` to construct an object that is effective of type `^Struct`. This choice was made to change the syntax as little as possible.

# Rationale and alternatives

## Why is this design the best in the space of possible designs?

because it closes exactly the ramaining gap to extend lifetime reasoning outside functions and not less and not more.

## What other designs have been considered and what is the rationale for not choosing them?

The author can only see two alternatives:
- manual resource management, which has a mission goal to avoid, and relying on a garbage collector, which introduces performance problems and thus far does not support user defined free functions
- abandoning references semantics altogether, at which point we could fully adopt the lobster ownership model

## What is the impact of not doing this?

basically giving up on auto-free beyond the body of a single function. if we dont do this we have to assume every pointer which is a struct member, function argument or return could point to a stack object or inside another struct. this also means there is no point to introducing reference counting at all because there is nothing left to do for it.


# Prior art

Objective-C could be seen as prior art, but only because it basically mixes two languages: a Smalltalk derivative and plain C. The managed objects that are introduced for its Smalltalk-like side of things are managed using a combination of reference counting and compiler reasoning called ARC that is very similar to what V wants to achieve. But at the same time plain pointers are still allowed.

C++ could also be seen as prior art, though here lifetime management is never assisted by the compiler, but its semantics allow to build objects that perform the lifetime management for you and have different objects for different purposes, thereby achieving something similar, although with more ways to hang themselves than we want to allow in V.

Rust can be seen as prior art, especially in it's use of annotations to track ownerships. It also allows reference counting, but only explicitly.

# Unresolved questions

How much should we enforce the use of this feature? Ideally we would require all pointers to heap objects entering or leaving a function to be annotated to avoid leaks. But since this would require to change a lot of code at once we may want to do this gradually?

# Future possibilities

This proposal aims to be self-contained and do nothing more than close the last gap enabling us to do automatic memory and resource management. That said the fact that one can still pass around pointers to inside other objects means one can still easily introduce memory errors such as segmentation faults or worse undefined behavior that can be exploited by malware. While the authors do not have a concrete proposal to mitigate this it seems related to lifetime management and maybe other authors find a good way to lifetime manage/track such pointers too.