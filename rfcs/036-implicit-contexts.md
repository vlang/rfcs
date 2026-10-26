- Topic Name: implicit-contexts
- Start Date: 2026-10-26
- RFC PR: [vlang/rfcs#36](https://github.com/vlang/rfcs/pull/36)
- V Issue: N/A (to be created by maintainers on acceptance)

# Summary

Add *context parameters* to V: parameters that a function declares up
front in a bracket group, and that the compiler threads through
ordinary calls automatically, resolving each one against the caller's
lexical scope.

```v
// declare: `ctx` is a context parameter of type &Allocator
pub fn read_config[ctx &Allocator](path string) !Config {
	raw := read_bytes(path) // read_bytes declares [ctx &Allocator] itself,
	return parse_config(raw)! // and gets ours, implicitly
}
```

Call sites do not change unless the author wants them to:

```v
with alloc { // ambient supply, matched by type
	config := read_config('conf.json')!
}

// explicit supply, resolved per call:
config := read_config[ctx: alloc]('conf.json')!
```

The first standard use case is the roadmap's: allocation contexts.
Today only `veb` has implicit context passing, and that mechanism is
hardcoded into the checker for veb's shapes. This RFC generalizes it
so any library can express the same thing in source, and so the
compiler stops accumulating per-framework versions of the same passthrough.

# Motivation

- The [V 0.6 roadmap](https://github.com/vlang/v/blob/master/ROADMAP.md)
  lists "Contexts that are passed implicitly (e.g. for custom
  allocation/memory management)" as an unchecked item.
- V already implements the feature, but only for one framework.
  `vlib/v/types/checker.v` (`insert_implicit_veb_ctx`,
  `fn_needs_implicit_veb_ctx`) inserts a hidden `mut ctx Context`
  parameter into veb handlers that return `veb.Result`, have an app
  receiver, and declare no context parameter of their own. The same
  special case is carried by three more passes:
  `vlib/v/transform/comptime.v` (`method_has_implicit_veb_ctx`),
  `vlib/v/markused/markused.v` (`markused_fn_needs_implicit_veb_ctx`),
  and the ownership pass (see
  `test_ownership_veb_implicit_context_arg_moves` in
  `vlib/v/compiler_tests/ownership/ownership_test.v`). The
  user-facing result is real and good; a veb handler uses `ctx`
  without declaring it, from
  [`examples/veb/cors/veb_cors_example.v`](https://github.com/vlang/v/blob/master/examples/veb/cors/veb_cors_example.v):

  ```v
  @[post]
  pub fn (app &App) time() veb.Result {
  	return ctx.json({
  		'time': time.now().format_ss_milli()
  	})
  }
  ```

  The problem is that the mechanism is welded to veb: the recognizer
  keys on `veb.Result`, app-shaped receivers, and the `Context`
  type name. Any other framework in vlib that wants the same
  property (`vlib/mcp` server contexts, session middleware, game
  render contexts) would need its own compiler patch.
- The allocator half of the roadmap item is already prototyped
  in-tree as the *only* alternative to explicit threading: a
  mutable, thread-local global. `vlib/v/profiler/context.v` defines
  an `Allocator` interface (its comment says "Similar to Jai's
  `context.allocator` design"), hangs it off
  `@[thread_local] __global profiler_context`, and scopes it with
  `push_allocator` / `pop_allocator`. That works locally, but it is
  still hidden shared state: nested regions clobber each other when
  the push/pop pairs are not perfectly disciplined, the value cannot
  soundly cross a `spawn` boundary, and every allocating call in the
  scope silently depends on whatever a `push` happened to install
  somewhere else in the file.
- Nothing connects library allocator types today: `vlib/dlmalloc`
  defines its own `Allocator` struct, `vlib/sokol` aliases C's
  `sapp_allocator`, and `vlib/v/profiler` has a third shape, so the
  ecosystem cannot converge on one allocation story.

Expected outcome: close the roadmap item with a design the community
has compared and approved, implement it, and in a later step migrate
veb onto it so the veb-only checker special case can be removed.

# Guide-level explanation

## What a context parameter is

A context parameter is a named value the function requires from the
*caller's scope* rather than from an argument list. The declaration
lives in a bracket group in front of the regular parameters:

```v
fn read_config[ctx &Allocator](path string) !Config {
	raw := read_bytes(path) // ctx is an ordinary immutable value here
	return parse_config(raw)!
}
```

The function cannot run without it, but passing it is the caller's
problem, and the caller's caller's problem, and so on up the chain
until someone makes the value available. No function between the
supplier and the consumer changes its own signature or its own call
sites; the compiler carries the value along paths that need it, and
only along paths that need it.

Unlike a mutable global, the binding is resolved *per lexical call*:
every call site resolves against the scope it is written in, so a
reader can tell from source whether a callee's requirement is
satisfied *here*, not wherever a global happened to be left set.

## Declaring and using them

Context parameters are declared in the same brackets V already uses
for generics; the shape differs, so both fit the bracket slot:

```v
// one
fn span_from[ctx &Allocator](start int) Span {
	return Span{ start: start, alloc: ctx }
}
```

```v
// two, comma-separated
fn build_node[ctx &Allocator, log &Logger](budget u64) ?Node {
	log.trace('build_node budget=${budget}')
	return ctx.alloc(budget)?
}
```

```v
// methods may also declare one, after the receiver
fn (doc &Doc) render[ctx &Allocator](w int, h int) string {
	return ctx.slice(doc.text, w, h)
}
```

Inside the body, context names are ordinary immutable values:
readable, type-carrying, capturable. They have no default value and
no `mut` in this RFC (see unresolved questions for the planned
follow-up).

## Supplying a context explicitly

A call may supply context arguments by name, in the same bracket
slot where the type call `f[int]` sits today:

```v
alloc := &Allocator{ ... }
config := read_config[ctx: alloc]('conf.json')!
```

Explicit supply overrides any ambient binding and is the
disambiguator of last resort. There is nothing else to learn.

## Supplying a context for a region

The `with` block introduces an ambient binding for the whole block,
matched by type to the context parameters of the calls inside:

```v
with alloc {
	// both calls resolve &Allocator to `alloc`:
	cfg := read_config('conf.json')!
	out := render_scene(scene)!
}
```

Where blocks nest, the innermost `with` wins, exactly the way a
local shadows an outer local:

```v
with test_alloc {
	for i in 1 .. runs + 1 {
		with per_run_alloc {
			// &Allocator contexts inside this loop resolve to per_run_alloc
			run_seed(i)
		}
	}
	// &Allocator contexts resolve to test_alloc again out here
}
```

To supply several context types over one region, nest:

```v
with alloc {
	with logger {
		// &Allocator binds to alloc, &Logger to logger
		node := build_tree(data)!
	}
}
```

The binding is read *per call*, not snapshotted at block entry, so a
supplier re-assigned inside the region takes effect from the next call
in it - allocations follow program flow, without nested blocks or
restore discipline:

```v
with alloc {
	for i in 1 .. runs + 1 {
		if i >= warmup_runs {
			alloc = &steady_arena // re-bind mid-region
		}
		run_seed(i) // allocations land in the supplier's value at the
		// time of the call: warmup arena early, steady arena after
	}
}
```

## Propagation through ordinary calls

A function that itself declares context parameters supplies its own
to every callee that requires one of the same type; neither
signature nor call sites change further:

```v
fn process[ctx &Allocator](raw []u8) !Result {
	// parse declares [ctx &Allocator]; it receives process's ctx
	// with no extra boilerplate at either end:
	tree := parse(raw)!
	return tree.eval()
}
```

This is the property that makes the feature compose. Helper chains
share the context of whichever function invoked the chain, and
inserting a hop in the middle is a no-impact change for existing
call sites.

## When nothing matches

If a call needs a context of some type and the call site is covered
neither by a matching `with` block nor by any enclosing context
parameter, the program does not compile, naming the callee:

```v
fn main() {
	// error: `read_config` requires an `&Allocator` context
	config := read_config('conf.json')!
}
```

```text
error: call to `read_config` requires an `&Allocator` context; none
is in scope. Pass it explicitly (`read_config[ctx: v](...)`) or
provide one with a matching `with` block.
```

Two matching values at the same scope depth are an error, not a
silent pick:

```v
with a {
	with b {
		// error: both `a` and `b` match the required &Allocator
		config := read_config('conf.json')!
	}
}
```

```text
error: two matching context values of type `&Allocator` are in
scope; pass one explicitly with `read_config[ctx: ...]`.
```

Proposed sample messages (wording open to bikeshedding):

- `` error: call to `read_config` requires an `&Allocator`
  context; none is in scope. Pass it explicitly
  (`read_config[ctx: v](...)`), or provide one with a matching
  `with` block. ``
- `` error: two matching context values of type `&Allocator` are
  in scope; pass the context argument explicitly. ``
- `` error: `spawn` does not forward ambient contexts; pass
  context arguments explicitly inside the spawned closure
  (`f[ctx: v](...)`). ``
- `` error: a bracket group cannot mix generic and context
  parameters. ``

## What does not change

- Plain local variables never satisfy context requirements. Ambient
  availability comes *only* from `with` blocks and from an enclosing
  context parameter of a matching type. A local `&Allocator` next to
  unrelated calls does not start feeding callees when a library adds
  a context parameter somewhere (this is the rule that keeps the
  mechanism bounded; see rationale).
- Functions without bracket groups compile unchanged, and calls
  into them compile unchanged.
- `veb` keeps working exactly as today, special case included, until
  it migrates to context parameters (timeline below).
- Named arguments, default values, `?`/`!` handling, variadic
  parameters, and comptime reflection keep their current meanings.
  Context parameters are not part of the variadic expansion.

# Reference-level explanation

## Grammar

The bracket group gains a second, value-level reading, and the
parser distinguishes the readings by element shape:

| Group                    | Shape of elements          | Accepted today? |
|--------------------------|-----------------------------|-----------------|
| `[T, U2]`                | bare identifiers (types)    | yes (generics)  |
| `[ctx &Allocator, ...]`  | `name Type` (parameters)    | new (declarations) |
| `f[ctx: value]`          | `name: expr` (arguments)    | new (calls)     |

Notes on the shapes:

- `[T]` stays generics; a group containing any `name Type` element
  is a context group; mixing both in one group is a hard error.
- The `[name: value]` call form mirrors struct initialization
  (`Foo{field: v}`) and named arguments, so both are known shapes,
  just in a new slot.

Context parameters:

- must declare a name and a type (any V type a field may carry);
- cannot have defaults: their meaning *is* "must be supplied by
  the caller's scope";
- cannot be `mut` in this RFC (the veb case needs `mut ctx`; that is
  the planned follow-up);
- cannot be declared on lambdas, closures, or fn-pointer types in
  this RFC (unresolved question);
- are accepted on plain functions and on methods, the group always
  sitting between the receiver (if any) and the `(...)`.
- are accepted on variadic functions; they are not part of the
  variadic expansion.

## Binding rules

When the checker reaches a call `f(args)` whose callee declares
context parameters:

1. If the call supplies one explicitly (`f[ctx: value]`), the
   expression is checked against the callee's declared parameter by
   name and type, then resolved like any argument; the ambient rule
   does not apply to that parameter for this call.
2. Otherwise, the checker searches the current lexical scope
   innermost out for a binding of exactly that type. A matching
   binding can come from only two kinds of declarations: an
   enclosing `with` block, or an enclosing function's own context
   parameter of a matching type. Two or more bindings at the
   innermost matching depth are an error (pass explicitly); the
   checker does not consult shallower depths to break the tie.
3. `spawn` is a boundary (rule 2 does not apply across it): ambient
   values are not forwarded by a spawn; code inside one thread calls
   context-taking functions only explicitly, or supplies its own
   `with` blocks. (Code that runs *inside* such a spawned closure,
   before another spawn, is still ordinary single-thread code and
   supplies itself.)
4. Once bound, the context value is just a value: usual ownership,
   lifetime, and copying rules of a local.

`with` blocks:

- accept exactly one expression; more than one context type needs
  nested blocks;
- nest by plain shadowing: an inner `with` of the same type hides
  the outer one for the extent of its own block, and the outer
  binding is what the code after the inner block sees; there is no
  stack mutation and no merge semantics;
- deferred functions registered inside a `with` block resolve
  calls lexically, so their context needs are satisfied by the
  binding where the deferred code was written;
- the supplied value lives by ordinary V local rules; no extra
  lifetime machinery enters here.

## Value read semantics

- A `with` block binds an *expression*, and that expression is read
  at each call that resolves to it, as the call executes: ordinary
  local-variable rules apply per call site, not once per block.
  Re-assigning a supplier mid-block updates every subsequent call
  that resolves to it (the loop example in the guide section). An
  enclosing function's own context parameter is fixed for its frame,
  the way a parameter is.
- Explicit per-call supply (`f[ctx: expr]`) reads `expr` when the
  call executes, identically.
- The consequence is that context binding needs no snapshot
  machinery, no copy-on-write buffer, and no "a loop cannot update
  the context" carve-out: both binding shapes are an ordinary
  expression read at an ordinary call site, which some ambient
  per-scope context systems must reject or work around with
  indirection (see prior art, Odin).

## No runtime mechanism

- Implicit propagation is compile-time only. There is no dynamic
  scoping machinery at runtime: no thread-local stack, no lookup,
  no ABI change of any kind. A resolved implicit call compiles to
  the exact call a manual author would have written by hand, so
  `-parallel-cc`, `-usecache`, backends, and profiling all inherit
  today's behavior unchanged.
- A callee reached over several hops receives the value its caller
  passed, and that value was resolved once, at the caller's own
  call site (which itself resolved against that call site's lexical
  scope). Nothing re-resolves per frame.
- fn-pointer and interface method shapes cannot carry context
  requirements in this RFC, so code storing functions in structs,
  vtables, or maps compiles unchanged. A pointer *materialized* at
  a context-materializing call site binds the context argument at
  creation, the same way a generic today is fulfilled by an
  expressly instantiated concrete instantiation (unresolved
  question).
- Ownership: context arguments at call sites follow the same
  parameter-move rules as written-out arguments. The existing veb
  test (`test_ownership_veb_implicit_context_arg_moves`) already
  anchors the same semantic for the veb-inserted `ctx`.
- Checker bookkeeping is per call site, computed during the
  existing scope walk, so it is compatible with the parallel
  checker; the declaration data is registered per function the way
  `fn_implicit_veb_ctx` already is.

## The allocation context

This RFC attaches no allocation semantics of its own: the context
mechanism is general, and `Allocator` is merely the first
consumer. The proposed sequencing:

1. Land the context-parameter mechanism (this RFC) using an
   `Allocator` value in the guide examples.
2. Decide the payload contract elsewhere: the in-tree
   `vlib/v/profiler` shape (an allocator struct with alloc /
   free / realloc function pointers plus user data) is the natural
   starting point for promotion to the canonical `Allocator` that
   the ecosystem converges on.
3. Libraries opt in by declaring `[ctx &Allocator]` themselves
   (parsers, image codecs, engines, arena-based tools). vlib code
   keeps compiling unchanged meanwhile; libraries can migrate
   without compiler help.

The runtime behavior of allocations does not change in this RFC.
What changes is the plumbing: the value that decides "which heap
this allocation goes to" flows along compiler-checked edges
instead of every hand-threaded parameter, or one mutable
thread-local global.

## veb migration

Veb adopts the mechanism in source once it can express its shape
(the `mut` follow-up):

```v
// before (special cased in the checker):
pub fn (app &App) index() veb.Result {
	return ctx.text('ok')
}

// after: plain source, no checker special case
pub fn (app &App) index[mut ctx veb.Context]() veb.Result {
	return ctx.text('ok')
}
```

Handlers that already declare their `ctx` parameter explicitly
today are already the "opt-out" spelling; the recognizer skips
them, and those definitions continue to compile unchanged through
the migration. Once the source form is in wide use,
`fn_needs_implicit_veb_ctx` and its three sibling passes become
redundant and are deleted. Removing an implementation-level
special case (rather than adding new ones) is what justifies this
RFC's complexity budget.

## Implementation notes

For compiler reviewers; if the RFC is accepted, an implementation
plan with exact diffs follows.

- **Parser** (`vlib/v/parser/parser.v`): the bracket-group code
  learns the two new element shapes above; `with` is a new block
  statement with exactly one initial sub-expression.
- **Checker** (`vlib/v/types/`): on declaration, context
  parameters are registered next to the fn's parameter data (the
  same registration pattern as the veb map); resolution walks the
  ordinary scope chain (the walk that resolves local shadowing),
  filtering by exact type. The parallel checker receives context
  declarations the same way it already receives the veb flags.
- **cgen / backends**: nothing new. A resolved implicit call was
  rewritten during checking into an ordinary call carrying an
  ordinary argument.
- **Transform and comptime**: no new machinery. In this RFC,
  context parameters are not exposed to comptime reflection (see
  unresolved questions), so existing comptime shapes are
  unchanged.
- **Dynamic backends and the interpreter**: same resolution
  happens at check time; no thread-local or runtime `with`
  structure exists.

# Drawbacks

- The `[...]` bracket group gains a second meaning in a language
  that sells a small grammar. The element shapes are structurally
  distinct, but a reader does have to have learned the rule.
- `with` is a new reserved word; V's reserved-word budget is
  deliberately small. The keyword earns its place by being
  greppable and unambiguous, but it is a cost.
- Implicit flow is exactly that: not every input of every call
  appears at the call site. V's design culture is explicit; this
  RFC argues the edge surface stays small (supply only by a lexically
  visible `with` or an enclosing context parameter, never from an
  arbitrary local or global), and that the roadmap item is worth
  that trade, but the trade should be called out and weighed by
  reviewers.
- Exact-type matching means renaming an established context type
  is a mechanical but potentially wide edit across call sites.
  Interface-based matching would soften this at the cost of
  exactness (unresolved question).
- Same-type nested `with` blocks shadow rather than merge; two
  libraries that scope the same context type over overlapping
  regions must be mutually aware at the composition point. The
  compiler can detect the conflict (ambiguity error) but cannot
  pick the intended value for the author.
- Public-shape ripple: libraries adopting context parameters
  change their public surface once; existing explicit call sites
  need a one-time mechanical update, like any other signature
  change.

# Rationale and alternatives

Commenters: this is the section to react to. Please say which
option you prefer (A-F) and why, especially if you disagree with
the recommendation.

## Option A - Declared context parameters (recommended)

As designed above: bracket declaration, `with` blocks, enclosing
context parameters, and per-call explicit supply; resolution by
exact type, innermost wins, ambiguity errors; compile-time only,
no runtime structure, no ambient capture, `spawn` as an explicit
boundary.

Recommended because:

- It generalizes a mechanism the compiler already implements for
  veb rather than inventing one, and eventually removes four
  subsystem-level special cases along the way.
- Declared context parameters are greppable, and the name is
  local to the callee: nothing spreads an ecosystem-wide
  convention through call sites.
- The supply surface is minimal and teachable: `with`, an
  enclosing declaration, or spell it out. Exactly one matching
  binding at a depth, or a refusal.
- The safety rules match practice already validated in-tree by
  veb: compile-time resolution, no runtime lookup, no implicit
  cross-thread transport.

## Option B - Magic-parameter recognition

Veb's approach, generalized to shapes: the compiler recognizes
any parameter named `ctx` (or another reserved name) of a type
that declares itself a context, and threads it implicitly:

```v
// nothing at the signature identifies a context explicitly
fn read_config(alloc &Allocator, path string) !Config { ... }
```

Rejected, but kept on the table because it is the smallest-syntax
option: it turns an ordinary parameter into a semantic one based
on spelling alone, degrades renames into behavior changes, and
gives no way to declare that a function does *not* want ambient
supply. Veb survives under this model only because its shapes
(veb.Result, app receiver) are narrow and stable.

## Option C - Attribute-marked context parameters

Reuse `@[...]` (per the pending RFC
[vlang/rfcs#35](https://github.com/vlang/rfcs/pull/35)) to mark
`@[context]` on parameters (waiting for attributes to land first):

```v
@[context]
fn read_config(alloc &Allocator, path string) !Config { ... }
```

Rejected as the primary transport: attributes are inert data read
at comptime by design, so a runtime behavior (parameter
transport) driven from a declarative attribute mixes models.
It also couples this RFC's availability to the attributes RFC's
landing. It remains listed as an unresolved question whether a
compatibility alias should exist once both are in the tree.

## Option D - Formalized ambient context

Generalize the in-tree prototype
(`vlib/v/profiler/context.v`): `@[ctx] __global thread-local
contexts` and a `with_allocator(alloc) { ... }` construct that
pushes and pops:

```v
with_allocator(alloc) { // pushes on entry, pops on exit
	...
}
```

Rejected as the primary mechanism: it remains mutable thread-ambient
state; the value lives in ambient machinery the type system
cannot see, so it cannot soundly cross `spawn` boundaries, and
nested same-type regions still effectively overwrite each other.
Kept in the list because it is an available *library* idiom
implementable on top of context parameters, not instead of them.

## Option E - Status quo

Keep manual threading everywhere in libraries (Zig-style
allocator passing in all signatures, Go-style `context.Context`)
and keep veb's compiler special case as the only implicit case.
Rejected because it is precisely the problem statement: the
roadmap item stays open, each new framework asks for its own
compiler patch, the thread-local prototype in `vlib/v/profiler`
remains the most powerful tool available, and the ecosystem's
allocator shapes keep diverging.

## Option F - Odin-style universal implicit context

```v
// no declaration anywhere; every proc and every call is ambient
fn read_config(path string) !Config {
	raw := read_bytes(path) // allocates via the ambient context
	return parse_config(raw)!
}
```

The strongest zero-ceremony design: one built-in per-scope `context`
value, implicitly passed to every call, writable per scope. The
universal context struct is shaped like Odin's `runtime.Context`
(one general allocator, a temp allocator, a logger, a random
generator, weakly typed escape slots), and Odin runs this design in
production across its entire core library - every allocation builtin
defaults to the ambient allocator, so third-party libraries
interoperate without opt-in.

Rejected for V, with the debt acknowledged, because:

- every program carries the surface for every callee: hidden
  dependencies are structural, not accidental;
- the calling convention grows an implicit argument on every call,
  a cost hot-path code pays everywhere (Odin's `"contextless"`
  convention exists precisely as the opt-out);
- per-scope copy-on-write snapshots create a documented wall: a
  context update inside a loop never reaches callees (odin-lang/
  Odin#7498), and the official workaround is mutable state behind
  `user_ptr` - the per-call read rule this RFC adopts does not
  have that wall (see the value read semantics section);
- a universal struct cannot anticipate each callee's needs, which
  is why the weakly typed `user_ptr`/`user_index` slots exist as
  the escape hatch; typed context parameters replace those slots
  with named, checked requirements, and each library can add its
  own context type without touching a shared struct;
- default context values live in the runtime implementation
  (the `base` package requires `__init_context`), so program-wide
  context behavior is defined outside the language; declared
  contexts keep all context behavior in V source.

What Odin proves and this RFC keeps: zero-annotation contexts work
at ecosystem scale in a manual-memory language, and the stdlib
defaults are what make it pay for everyone. Both ends land in the
sequenced rollout (future possibilities): the two-region temp-arena
allocation convention, and the inventory of which vlib affordances
could eventually default a resolution through an ambient context -
rather than either arriving as part of a universal mechanism in the
first pass.

## Smaller choices already made (challenge if wrong)

- Plain locals never satisfy context requirements. Supply points
  are only `with` blocks and enclosing context parameters. (This
  is the one rule that stands between an otherwise-ordinary
  mechanism and Scala's `given`/`using` matching, where ambient
  matching against broadly available values caused real
  confusion.)
- Immutable context parameters only, for this RFC. Mutable
  context parameters (`mut ctx`) follow; veb's compiler special
  case stays in place until the general mechanism can express
  it. This RFC does not pretend the veb special case dies
  immediately; it dies when the sequenced migration reaches it.
- Exact type matching after alias normalization, not interface
  satisfaction; experience from Scala shows a wider matching also
  pulls surprise into the matching ID, and the narrower rule can
  be widened later, never pulled back without breaking code
  written on the wider rule.
- One reserved word (`with`) in this RFC. The declaration is in
  the existing bracket group; the explicit per-call supply reuses
  the struct-init `name: value` shape. Nothing else new.
- Nothing in this RFC requires a cross-dependency on the pending
  attributes RFC.

Comparison table:

|                         | A. Declared context params | B. Magic `ctx` name | C. Attribute-marked | D. Ambient globals | E. Status quo | F. Universal context |
|-------------------------|-----------------------------|----------------------|----------------------|---------------------|--------------|-----------------------|
| Declaration             | `[ctx &Allocator]`          | plain `ctx` param    | `@[context]`         | `@[ctx] __global`   | none         | none (built-in)       |
| Explicit supply         | `f[ctx: v]`                 | ordinary argument    | attribute syntax     | push/pop pair       | argument     | awkward (field names) |
| Region supply           | `with v { ... }`            | push/pop pair        | not expressed        | built-in            | manual       | writes in any block   |
| Plain locals supply     | no (deliberate)             | yes (risk)           | no                   | ambient             | n/a          | ambient (always)      |
| Cross-thread safety     | explicit only, enforced     | explicit only        | explicit only        | not usable          | manual       | thread-local copies   |
| Runtime cost            | none                        | none                 | none                 | thread-local global | none         | implicit arg per call |
| New keyword(s)          | 1 (`with`)                  | 0                    | 0 (needs attrs)      | 2+                  | 0            | 0                     |
| Backward compatible     | yes                         | ambiguous            | yes                  | yes                 | yes          | n/a (own ABI)         |
| Kills veb special case  | planned follow-up           | eventually           | eventually           | no                  | no           | no                    |
| Comptime reflection     | later                       | yes                  | via attrs            | n/a                 | yes          | n/a                   |

# Prior art

- **Jai**: `context.allocator` is the closest design in spirit and
  the one referenced in-tree, in
  [`vlib/v/profiler/context.v`](https://github.com/vlang/v/blob/master/vlib/v/profiler/context.v):
  Jai exposes allocation choice through a dynamic per-thread
  context object. This RFC takes Jai's goal (heap choice follows
  scope) and replaces the mutable ambient object with
  compiler-resolved, statically checked edges.
- **Odin**: the systems-language precedent for the whole roadmap
  item, and the design reviewers will compare against first.
  Every scope has an implicit, scope-local `context` value passed
  by pointer to any call whose callee uses the Odin calling
  convention ([overview: Implicit context
  system](https://odin-lang.org/docs/overview/#implicit-context-system)).
  The universal `Context` struct (`base/runtime/core.odin`) carries
  a general allocator, a temp allocator, a logger, a random
  generator, an assertion handler, and weakly typed
  `user_ptr`/`user_index` slots; the allocation builtins (`new`,
  `make`, `append`, `delete`) default the allocator from the
  current context, so every library allocates through the ambient
  one with no opt-in. Writes are copy-on-write per scope, and
  `"contextless"` procedures opt out at the calling-convention
  level. Two of its documented properties shaped Option A's rules
  and Option F's rejection: the [#7498](https://github.com/odin-lang/Odin/issues/7498)
  limitation (a context value updated inside a loop never reaches
  callees; the official workaround is mutable data behind
  `user_ptr`), which the per-call read rule here avoids, and the
  universal-struct uniformity that typed per-context parameters
  replace.
- **Kotlin**: context parameters
  ([docs](https://kotlinlang.org/docs/context-parameters.html))
  declare bracketed `context(name: Type)` on functions and
  properties, resolve by type against the caller's scope,
  disambiguate with `contextOf<T>()` and by passing arguments
  explicitly, supply regionally with `context(v) { ... }`, and
  error on two matching values at the same depth. They are
  still Experimental (opt-in flag) at the time of writing. This
  RFC's Option A is a direct translation, with two deliberate
  differences: matching is exact-type only, and plain locals
  never match (V stays stricter).
- **Scala** `given`/`using`: widely known for the matching
  surface creating the community's "implicit hell" and the
  `given` rework; this RFC's with-block-only supply and
  exact-type matching respond directly to that history.
- **Haskell** implicit parameters (`?x`): runtime dynamic
  scoping, with the standing failure mode that a nearer local
  may silently change which value a deep call resolves to; rule
  supply-here-from-visible-binding-only responds to that mode.
- **Zig**: explicit allocator passing by every signature; shows
  the ergonomic cost of the status quo and why the roadmap asks
  for implicit passing rather than the reverse.
- **Go** `context.Context`: the mainstream method of the
  explicit-transit pattern; threading by hand through every
  layer is familiar pain that this RFC removes by declaration
  rather than by a runtime data structure.
- V itself: veb's checker-inserted `mut ctx Context`, plus the
  three sibling passes that keep it alive, is working precedent
  for the bookkeeping shape on the compiler side; the
  `vlib/v/profiler` prototype is working precedent for the
  allocator payload shape on the library side.

# Unresolved questions

Please comment on these specifically:

1. Block-supply spelling: `with expr { ... }` (recommended)
   versus `with expr;` (to end of block), versus a
   compiler-recognized stdlib function (which avoids the new
   keyword but hides the supply point behind an ordinary call)?
2. Mixed declaration groups: should a function needing both
   generics and contexts be allowed to write them in one group,
   or be required to declare two (`[T][ctx &Allocator]`)? Which
   order reads better in V?
3. Context parameters on methods: is the placement above the
   right spelling for the long term, or should methods be
   prohibited from declaring their own in the first version?
4. Exact type matching only, or should an interface-typed
   context argument accept a satisfying subtype binding?
   Exact-only is recommended.
5. Should context parameters be reflected in comptime function
   metadata in this RFC (`params`, a dedicated list, or neither)?
6. When may lambdas and fn-pointer types declare their own?
   This RFC forbids them to keep the first version simple;
   when is the right follow-up?
7. Mutability follow-up for veb: should it be its own RFC
   (this one does not preempt it)? What is the specific gate for
   withdrawing the veb special case from the checker?
8. Should primitive context types (`int`, `u8`, `bool`) be
   allowed as payloads, or restricted to types any field can
   hold? (Allowed in this draft, though clearly not the natural
   use case.)
9. Should a positional supply form (`read_config[alloc]`) be
   allowed for a single-context callee, or is the named form
   always required?
10. Anything else that should stay out of the first
    implementation besides the `mut` follow-up (e.g. interface
    context params, per-module default contexts, comptime-specialized
    context values)?
11. How should context-taking functions meet FFI? A `@[export]`ed
    (or otherwise externally called) function's context parameters
    are real parameters at the C ABI, so external callers would
    pass them positionally at their declared position; is that the
    whole rule, or should `@[export]` simply forbid bracket
    declarations in the first version? This RFC defines V-internal
    calls only.

# Future possibilities

- Mutable context parameters, the follow-up that completes the
  veb migration and lets `fn_needs_implicit_veb_ctx` and its
  sibling passes be deleted from the checker.
- A canonical `Allocator` in `builtin`, promoted from the
  in-tree profile shape and adopted by `dlmalloc`, `sokol`, and
  friends, making allocation switching a first-class ecosystem
  capability.
- Per-test isolated allocators in the V test runner, so leaks
  and allocation counts become first-class test-assertion
  properties ("this test allocates nothing outside its arena").
- Comptime context plumbing for build-time specialization
  (e.g. `-d`-flag-driven allocator selection without runtime
  branching).
- The cancellation-related context shape in `vlib/goroutines`
  as a second standard consumer: cancellation propagation
  through spawned workers without threading it through every
  `spawn` call manually.
- A two-region allocation convention: a general allocator plus a
  scratch-shaped temp allocator, freed regionally in the
  `free_all`-per-frame style; Odin's design makes the second
  region first-class, and real allocation workloads want both.
- An inventory of which vlib affordances can responsibly default a
  resolution through an ambient context (the way Odin's `new`/
  `make` default to `context.allocator`) - deliberately out of
  scope here, and to be weighed honestly, since V's collections
  are GC-rooted rather than allocator-parameterized, unlike
  Odin's.
