- Topic Name: implicit-contexts
- Start Date: 2026-10-26
- RFC PR: [vlang/rfcs#36](https://github.com/vlang/rfcs/pull/36)
- V Issue: N/A (to be created by maintainers on acceptance)

# Summary

Add a universal implicit `context` to V, passed automatically to
ordinary calls in the Odin/Jai sense, with scoped overrides.
Every ordinary function has access to a well-defined `Context`
with useful defaults; ordinary calls, methods, and compatible
indirect calls forward the current context automatically. An
override affects calls within its region; leaving that region
restores the enclosing selection.

```v
// no declaration anywhere; ordinary helpers forward automatically
fn consume() {
	// uses context.allocator
}

fn helper() {
	consume() // forwards the caller's context, no annotation
}

fn run(alloc &Allocator) {
	with alloc {
		helper() // consume() observes alloc
	}
}
```

Per-call explicit control remains available:

```v
with alloc {
	config := read_config('conf.json')!
}
// explicit single-call override:
config := read_config[allocator: alloc]('conf.json')!
```

The first standard use case is the roadmap's: allocation contexts.
Today only `veb` has implicit context passing, and that mechanism is
hardcoded into the checker for veb's shapes. This RFC generalizes the
passing convention itself so any library participates without opt-in
plumbing, and so the compiler stops accumulating per-framework
versions of the same passthrough.

Declared, type-matched implicit parameters (the former Option A,
a Kotlin-style translation) are explicitly deferred: they may be
proposed independently as a separate future RFC for typed
implicit parameters. They are not the mechanism of this RFC.

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

## What the context is

Every ordinary V function has access to a well-defined `context`
with useful defaults. No declaration is required to receive it
and no signature change is required to forward it: ordinary
calls, methods, and compatible indirect calls forward the
current context automatically.

Required contract:

| Area | Behavior |
|------|----------|
| Availability | Ordinary functions observe a valid context. |
| Propagation | Callees receive the caller's context unless overridden. |
| Scoped overrides | An override affects its region; exit restores enclosing. |
| Allocation participation | Listed allocation ops default to the selected allocator. |
| Ownership | Existing allocations retain their allocator for grow/free. |
| Boundaries | Defined for entry, `spawn`, foreign calls, contextless code. |
| Explicit control | Per-region and per-call overrides stay available. |

```v
fn read_config(path string) !Config {
	raw := read_bytes(path) // same ambient context, no annotation
	return parse_config(raw)!
}
```

Adding an ordinary helper between an override and an allocation
preserves behavior. This is the central Jai/Odin property.

## The Context value

```v
pub struct Context {
pub mut:
	allocator      &Allocator
	temp_allocator &Allocator
	logger         &Logger
}
```

Defaults are provided by the runtime (system allocator, default
logger).

## Entry points and runtime construction

Following Zig's `std.process.Init` precedent (entry boundary
bundle only, not a forwarding model):

- Program entry constructs the default `Context` before user
  code runs. An explicit entry form (`fn main(ctx Context)`)
  may observe it; plain `fn main()` observes the ambient
  default implicitly.
- A minimal context covers early/tool paths where the full
  runtime is not ready yet; document which fields are valid
  before `main`.
- Foreign callbacks observe a defined default context and
  cannot inherit a caller scope implicitly.
- `spawn` copies the parent context at spawn time (no implicit
  sharing afterwards).
- Lifetime: distinguish the process-lifetime backing store
  from scoped arenas. The acceptance example covers scope
  exit, but implementations must state which allocator is
  process-lifetime versus scoped.

Functions marked `@[contextless]` receive no implicit context
and cannot observe ambient overrides; they keep their existing
signatures.

## Explicit control

A call may override context fields by name for that call only:

```v
alloc := &Allocator{ ... }
config := read_config[allocator: alloc]('conf.json')!
```

Explicit supply overrides the ambient context for that call.
It is also the disambiguator of last resort.

## Supplying a context for a region

The `with` block evaluates its expression once at block entry
and overrides the corresponding `Context` field for the whole
block. Leaving the block restores the enclosing selection.

```v
with alloc {
	// both calls observe alloc as context.allocator:
	cfg := read_config('conf.json')!
	out := render_scene(scene)!
}
```

Where blocks nest, the innermost `with` of the same field type
wins, exactly the way a local shadows an outer local:

```v
with test_alloc {
	for i in 1 .. runs + 1 {
		with per_run_alloc {
			// context.allocator is per_run_alloc here
			run_seed(i)
		}
	}
	// context.allocator is test_alloc again out here
}
```

To supply several fields over one region, nest:

```v
with alloc {
	with logger {
		// allocator binds to alloc, logger to logger
		node := build_tree(data)!
	}
}
```

