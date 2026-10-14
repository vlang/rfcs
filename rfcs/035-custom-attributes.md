- Topic Name: custom-attributes
- Start Date: 2026-10-12
- RFC PR: [vlang/rfcs#35](https://github.com/vlang/rfcs/pull/35)
- V Issue: N/A (to be created by maintainers on acceptance)

# Summary

Add user-defined, typed attributes to V. A struct marked
with `@[attribute]` becomes an attribute *schema*. The schema
can then be used on functions, structs, enums, fields, and
enum values with call syntax:

```v
@[attribute]
struct Route {
	path   string
	method HttpMethod
}

@[Route('/index', method: .get)]
fn index() {}
```

Custom attributes are inert at runtime. They are readable
at compile time as *typed* values, so libraries can react
to them without compiler magic. A maintainer described
the intended direction informally as "C#-style" attributes,
and this RFC follows that steer.

This RFC is intentionally a *request for comments*: it
presents the candidate designs side by side so readers can
compare them, and recommends one.

# Motivation

- The [V 0.6 roadmap](https://github.com/vlang/v/blob/master/ROADMAP.md)
  lists "Custom attributes" as an unchecked item.
- Today attribute names are an open, unchecked namespace.
  Anyone can write `@[anything]`, and library authors must
  parse raw strings by hand at compile time.
- The `vweb` framework motivated the original proposal
  ([vlang/v#11732](https://github.com/vlang/v/discussions/11732),
  also filed as
  [vlang/v#7014](https://github.com/vlang/v/issues/7014)):
  route tables need typed, validated declarations instead
  of compiler-specific handling.
- The syntax groundwork is done:
  [vlang/v#25502](https://github.com/vlang/v/issues/25502)
  ("new syntax for attributes", completed) added the
  `@[name(...)]` call form to the parser. What is missing
  is the *meaning*: schemas, validation, and typed access.
- [vlang/v#15797](https://github.com/vlang/v/issues/15797)
  ("attribute name is not checked") shows the validation
  half of this is wanted on its own.
- The [syntax discussion](https://github.com/vlang/v/discussions/23445)
  collected prior art (C#, Python, Swift, Go tags) and the
  idea of restricting which declarations an attribute may
  sit on (Java-style targets).

Expected outcome: close the roadmap item with a design the
community has compared and approved, then implement it.

# Guide-level explanation

Think of a custom attribute as a small typed form that the
programmer fills in and attaches to a declaration. The
compiler checks the form; comptime code reads it.

## Declaring an attribute

A struct marked with `@[attribute]` is an attribute schema,
not an ordinary struct:

```v
enum HttpMethod {
	get
	post
}

@[attribute]
struct Route {
	path   string
	method HttpMethod
}
```

The marker reserves the name `Route` for attribute use.
An attribute struct has limits (the reference section
explains why): no `mut` fields, no embedding, and it can
never be instantiated with `Route{...}`, embedded, or used
as a generic type argument.

## Using an attribute

Attach it with the existing `@[...]` syntax, using the
call form for arguments:

```v
@[Route('/index', method: .get)]
fn index() {
	// ...
}
```

Positional arguments bind to fields in declaration order;
named arguments bind by field name. This also works on
structs, struct fields, enums, and enum values:

```v
struct Cfg {
	user_name string @[json: 'userName'; required]
}

@[Route('/submit', method: .post)]
fn submit() {}
```

Multiple attributes group with `;`, as today:
`@[required; json: 'x']`.

## What the compiler checks

Arguments are checked against the schema. Unknown names
produce a *warning*, not an error: existing code already
uses arbitrary `@[...]` names, so rejecting them outright
would break working programs. The warning names the
suspected typo and points at schema declaration; it
becomes an error in a later release (timeline below):

```v
@[Rout('/index')] // warning: unknown attribute `Rout`
fn index() {}

@[Route('/index', method: .put)] // error: `put` is not a value of HttpMethod
fn other() {}
```

Proposed sample messages (wording open to bikeshedding):

- `` warning: unknown attribute `Rout`. Did you mean `Route`?
  Unvalidated attributes are deprecated; declare a schema
  with `@[attribute]` or drop the attribute. ``
- `` attribute `Route` expects 1 positional argument, got 2 ``
- `` unknown field `metho` in attribute `Route` ``
- `` cannot initialize struct `Route` marked with `@[attribute]` ``
- `` attribute `Route` cannot be used as a type argument ``

## Reading an attribute at compile time

Today `$for a in Fn.attributes` yields flat `VAttribute`
values with `name`/`has_arg`/`arg`/`kind`. Under this RFC,
an attribute whose name matches a schema instead yields
that struct, fully typed:

```v
$for attr in index.attributes {
	$if attr is Route {
		println('route: ${attr.path} ${attr.method}')
	}
}
```

(`$if attr is Route` is the natural comptime type test;
its exact spelling is an unresolved question below.)
Builtin attributes keep yielding `VAttribute`, so existing
comptime code keeps working.

Struct fields and enum values are the one place that does
not follow this convention today: in `$for` loops they
expose raw strings via `.attrs` (`[]string`, e.g.
`field.attrs.contains('skip')` in `vlib/json2`), not
`VAttribute`. Under this RFC they gain the same typed
`.attributes` view as declarations, and the stringly
`.attrs` is deprecated (kept working, removal after 1.0;
timeline below). New comptime code should use
`.attributes`; `json2`-style manual parsing migrates to
it.

A schema may also declare methods, which comptime code can
call like any other method call. This is how a `vweb`-style
framework builds its route table from declarations instead
of compiler magic (no new comptime method machinery is
proposed in this RFC):

```v
@[attribute]
struct Route {
	path   string
	method HttpMethod
}

fn (r Route) key() string {
	return '${r.method}:${r.path}'
}
```

## Where an attribute may sit

C# has `AttributeUsage`; Java has `@Target`. Following the
syntax discussion, a schema may restrict its targets:

```v
@[attribute: 'fn'; attribute: 'struct']
struct MyAttr {
	name string
}
```

Using `@[MyAttr{}]` on a struct field is then a compile
error. A schema without a target list may sit on any
declaration that accepts attributes today.

## What does not change

- Builtin attributes (`@[heap]`, `@[packed]`, `@[required]`,
  `@[deprecated(...)]`, `@[if flag ?]`, ...) are untouched.
- `@[if flag ?]` keeps its guard meaning and is not
  exposed as an attribute.
- The `@[...]` grouping syntax stays; no new `@attr(...)`
  front syntax is introduced.
- Compatibility is warn-first, not break-first: unregistered
  attribute names and legacy field `.attrs` keep compiling
  with a deprecation warning. Nothing that compiles today
  stops compiling under this RFC.

# Reference-level explanation

## Declaration

`@[attribute]` on a struct registers a schema: an ordered
field list with types and optional target restrictions.
Schema structs:

- must not have `mut` fields;
- must not embed other structs;
- cannot be initialized, embedded, cast to/from, or used
  as a generic type argument;
- may declare ordinary methods; comptime code may call
  them under the existing comptime call rules (no special
  comptime-method machinery in this RFC);
- are resolved by exact name only: `@[Route]` requires a
  schema literally named `Route`. (Whether `@[Route]` may
  also resolve a schema named `RouteAttribute`, C#-style,
  is an unresolved question.)

## Argument binding

The call form is `@[Name(pos1, key: v2, ...)]`. Binding
rules:

- Positional arguments bind left to right to schema
  fields. Mixing positional after named is an error.
- Named arguments bind by field name. Duplicates and
  unknown names are errors.
- Missing fields are errors unless the field declares a
  default value.
- Supported field types in this RFC: `string`, integer
  types, `bool`, and enums. Nested structs are out of
  scope (see future possibilities).
- Literal kinds keep working as today (`'str'`, `123`,
  `true`), now additionally type-checked.

The single-argument `@[key: value]` form stays sugar for
single-field schemas and builtins.

## Targets

Target restrictions reuse attribute syntax on the schema:

```v
@[attribute: 'fn'; attribute: 'struct']
struct Doc {
	text string
}
```

Allowed target names mirror declaration kinds: `'fn'`,
`'struct'`, `'enum'`, `'field'`, `'value'` (enum value),
`'interface'`, `'module'`. Omitting the list allows all.

## Name resolution across modules

Schemas live in modules, so two modules can declare the
same schema name (`json.Skip` vs `orm.Skip`). Resolution
follows V's existing type rules — no new ambiguity error
and no import-order rule:

- Builtin attributes match first, case-sensitively.
- A bare `Name` matches a schema in the current module
  only.
- A dotted `mod.Name` matches schema `Name` in imported
  module `mod`.
- Anything else is the unknown-attribute warning, which
  suggests the qualified forms when same-named schemas
  exist in imports.

Consequences: with both `json` and `orm` imported, bare
`@[Skip]` warns (there is no current-module `Skip`);
`@[json.Skip]` and `@[orm.Skip]` both work, including
together on one field: `@[json.Skip; orm.Skip]`.

Dotted names are new syntax in attribute position: today
a dot splits `@[foo.Bar]` into two attributes (`foo` +
`Bar`). The parser must accept `mod.Name` (and
`mod.Name(args)`, binding like the bare call form) as a
single attribute piece.

## Comptime reflection

When an attribute matches a registered schema, the
comptime lowering materializes the schema struct instead
of `VAttribute`. Member access is typed: `attr.path` is a
`string`, `attr.method` is an `HttpMethod`. For builtin or
unregistered attributes, iteration yields `VAttribute`
exactly as today, so the current reflection contract
(`name`/`has_arg`/`arg`/`kind`, see `comptime_attribute_selector_test.v`)
is preserved.

Because some members exist only on some schemas, member
resolution inside an `attributes` loop accepts the union
of all registered schemas' fields plus `VAttribute`'s
four members. Code that reaches a member the current
instance cannot have must narrow with `$if attr is Route`
first; otherwise it is a compile error.

The same typed view is added for struct fields and enum
values: `field.attributes` yields schema structs or
`VAttribute`, exactly like declarations. Their legacy
`.attrs` (`[]string`) keeps working but is deprecated;
see the migration timeline question below.

## Implementation notes

This subsection is for compiler reviewers; it sketches
where the work lands in the V3 flat-AST compiler. If the
RFC is accepted, an implementation plan with exact diffs
follows.

- **Parser** (`vlib/v/parser/parser.v`): the call form is
  parsed today but flattened into `Name` + `Name_arg: value`
  strings (`parse_field_attrs_with_kinds_mode`, around the
  `p.tok == .lpar` branch). The structured pieces
  (argument order, names, literal kinds) must survive into
  the `@attributes:<decl_id>` directive payload. The
  directive payload is `[]string` and is serialized by
  the module cache, so the structured form is encoded
  into that list with an unambiguous escaped shape; the
  legacy string form is kept for builtins and for `vfmt`.
- **Registration** (`vlib/v/types/checker.v`, struct-decl
  pass): structs carrying `@[attribute]` register a
  schema map (name to ordered fields and types), next to
  the existing struct registration.
- **Validation**: a new pass modeled on `check_export_attrs`
  checks every attribute piece on declarations, fields,
  and enum values. Unknown names (not builtin, not
  registered) are *warnings* with a migration message, not
  errors; schema arguments are checked for count, names,
  and types (hard errors); target restrictions are
  enforced per declaration kind (hard errors). Bans on
  initializing, embedding, and generic use of schema
  structs hook the existing struct-init and type-argument
  checks.
- **Comptime** (`vlib/v/transform/comptime.v`,
  `comptime_attribute_metas_from_raw`, `make_attribute_literal`;
  `vlib/v/gen/c/reflection.v`, `reflection_attributes_array`):
  schema-matching attributes materialize the schema
  struct; everything else keeps the `VAttribute` path.
  Checker support in `checker_comptime.v` for the union
  member resolution and `$if attr is Schema` narrowing.
- Nothing in this design touches `vfmt` output shape:
  attribute source text is preserved and re-emitted as
  written.

# Drawbacks

- New comptime surface area: schemas, union member
  resolution, and narrowing add real checker complexity.
- Union member resolution in `attributes` loops is
  permissive by construction; misuse surfaces as a
  "narrow first" error rather than a precise one.
- Escaped-string storage of structured arguments is a
  workaround for the flat `[]string` payload, not a
  clean data model.
- Exact-name resolution deviates from C#, where `@[X]`
  also finds `XAttribute`.
- Restricted schema structs (no `mut`, no embed, limited
  field types) may feel arbitrary; each ban needs a clear
  error message.
- `vweb`/`vpm`-style consumers that parse raw attribute
  strings today must migrate to the typed form.
- `.attrs` (`[]string`) deprecation touches real comptime
  code (`vlib/json2` and friends); the migration is
  mechanical (`.contains('x')` to a typed test) but wide.
- Warning-first validation means a long tail of warnings
  in codebases with ad-hoc attributes before the
  error flip; the flip itself is a scheduled break.

# Rationale and alternatives

Commenters: this is the section to react to. Please say
which option you prefer (A–E) and why, especially if you
disagree with the recommendation.

## Option A — Typed schema structs (recommended)

`@[attribute] struct Route {...}`, used as
`@[Route('/index', method: .get)]`, per the guide section.
Recommended because: no new keyword; reuses the `@[...]`
syntax programmers already know; gives type-checked
arguments and targets; matches the maintainer's C# steer;
is backward compatible by construction (unregistered
names and legacy `.attrs` warn instead of erroring, so
*every* program that compiles today keeps compiling).

## Option B — New `attribute` declaration keyword

```v
attribute Route(path string, method HttpMethod)

@[Route('/index', .get)]
fn index() {}
```

Shorter declarations and a dedicated concept. Rejected in
this RFC because it adds a reserved word to a language
that prizes a small keyword set, while buying nothing
Option A cannot express.

## Option C — Go-style string tags

```v
struct Cfg {
	user_name string @[tag: 'json:"userName"']
}
```

Familiar to Go programmers and trivial to parse. Rejected
because everything stays a string: no argument names or
types are checked, targets cannot be restricted, and
comptime code goes back to manual string parsing — the
exact pain this RFC exists to remove.

## Option D — Python/Swift behavior wrappers

```v
@logged
fn f() {}
```

where `@logged` transforms or wraps the declaration.
Rejected: V attributes are compiler instructions and
metadata, not code transforms. Behavior wrappers need
macro-grade machinery and a runtime story V does not
have; #23445 commenters also noted this mismatch.

## Option E — Status quo

Keep compiler-specific builtin attributes plus hand-rolled
raw-string parsing in libraries. Rejected because it is
the problem statement: it leaves the namespace unchecked
(#15797), forces every library to re-parse strings, and
keeps framework behavior as compiler magic (#11732).

## Smaller choices already made (challenge if wrong)

- `@[...]` only, no new `@attr(...)` front form: groups
  are needed for struct/enum fields, and a bare
  `@attr()` form interacts badly with the existing
  syntax history (see #25502's thread).
- Exact-name resolution only, no `XAttribute` suffix
  fallback: simpler lookup, one obvious spelling. Early
  discussion feedback agrees; the suffix fallback stays
  listed as an unresolved question in case that changes.
- Cross-module schemas resolve V-strict: bare names see
  the current module only; imports require `mod.Name`
  (new dotted attribute syntax, since dots split today).
- Validation is warn-first for unregistered names
  (hard errors only for schema argument and target
  misuse): rejecting unknown names outright would break
  existing code, per early discussion feedback.
- Escaped-string encoding for structured arguments:
  keeps the flat-AST payload and module cache formats
  stable. A real structured payload is the alternative
  if reviewers prefer it.

## Comparison table

|                       | A. Schema structs | B. `attribute` keyword | C. Go tags | D. Wrappers | E. Status quo |
|-----------------------|-------------------|------------------------|------------|-------------|---------------|
| Declaration example   | `@[attribute] struct Route` | `attribute Route(...)` | tag string | `@logged` | builtin only |
| Use example           | `@[Route('/i', method: .get)]` | `@[Route('/i', .get)]` | `` `json:"x"` `` | `@logged fn f()` | `@[get]` magic |
| Typed arguments       | yes               | yes                    | no         | n/a         | no            |
| Named arguments       | yes               | yes                    | map lookup | n/a         | `key: value`  |
| Target restrictions   | yes               | yes                    | no         | no          | no            |
| Comptime data         | typed struct      | typed struct           | strings    | transform   | raw strings   |
| New keywords/syntax   | none              | new keyword            | new syntax | new model   | none          |
| Backward compatible   | yes               | mostly                 | yes        | no          | yes           |
| Compiler cost         | medium            | medium                 | low        | high        | none          |

# Prior art

- **C#**: `class X : Attribute`, usage `[X(1, Named = 2)]`,
  `[AttributeUsage(...)]` targets, `[X]` resolving
  `XAttribute`. The direct model for Option A; the
  suffix fallback and `AttributeUsage` are incorporated
  here as "targets" and an open question.
- **Java annotations**: `@Target`/`@Retention` map
  cleanly onto the target-restriction part; retention
  policy has no V equivalent (everything is comptime).
- **Rust**: `#[derive(...)]` and procedural macros. Proc
  macros are deliberately more powerful than this RFC:
  V does not need code-generating plugins to type its
  attributes.
- **Python decorators / Swift wrappers**: transform
  declarations at runtime/compile time. Wrong model for
  V, where attributes are inert metadata consumed at
  comptime.
- **Go struct tags**: `reflect.StructTag.Get`. Works,
  but stringly-typed; V's `$for` comptime reflection
  can do better with real types.
- V itself: `@[deprecated(msg: ...)]`, `@[json: 'x']`,
  `@[if flag ?]`, and the `$for x in T.attributes`
  reflection show the inplace conventions this RFC
  extends rather than replaces.

# Unresolved questions

Please comment on these specifically:

1. Should `@[Route]` also resolve a schema named
   `RouteAttribute` (C# behavior), or is exact-name-only
   right for V?
2. Data-only schemas, or methods allowed (needed for
   the `vweb` route-table use case)?
3. Should schema fields support default values, and if
   so, which constant expressions are allowed?
4. Enforce CamelCase for schema names to distinguish
   them from lowercase builtins, or leave it to style?
5. What is the exact spelling of the comptime type test
   (`$if attr is Route`, something else)?
6. Should the flat AST gain a real structured payload
   for attribute arguments instead of the escaped-string
   encoding sketched here?
7. Migration timelines (proposed; challenge if wrong):
   unknown-name warning becomes an error one minor
   release after schemas ship; legacy field `.attrs`
   is removed after 1.0. Too fast, too slow?
8. Should a bare `@[Skip]` also search imported modules
   when the current module has no `Skip`, or stay
   V-strict (qualify)? Recommended: V-strict, matching
   type resolution.
9. Anything in this RFC that should explicitly stay out
   of scope for the first implementation?

Early discussion signals (vlang/v#30239): exact-name-only
is preferred over the `XAttribute` suffix fallback, and
schema methods should behave like ordinary methods. Both
are reflected above; speak up if you disagree.

# Future possibilities

- Derive-style comptime hooks over schema instances.
- Migrating `vweb` route registration (and similar
  `@[get]`-style consumers) onto typed attributes.
- `vdoc` rendering of schema documentation.
- Wider field types (nested schemas, arrays) once the
  core design is proven.
- Runtime reflection of attributes, Go-`reflect`-style,
  if a use case ever demands it.
- Smarter "did you mean" suggestions for unknown names.