Scoped reassignment uses a nested block or an explicit
statement, not silent re-reads of the entry expression:

```v
with warmup_arena {
	for i in 1 .. runs + 1 {
		if i >= warmup_runs {
			with steady_arena {
				run_seed(i)
			}
		} else {
			run_seed(i)
		}
	}
}
```

## Propagation through ordinary calls

Ordinary functions forward the current context automatically.
No declaration is required on intermediaries:

```v
fn consume() {
	// uses context.allocator
}

fn helper() {
	consume() // forwards the caller's context
}

fn run(alloc &Allocator) {
	with alloc {
		helper() // consume() observes alloc
	}
}
```

Helper chains share the context of whichever function invoked
the chain, and inserting a hop in the middle is a no-impact
change. This acceptance property is required.

## Ambiguity

Two `with` bindings for the same context field at the same
scope depth are an error; pass explicitly instead. Nesting is
not ambiguity: the inner binding shadows the outer one.

```text
error: two matching context values of type `&Allocator` are in
scope; pass one explicitly with `read_config[allocator: ...]`.
```

Proposed sample messages (wording open to bikeshedding):

- `` error: two matching context values of type `&Allocator` are
  in scope; pass the context argument explicitly. ``
- `` error: `spawn` copies the parent context at spawn time; it
  does not share later overrides. ``

## What does not change

- `veb` keeps working exactly as today, special case included,
  until it migrates onto the ambient context (timeline below).
- Named arguments, default values, `?`/`!` handling, variadic
  parameters, and comptime reflection keep their current meanings.
- `@[contextless]` functions keep their existing signatures and
  never observe ambient overrides.

# Reference-level explanation

## Calling convention

- Every ordinary function takes an implicit `context` parameter
  (a pointer to `Context`). The compiler selects the value at
  compile time; the value travels at runtime like any argument.
- Defensible claims only: no runtime search, no required
  thread-local stack, cost equivalent to the corresponding
  explicit arguments. Functions marked `@[contextless]` keep
  their existing signatures.
- Odin implements the same property with an implicit argument;
  it needs no runtime type search. The trade-off to weigh is
  one common context argument versus selectively added typed
  arguments, with inlining qualified on hot paths.

## Binding rules

1. Ordinary calls forward the current context automatically.
   Intermediaries need no annotation (see `helper` example).
2. A `with` block evaluates its expression once at entry,
   overrides the matching `Context` field for its region, and
   restores the enclosing value on exit. Inner `with` of the
   same field shadows outer `with`; same-depth duplicates are
   an error.
3. Per-call override (`f[allocator: expr]`) replaces the field
   for that call only. `expr` is evaluated when the call
   executes.
4. Function values use invocation context: obtaining a value
   under allocator A and invoking it under allocator B uses B.
   Capturing a context at creation is a separate explicit
   operation (closure/environment adapter) with ordinary
   lifetime rules; a captured short-lived arena must not
   outlive its use. FFI callbacks are a separate boundary with
   explicitly defined context (default or contextless).
5. `spawn` copies the parent context at spawn time. Later
   overrides in either side are not shared. Program entry,
   foreign entry, and `@[contextless]` boundaries are defined
   per the Context-value section.
6. Deferred functions registered inside a `with` block observe
   the block's override for calls they make while it is active,
   following normal scoped-restore rules.

## Value read semantics

- A `with` block evaluates its expression once at block entry.
  It does not re-evaluate per resolving call. `with
  acquire_allocator()` therefore acquires once, not once per
  call. Refactoring the body does not change acquisition count.
- A stable value with explicit scoped updates is the rule for
  scoped allocation: the region's allocator is fixed unless a
  nested `with` overrides it.
- Explicit per-call supply (`f[allocator: expr]`) reads `expr`
  when the call executes.

## Runtime mechanism

- Resolution is compile-time (which value to pass is decided
  statically). Transport is runtime: the context pointer travels
  as an implicit argument, cost equivalent to the corresponding
  explicit arguments.
- No runtime search for a matching context and no required
  thread-local context stack.
- Odin uses the same shape: the compiler obtains the context
  pointer when emitting an ordinary call. The trade-off to
  document is one common context argument versus selectively
  added typed arguments.
- A callee reached over several hops receives the invocation
  context. Nothing re-resolves per frame beyond normal
  forwarding.
- Ownership: context arguments follow the same parameter-move
  rules as written-out arguments. The existing veb test
  (`test_ownership_veb_implicit_context_arg_moves`) already
  anchors the same semantic for the veb-inserted `ctx`.
- Checker bookkeeping is per call site, computed during the
  existing scope walk, so it is compatible with the parallel
  checker.

## The allocation contract

This RFC includes the allocator behavior; it is not deferred.

Participation: array creation and growth, map creation, string
allocation, explicit heap allocation, and allocating stdlib
functions default to `context.allocator`. The design also states
its relation to V memory modes (GC / autofree / `-gc none`):
where collection is GC-rooted, the context selects the backing
arena for new storage where the implementation supports it;
existing GC semantics are otherwise unchanged and are called
out per operation in implementation.

Ownership: choosing an allocator for new storage and retaining
the allocator that owns existing storage are separate. An
array created while A is active and later grown or freed while
B is active uses its retained allocator for growth and release,
following Odin dynamic-array behavior (`reserve` uses the
retained allocator once set; `delete` frees through
`array.allocator`). Merely consulting the current context at
every operation is insufficient and is not the rule.

Acceptance example (required):

1. Establish allocator A for a scope (`with A`).
2. Call an ordinary helper that calls another ordinary helper
   or callback, with no context annotations in that chain.
3. Create a collection through the supported allocation API.
4. Leave the override scope.
5. New allocations use the enclosing allocator, while the
   existing collection still grows/frees with A.

Staging is allowed for implementation, but the contract above
is part of the design.

## veb migration

## veb migration

Veb adopts the ambient context in source. The veb `Context`
becomes a projection of the ambient `Context` (or a field of
it) rather than a hardcoded checker special case:

```v
// before (special cased in the checker):
pub fn (app &App) index() veb.Result {
	return ctx.text('ok')
}

// after: ordinary function observing the ambient context
pub fn (app &App) index() veb.Result {
	return context.logger.text('ok')
}
```

Once the source form is in wide use, `fn_needs_implicit_veb_ctx`
and its three sibling passes become redundant and are deleted.

## Implementation notes

For compiler reviewers; if the RFC is accepted, an implementation
plan with exact diffs follows.

- **Parser** (`vlib/v/parser/parser.v`): `with` is a new block
  statement with exactly one initial sub-expression, evaluated
  once at entry with scoped restore on exit.
- **Checker** (`vlib/v/types/`): every ordinary function carries
  the implicit context; forwarding is automatic. Same-depth
  duplicate `with` for one field is an error.
- **cgen / backends**: emit the implicit context argument (one
  pointer). `@[contextless]` functions emit no such argument.
- **Transform and comptime**: context is exposed to comptime
  function metadata only as the implicit convention requires;
  details in unresolved questions.
- **Dynamic backends and the interpreter**: same forwarding;
  no thread-local lookup on the hot path.

# Drawbacks

- `with` is a new reserved word; V's reserved-word budget is
  deliberately small. The keyword earns its place by being
  greppable and unambiguous, but it is a cost.
- Implicit flow is exactly that: not every input of every call
  appears at the call site. V's design culture is explicit; this
  RFC argues the Jai/Odin goal requires automatic forwarding,
  and the trade is scoped overrides plus explicit per-call
  control, but the trade should be called out and weighed.
- Same-field nested `with` blocks shadow rather than merge; two
  libraries scoping the same field over overlapping regions
  must be mutually aware at the composition point.
- Calling convention grows an implicit argument on every
  ordinary call; `@[contextless]` exists as the opt-out, and
  hot-path cost must be qualified with inlining data, not
  asserted as zero.

# Rationale and alternatives

Commenters: this RFC now recommends Option F. Option A is no
longer the primary design; it is retained below as a separate
future typed-implicits proposal, independent of this RFC.

## Option F - Universal implicit context (recommended)

```v
// no declaration anywhere; every proc and every call is ambient
fn read_config(path string) !Config {
	raw := read_bytes(path) // allocates via the ambient context
	return parse_config(raw)!
}
```

Recommended because it delivers the stated Jai/Odin goal:
ordinary helpers forward automatically, scoped overrides affect
their region, and allocation participation plus ownership are
specified. One common context argument replaces selectively
added typed arguments; `@[contextless]` is the opt-out.

## Option A - Declared context parameters (future separate proposal)

Formerly recommended; now explicitly deferred. Bracket
declaration (`fn f[ctx &Allocator]`), `with` supply, enclosing
declarations, exact-type matching; Kotlin-style translation.

Retained only as a possible independent follow-up for general
typed implicit parameters. It is not the mechanism of this
RFC, and adopting it later must be an explicit decision to
pursue a different feature from the Jai/Odin model. It does
not deliver automatic forwarding through unannotated helpers
without added inference rules, and it leaves allocation
behavior unchanged by design.

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
implementable on top of the ambient context, not instead of it.

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

See recommendation above. Prior rejection reasons are withdrawn
as primary objections; costs are documented as trade-offs
(one implicit argument per ordinary call, `@[contextless]`
opt-out, scoped-restore discipline) rather than rejections.

What Odin proves and this RFC adopts: zero-annotation contexts
work at ecosystem scale, and stdlib defaults make it pay for
everyone. The two-region temp-arena convention and the vlib
affordance inventory are part of this RFC's allocation
contract, not a later pass.

## Smaller choices already made (challenge if wrong)

- `with` evaluates once at entry with scoped restore. No
  per-call re-read of the entry expression.
- Inner `with` of the same field shadows outer `with`;
  same-depth duplicates are an error resolved by explicit
  per-call supply.
- Invocation context for function values; capture is explicit
  with ordinary lifetime rules.
- One reserved word (`with`) in this RFC. Explicit per-call
  supply reuses the struct-init `name: value` shape.
- Nothing in this RFC requires a cross-dependency on the pending
  attributes RFC.

Comparison table (primary column is F; A is a future separate
proposal, not a competing primary):

|                         | F. Universal context (primary) | A. Declared params (future) | B. Magic `ctx` | C. Attr-marked | D. Ambient globals | E. Status quo |
|-------------------------|--------------------------------|-----------------------------|----------------|----------------|--------------------|--------------|
| Declaration             | none (built-in)                | `[ctx &Allocator]`          | plain `ctx`    | `@[context]`   | `@[ctx] __global`  | none         |
| Explicit supply         | `f[allocator: v]`              | `f[ctx: v]`                 | ordinary arg   | attr syntax    | push/pop           | argument     |
| Region supply           | `with v { ... }` (once, scoped)| `with v { ... }`            | push/pop       | not expressed  | built-in           | manual       |
| Forwarding              | automatic                      | declared-only               | implicit       | implicit       | ambient            | manual       |
| Cross-thread            | copy at spawn                  | explicit only               | explicit only  | not usable     | manual             | manual       |
| Runtime cost            | implicit arg per call          | explicit-arg equiv          | explicit-equiv | explicit-equiv | thread-local       | none         |
| New keyword(s)          | 1 (`with`)                     | 1 (`with`)                  | 0              | 0              | 2+                 | 0            |
| Backward compatible     | `@[contextless]` opt-out       | yes                         | ambiguous      | yes            | yes                | yes          |
| Kills veb special case  | yes (projection)               | planned follow-up           | eventually     | eventually     | no                 | no           |

# Prior art

- **Jai**: Blow describes an implicit context pointer carrying
  facilities such as the allocator and logger, with allocator
  changes affecting downstream code using that mechanism. This
  RFC follows that pointer-passing shape, not a per-thread
  global. Do not conflate it with the mutable thread-local
  prototype in `vlib/v/profiler/context.v`.
- **Odin**: the systems-language precedent for the roadmap item.
  Every scope has an implicit, scope-local `context` value passed
  by pointer to calls using the Odin calling convention. The
  universal `Context` struct carries a general allocator, a temp
  allocator, a logger, and related slots; allocation builtins
  default to the current context, so libraries interoperate
  without opt-in. Calling convention is part of procedure-type
  compatibility. Corrections applied in this revision:
  context assignment creates/updates the scoped context and
  subsequent calls observe it (no per-loop wall is claimed
  here); `new`/`make` use the ambient allocator for new storage
  while dynamic-array growth and `delete` use the retained
  `array.allocator`. Ownership retention is therefore specified,
  not grouped as ambient.
- **Kotlin**: context parameters declare bracketed
  `context(name: Type)`, resolve by type, and error on two
  matches at the same depth. Retained here only as the model
  for the deferred Option A separate proposal, not as the
  mechanism of this RFC.
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

1. Block-supply spelling: `with expr { ... }` (recommended,
   single evaluation with scoped restore) versus alternatives.
2. `Context` fields: allocator, temp allocator, logger — what
   else belongs in v1, and what stays out?
3. `@[contextless]` spelling and its interaction with generics,
   methods, closures, and function types.
4. Interface-typed context fields: exact-type only or
   interface satisfaction?
5. Comptime reflection for the implicit context.
6. FFI: `@[export]`ed functions are contextless by default or
   take an explicit context positionally — which rule for v1?
   Foreign callbacks observe a defined default context.
7. `spawn` copy semantics and cancellation propagation.
8. Memory-mode interaction: precise per-operation behavior
   under GC / autofree / `-gc none`.
9. Per-call override spelling (`f[allocator: v]`) and whether a
   positional single-field form is allowed.

# Future possibilities

- Option A (declared typed implicit parameters) as a separate
  RFC, if general typed implicits prove useful independently.
- A canonical `Allocator` in `builtin`, promoted from the
  in-tree shape and adopted by `dlmalloc`, `sokol`, and friends.
- Per-test isolated allocators in the V test runner.
- Comptime-driven allocator selection without runtime branching.
- Cancellation propagation through spawned workers.
- Two-region (general plus scratch temp arena) convention.
