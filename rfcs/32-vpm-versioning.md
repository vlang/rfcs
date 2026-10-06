- Topic Name: `vpm_versioning`
- Start Date: 2026-10-03
- RFC PR: [vlang/rfcs#32](https://github.com/vlang/rfcs/pull/32)
- V Issue: [vlang/v#29360](https://github.com/vlang/v/issues/29360)

# Summary

Give vpm a notion of a *dependency constraint*, and a resolver that turns
constraints plus the available tags into one chosen version per module.

This is deliberately **not** a lockfile proposal.
[vlang/v#29250](https://github.com/vlang/v/issues/29250) is, and it now has an
open implementation as [vlang/v#29439](https://github.com/vlang/v/pull/29439).
That issue answers *"what did we resolve to, and can we get it back?"* —
reproducibility. This RFC answers the question underneath it:
*"what should we resolve to?"* Without that, the lockfile faithfully records an
arbitrary choice.

Concretely, this RFC proposes:

- version ranges in `v.mod`, using the `@` separator that already exists
- a resolver that picks the highest tagged version satisfying every constraint,
  and says clearly when nothing satisfies them
- `dev_dependencies`, `dependency_overrides`, `retracted`, and `min_v`
- `v mod graph`, and a version-aware `v outdated`
- constraint attribution in `v why`, which shipped in #29405 without it

None of that changes a compiler behaviour or an on-disk layout. There is a
section on letting two major versions coexist via import-path suffixes, because
the rest of the design only makes sense once you know where it is going — but I am
proposing that as a **separate RFC**, and the Phasing section says why.

# Motivation

## What vpm does today

`v install` has exactly one versioning feature. You may suffix a dependency with
`@<ref>`, and that ref is handed straight to the VCS:

```sh
v install vsl@v0.1.47
```

`parse.v:89-102` splits the string on its last `@`, and `vcs.v:69-84` turns the
right-hand side into `--branch=<ref>` for git or `--rev=<ref>` for hg:

```v ignore
if version != '' {
    if vcs == .git { args << '--single-branch' }
    args << '${info.args.version}=${version}'
}
```

So a "version" in vpm is a git ref. The only validation it gets is a guard against
NUL, CR, and LF (`vcs.v:70`) — sensible, since the string ends up on a command
line. It is never parsed as a version, never compared, and never resolved. If the
tag does not exist, the clone fails, and that is the entire error report.

Everything downstream of that is working around the absence of a version *model*:

**Asking what is installed is a guess.** `parse.v:289-314` runs
`git ls-remote --refs` on the installed directory and compares the last tag it
finds against the last branch head, as strings. If they happen to be equal, the
install counts as versioned. If your `master` and your newest tag point at the
same commit, the answer is "not a version install". The code says so itself:

```v ignore
// NOTE: can be refined for branch installations. E.g., for `sdl`.
```

**Dependencies carry no constraint.** `dependencies` is `[]string`
(`vlib/v/vmod/parser.v:33`) holding bare names or URLs. The parser accepts a
`@ref` because `parse.v:233-238` feeds each entry straight back into
`parse_module`, which does the same `rsplit_once('@')`. That path works and is
completely undocumented and untested.

**Resolution is "whoever got there first".** `Parser.modules` is a flat
`map[string]Module` keyed by `name@version` (`parse.v:22-29`). If two modules
want incompatible things, the first one parsed wins and the second is silently
dropped. Recursion into dependencies is depth-first at parse time
(`parse.v:233-238`) and the only thing bounding it is the `key in p.modules`
early return — a dependency cycle is caught by a test watchdog with a two-minute
timeout (`dependency_test.v:80-93`), not by a graph check. `v update` re-resolves
differently, with a flat one-level `resolve_dependencies` (`common.v:555-566`).

**`v outdated` cannot see versions.** `outdated.v:50-70` compares
`rev-parse @` against `rev-parse @{u}`. That is a branch-head comparison. A
tagged release is invisible to it.

**The on-disk layout holds one version.** `common.v:229-231` normalises a name
and it lands at `$VMODULES/<publisher>/<name>/`. There is nowhere to put a
second version of the same module, which is why `install.v:182-196` has to ask
before replacing one.

**Nobody has a lockfile.** The only writes vpm performs are the directory move
at `install.v:211`, a download counter, the log file, and the `--local`
ownership token. `v install foo` does not even add `foo` to your `v.mod`.

**And yet the tooling already assumes versions exist.** The one piece of
automatic dependency installation in the compiler is a hardcoded table:

```v ignore
// vlib/v/util/module_deps.v:11-13
pub const external_module_dependencies_for_tool = {
	'vdoc': ['markdown']
}
```

There is no place to say "vdoc needs markdown at version X", so it is a
compile-time constant instead.

## What this costs people today

Concretely, four things are impossible:

1. **You cannot say what you need.** `dependencies: ['vsl@v0.1.47']` expresses
   "that one". It cannot express "anything in the 0.1 series" or "at least 0.2,
   below 0.3". So you either pin exactly and lose every fix, or you leave the
   constraint off and get whatever `master` is today.

2. **Two modules cannot want different majors.** If `a` needs `args@0.4` and `b`
   needs `args@0.5`, one of them is wrong. There is no coexistence and no error.

3. **Your build is not reproducible**, which #29250 fixes, but only once there
   is a resolution worth recording.

4. **You cannot find out why you have the version you have.** `v why` landed in
   #29405 and answers "who pulled this in", but nothing selects versions yet, so
   it cannot say which constraint admitted the one you got. Every other ecosystem
   here can — `go mod why`, `npm explain`, `cargo tree --invert`, `pnpm why`,
   `bun why`, `dart pub deps`.

## Why now

`ROADMAP.md:81-83` has carried an unchecked "VPM / Package versioning" line for
years. What changed recently is that the bottom half of the problem got solved
first: #29250, with its implementation now open as #29439, gives us a place to
record a resolution and a `--locked` mode to enforce it. It is much easier to
review a resolution design once the recording mechanism exists, because the two
can be argued about concretely.

We agreed with the author of #29250 to keep those two as separate layers rather
than one change, so #29439 can land on its own terms. That is also the lower-risk
order: a lockfile is useful before ranges exist, because it already pins HEAD
installs with pseudo-versions and makes CI reproducible.

There is also an unused asset, and it is the reason phase 1 looks cheaper than it
is. `vlib/semver/range.v` is a range engine — x-ranges, `~`, `^`, hyphen ranges,
`||` sets — sitting behind a single public entry point:

```v ignore
// vlib/semver/semver.v:67
pub fn (ver Version) satisfies(input string) bool {
	return version_satisfies(ver, input)
}
```

`vpm/vcs.v:4` imports `semver`, and uses it for one thing: comparing the
installed git version against `2.36.0` to decide about shallow submodules
(`vcs.v:29-43`). The range engine is never used.

I originally wrote that this made phase 1 "mostly wiring, not writing". **That was
wrong, and I have since measured it.** `vlib/semver` is not the complete
node-semver implementation it appears to be: a corpus, now 130 cases, measured
against the ranges grammar in
[npm/node-semver](https://github.com/npm/node-semver), found **21 divergences**,
several of them in the core expansion logic rather than at the edges. #29428 has
since repaired every expansion case below; what remains is the two prerelease
bullets and the reporting half of the last one. The bullets are kept as written,
because the line numbers are the ones to check against:

- a **partial version is read as an exact pin**. `'1.2'` means `=1.2.0`, not
  `1.2.x`, because `can_expand` (`range.v:151-154`) only looks for an explicit
  `x`, `X` or `*`. So `'1.2.9'` does not satisfy `'1.2'`.
- **`^0.0.3` admits the whole `0.0.x` series.** `expand_caret` (`range.v:179-187`)
  increments the minor whenever the major is `0`, where node-semver increments
  the patch.
- **an x-range on a zero major has no ceiling at all.** `expand_xrange`
  (`range.v:207-218`) returns only the floor when the major is `0`, so `0.x`,
  `0.1.x` and `0.0.1.x` are all unbounded above. `'5.0.0'` satisfies `'0.1.x'`.
- **a hyphen range with a bare-major upper bound does not expand.**
  `is_missing(ver_major)` is true for `'2.2 - 2'`, so `expand_hyphen` returns
  `none` and `'2.2 - 2'` matches nothing.
- **prereleases have no ordering at all.** `compare_lt` never reads the
  prerelease, so `1.0.0-alpha` is neither `<` nor `>` `1.0.0`, yet both `<=` and
  `>=` hold — because `Version` overloads only `==` and `<` (`semver.v:72-79`) and
  the compiler derives the rest. That is an inconsistent relation, and it is why
  the prerelease problems cannot be fixed in the range layer alone.
- **there is no prerelease admission check**, so `1.0.0-alpha` satisfies
  `^1.0.0`, `>=0.9.0` and `*`.
- **a range with more than two comparators is a parse failure**, and an
  unparseable range is reported as "does not satisfy". A caller cannot tell a
  broken constraint from a genuine miss. Whitespace-only input falls into this:
  it splits into four empty comparators and is rejected, where node-semver treats
it as the empty range. #29428 removed the cap and made the empty range `*`.

   The reporting half is now closed too. `Version.satisfies_or_error` and
   `is_valid_range` report an unparseable range as an error rather than as a miss, and
   `select_version_tag` rejects a broken constraint before its loop — without which a
   typo in a range made every tag get skipped and the user got "no semantic-version tag
   satisfies" with no idea why. `Version.satisfies` itself still returns `false` for
   that case, because changing it would break every caller at once.

Two of those are landmines. `compare_ge` and `compare_le` are unreachable —
nothing calls them — and `compare_gt` is reachable only through `compare_ge`
(`compare.v:36`), so fixing the ordering means going through `<`.
`semver_test.v` pinned the `^0.0.1` divergence as expected behaviour, so
repairing `expand_caret` broke an existing test; #29428 corrected that row rather
than preserving it.

The honest version of the claim: the range engine is a real and mostly-right
implementation of the common forms, and reusing it still beats writing a second
one. But phase 1 includes repairing it, and a resolver should not be built on it
until that is done. The corpus test referred to below is the prerequisite, and
it is deliberately written to make every divergence visible rather than to assert
that the divergences are correct.

# Guide-level explanation

## Declaring what you need

You write a range after `@`, in the same string, using semver's grammar:

```v ignore
Module {
	name: 'myapp'
	version: '0.3.1'
	dependencies: [
		'vsl@^0.1.47',
		'nedpals.args@>=0.4.0 <0.6.0',
		'nedpals.orm@~0.2',
		'markdown@*',
		'https://github.com/nedpals/v-thing@>=2.1.0',
	]
	dev_dependencies: [
		'assert@~0.2.1',
	]
}
```

Note the trailing commas: `v.mod` requires a separator between array elements, and
the parser's error for a missing one is `invalid separator`, which is about the
array syntax rather than about whatever the element was going to say.

What each form means:

| Written | Means |
|---|---|
| `'vsl'` | any version at all (today's behaviour, unchanged) |
| `'vsl@0.1.47'` | exactly that version |
| `'vsl@^0.1.47'` | `>=0.1.47 <0.2.0` |
| `'vsl@^0.2'` | `>=0.2.0 <0.3.0` — note `^0.x` is stricter than `^1.x` |
| `'vsl@~0.1.47'` | `>=0.1.47 <0.2.0` |
| `'vsl@~0.1'` | `>=0.1.0 <1.0.0` |
| `'vsl@>=0.4.0 <0.6.0'` | that interval, and nothing else |
| `'vsl@1.2.x'` | `>=1.2.0 <1.3.0` |
| `'vsl@1.x'` | `>=1.0.0 <2.0.0` |
| `'vsl@*'` | anything |

A bare name with no `@` keeps meaning "anything", so every existing `v.mod` in
the world stays valid and keeps behaving identically.

Two rules worth internalising:

- **If the constraint is a range, only tags count.** `'vsl@^0.1'` will not
  resolve to a commit on `master` that happens to have a higher version in its
  `v.mod`. Branches and SHAs are only used when you ask for one by name.
- **`0.x` is not a stable series.** Under semver, `^0.1.47` means `>=0.1.47
  <0.2.0` — the minor acts as the major. If you want the whole `0.x` line, write
  `~0.1` or `>=0.1.0 <1.0.0`.

## Installing

```sh
v install                    # resolve everything from v.mod, honour the lock
v install vsl                # add 'vsl@^<latest>' to v.mod, then resolve
v install vsl@1.2.3          # exact
v install 'vsl@^1.2'         # a range — quote it, the shell will split on space
v install --dev              # also install dev_dependencies
v install --locked           # fail if resolution would differ from the lock
v install --frozen           # never write the lock
```

Quote any constraint containing a space. `v install vsl@>=1.0 <2.0` is two
arguments to your shell, not one constraint — the same papercut npm has had for
a decade.

## Two majors at once (forward-looking, separate RFC)

This one is not in scope — see Phasing. It is here because "one version per
module" is a decision you only make once you have seen the alternative, and
because the `/vN` RFC will start from this section rather than from nothing.

When a module reaches major 2, its import path changes:

```v ignore
// major 0 and 1 — unchanged, nothing to do
import nedpals.args

// major 2 and up — the suffix is part of the name
import nedpals.args.v2
```

Both can be installed, both can be imported, in the same build:

```
$VMODULES/nedpals/args/          <- v0.5.2 and v1.x land here
    v.mod
    args.v
    v2/                          <- v2.x lands here
        v.mod
        args.v
```

That falls out of the existing module lookup. `pref.v:426` turns the module name
into a path with `mod.replace('.', os.path_separator)`, and `dir_is_module`
(`pref.v:671-682`) only requires the directory to exist and hold at least one
`.v` file — it says nothing about subdirectories. So `publisher.name` and
`publisher.name.v2` resolve to two sibling directories with no compiler change
at all. If only `v2/` is installed, `import nedpals.args` fails to resolve,
which is correct.

Go has required this suffix since modules shipped, and it is the reason Go has
never had a diamond-dependency problem: incompatible versions are not two
copies of a library that a resolver has to keep straight, they are two different
names.

The compiler's "cannot import module" error
(`checker.v:5960-5968`) should gain one line: if `publisher.name.vN` is
installed but `publisher.name` is not, say so.

## Dev dependencies

`dev_dependencies` are for tests, tools, and docs — things your consumers do not
need. They are installed when you ask for them and are **not** part of your
transitive closure. If `a` depends on you, `a` does not get your `assert`.

This is pub's rule, and it is the right one: otherwise every project that
depends on you also depends on your test framework.

It also lets us retire `external_module_dependencies_for_tool` in
`vlib/v/util/module_deps.v`. `vdoc` declares its own dependency on `markdown` in
its `v.mod`, and `ensure_modules_for_tool_are_installed` reads it from there.

The rest of `module_deps.v` stays. That file is 230 lines and also owns the
clone-with-retry, the search across `VMODULES` roots, and the wait for a module
another process is installing right now; the constant is a three-line table inside
it. The table also doubled as the list of tools to check, so `v build-tools` now
reads the `cmd/tools` folders instead of iterating a map — a new tool then needs no
compiler change at all.

## Overrides

When two constraints genuinely cannot be reconciled, the root project gets the
last word. Overrides use pnpm-style selectors and only apply from the root:

```v ignore
Module {
	dependencies: ['vsl@^0.1.47']
	dependency_overrides: [
		'vsl: 0.1.60', // force this version everywhere
		'vsl>c: 1.0.2', // force it only where vsl asks for c
		'legacy@v3>risky: -', // delete that edge entirely
		'somepkg@>=2: 2.4.1', // only for constraints that already allow it
	]
}
```

The last form is worth calling out: it pins a version *only* for consumers whose
own constraint already admits it. Compatible consumers converge on one version
without forcing an incompatible one on the rest of the graph. pnpm calls this a
convergence override and it is the single most useful idea in this section.

## Retractions

A publisher can mark versions as bad without deleting them:

```v ignore
Module {
	name: 'vsl'
	version: '0.1.48'
	retracted: ['0.1.45', '0.1.46', '0.1.x']
}
```

- The resolver **skips** a retracted version when picking the highest candidate.
- `v install vsl@0.1.45` installs it, with a warning.
- `v install 'vsl@0.1.x'` refuses.

This is Go's `retract`, and the distinction from Cargo's `yank` is the point: a
retracted version is still downloadable and still works, it just must not be
what you get by accident. "A retracted paper is still available, but it should
not be the basis of future work."

## Finding out why

```sh
v why vsl
```

```
myapp@0.3.1
└── vsl@0.1.48
    └── c@0.2.1  (requires ^0.2.0)
        └── nedpals.args@0.5.2  (requires ~0.5.0)
```

`vsl` is here because `myapp` asks for `^0.1.47`, and nothing else in the graph
constrains it. `v why` can walk the tree today, but it has no constraint to
attribute a version to, so this is the part it cannot print yet.

## Seeing what is stale

```sh
v outdated
```

```
Package              Current    Upgradable   Resolvable   Latest
direct dependencies:
  vsl                0.1.47     0.1.48       0.1.48       0.2.0
  nedpals.args       0.4.9      0.5.2        0.5.2        0.5.2
  markdown           *          *            0.2.4        0.2.4
transitive dependencies:
  c                  0.2.0      0.2.0        0.2.1        0.2.1
```

Four columns, each answering a different question:

- **Current** — what the lock has
- **Upgradable** — the best your `v.mod` allows
- **Resolvable** — the best that satisfies every constraint in the graph
- **Latest** — ignoring all constraints

When Upgradable is behind Latest, your constraint is the bottleneck. When
Resolvable is behind Upgradable, someone else's is. Today `v outdated` can only
ever tell you about branch heads.

## Keeping it pinned

```sh
v update                      # re-resolve inside the existing constraints
v update --latest             # also widen constraints across majors
v update -p vsl --precise 0.1.45   # pin exactly one module, leave the rest alone
```

`--precise` is Cargo's escape hatch and it is the command people actually reach
for. It lets you say "this one, exactly" without hand-editing `v.mod`, and
without a lockfile full of one-off entries.

## Requiring a compiler version

```v ignore
Module {
	name: 'vsl'
	version: '0.1.48'
	min_v: '0.5.0'
}
```

If the running compiler is older than `min_v`, `v install` refuses with a clear
message instead of letting you discover the problem as a compile error 200 lines
into someone else's module. pub makes its equivalent (`environment: sdk:`)
mandatory; see the unresolved questions for whether we should.

# Reference-level explanation

## Syntax, and why it looks like this

The `@` separator stays. `parse.v:96` already splits a dependency string on its
last `@`, and `'vsl@v0.1.47'` already means something today. Changing the syntax
would invalidate the `v.mod` of every published module in exchange for nothing.
What changes is that the right-hand side may now be a range instead of a ref.

Everything new goes into keys the parser already tolerates.
`vlib/v/vmod/parser.v:285-293` puts any unrecognised field into
`mn.unknown`, so `dev_dependencies`, `dependency_overrides`, `retracted`, and
`min_v` are all readable by a new vpm and invisible to an old one. An old vpm
that meets a `v.mod` using them will simply not install the extras — which is the
right failure mode, and strictly better than a parse error.

### Why not a `name: version` map, when the parser now accepts one

As of #29249 the parser *does* accept a map for `dependencies` — the legacy form:

```v ignore
Module {
	dependencies: [
		markdown: '0.2.4'
	]
}
```

It also **discards the value**, with a comment that says so outright:

```v ignore
// vlib/v/vmod/parser.v:198
// Manifest.dependencies stores names only, so ignore legacy version values.
```

So `dependencies: [markdown: '0.2.4']` parses to exactly `['markdown']`.

That is worth pausing on, because it is the ecosystem already answering the
question this RFC asks. A `name: version` map was tried, accepted for
compatibility, and the version thrown away — `Manifest.dependencies` is
`[]string` (`parser.v:33`) and stays that way. The natural conclusion is that the
map is the wrong shape for a constraint, and that the constraint belongs in the
name string, where it survives parsing and where `parse.v:96` already knows how
to split it off.

Note also that only `dependencies` accepts the map form; every other field must
still be a string or an array of strings (`parser.v:251`). So `dependency_overrides`
would need a parser change to become a nested map regardless. Keeping it as flat
strings with a selector syntax avoids that.

The full grammar accepted after `@` is node-semver's, which is what
`vlib/semver/range.v` already implements:

| Form | Expands to |
|---|---|
| `1.2.3` | `=1.2.3` |
| `^1.2.3` | `>=1.2.3 <2.0.0` |
| `^1.2` | `>=1.2.0 <2.0.0` |
| `^0.2.3` | `>=0.2.3 <0.3.0` |
| `^0.0.3` | `>=0.0.3 <0.0.4` |
| `~1.2.3` | `>=1.2.3 <1.3.0` |
| `~1.2` | `>=1.2.0 <2.0.0` |
| `~1` | `>=1.0.0 <2.0.0` |
| `1.2.x` | `>=1.2.0 <1.3.0` |
| `1.x` | `>=1.0.0 <2.0.0` |
| `>=1.2.3` / `>1.2.3` / `<=1.2.3` / `<1.2.3` | as written |
| `1.2.3 - 2.3.4` | `>=1.2.3 <=2.3.4` |
| `^1 \|\| ^3` | either |
| `*`, `''` | any |

Whether we want all of it — particularly `||` and hyphen ranges — is an open
question below. The engine is already written either way.

## The resolver

The unit of work is a `(consumer, dependency_string)` pair.

```
resolve(root_manifest):
    constraints: map[name] -> list of (consumer, range)
    chosen:      map[name] -> version
    queue        = root.dependencies ++ root.dev_dependencies

    while queue is not empty:
        edge = pick(queue)                     # breadth-first, direct deps first
        name, spec = split(edge)

        if spec is an exact ref (branch, tag, or SHA):
            chosen[name] = spec                # no resolution; today's behaviour
            continue

        constraints[name] += (edge.consumer, spec)
        if name in chosen: continue

        # the lock gets the first say, so an unchanged project stays unchanged
        if lock has name and lock[name] satisfies all constraints[name]:
            chosen[name] = lock[name]
        else:
            candidates = highest_first(tags(name) where tag parses as semver)
            candidates = candidates.filter(not retracted)
            pick the first candidate satisfying every constraints[name]
            if none: backtrack, or fail

        queue += chosen[name]'s dependencies   # never its dev_dependencies
```

Four decisions inside that:

**Version discovery is `git ls-remote --tags`, filtered to parseable semver, sorted
in semver order — not string order.** Tags that do not parse are ignored, unless
you asked for one by name. Semver order is a total order on `major.minor.patch`,
so "highest" is unambiguous, which string sorting of `0.10.0` against `0.9.0` is
not.

**The lockfile has priority over "highest".** If the locked version still
satisfies every constraint, it wins even when something newer exists. That is the
whole point of #29250, and it is why `v install` twice in a row is a no-op
rather than a slow drift toward whatever was tagged this morning.

**Backtracking is over one axis: which version of one module.** When a choice
leads to a dead end, drop that module to the next lower candidate and re-expand.
Not a general SAT search, not PubGrub. Cargo publishes this shape and it is a
few hundred lines.

**The failure message is the feature.** When nothing satisfies the constraints,
print the chain, not "conflict":

```
error: no version of `c` satisfies the graph

  myapp requires            c@^0.3.0
  vsl@0.1.48 requires       c@^0.2.0

  `vsl@0.1.48` is what the lockfile pins and `c@^0.3.0` is what you asked for.
  Try: v update -p c --precise 0.2.1
       or relax 'c@^0.3.0' in v.mod
       or add 'c: ^0.3.0' to dependency_overrides
```

uv's PubGrub produces messages of this quality and it is the best argument for
PubGrub. But a good printer over a backtracker gets most of the way, and the
printer is the part users actually read.

## Layout for coexisting majors (for the follow-up RFC)

Not in scope here — see Phasing. Recorded in full so the follow-up has a starting
point and so this RFC gets reviewed against the destination it is heading for.

```
$VMODULES/<publisher>/<name>/            major 0 and 1
    v.mod                                 version: 0.5.2
    *.v
    v<N>/                                 major N >= 2, N = 2, 3, ...
        v.mod                             version: 2.1.0
        *.v
```

Rules:

- A module with `version` major `>= 2` is installed under `<name>/v<major>/` and
  must be imported as `publisher.name.v<major>`.
- Majors `0` and `1` both live at the unversioned path, and keep importing as
  `publisher.name`. This matches Go.
- If only `v2/` exists, `import publisher.name` does not resolve. `dir_is_module`
  (`pref.v:671-682`) requires a `.v` file directly in the directory, so a
  container holding only `v2/` is correctly not a module.
- `v list` reports `publisher.name` and `publisher.name.v2` as separate entries.
- `v remove publisher.name` removes the unversioned one; `v remove
  publisher.name.v2` removes v2. The command speaks in import names, which is the
  only name the user has.

What this does **not** do is nest a second copy inside a dependent, npm-style.
V's import path *is* the identity, so a nested copy would have to lie about where
the code came from.

## Interaction with #29250

#29250 is `whiter001`'s, and its implementation is now open as
[vlang/v#29439](https://github.com/vlang/v/pull/29439). We agreed to keep the two
as separate layers: theirs records what was chosen, this one decides what gets
chosen, and each stands on its own without the other. This section describes
their layer; nothing here asks them to change it.

This RFC does not change the lockfile format, and that is deliberate.

`v why` needs the requirement edges. It does not need them in the lockfile,
because every installed module already carries its own `v.mod` with its own
`dependencies`. So `v why` walks the installed tree, using the lock only to know
which version of each name is authoritative. #29250's format — the dependency
string as written, the resolved tag or pseudo-version, the full SHA, the clone
source — is sufficient.

Worth recording since it is now checkable rather than predicted: #29405 built
`v why` this way, and needed no lockfile format change to do it.

If it turns out not to be, the minimal change is a `deps` array per entry, which
is exactly what `Cargo.lock` does.

What this RFC *does* change about the lock: the set of versions a run may choose
from. Under #29250 alone, the lock records a branch tip. Under this RFC it
records a tag chosen from a range, and the SHA of that tag.

Two properties of #29439 make that a change of meaning rather than of format, and
I checked both in its diff rather than taking them on trust. Its `resolved` field
is documented as "the selected revision: the requested tag for `@tag` installs,
the version chosen by a resolver once version ranges exist, or a pseudo-version
of the checkout HEAD otherwise" — so it already has room for a chosen version.
And it never parses a version at all, which is what keeps the two layers from
blocking each other. `--locked` compares `requested` against the dependency
string verbatim, so an edited range is a changed string and fails, while an
unchanged range with a satisfying locked revision passes. All range semantics
stay in this layer.

One more interaction: `--locked` in #29250 means "fail if resolution would differ
from the lock". That definition only becomes meaningful once there is a
resolution. It currently passes trivially.

## Migration

Nothing breaks, and that is by construction:

| Existing | After |
|---|---|
| `dependencies: ['markdown']` | same, means "any version" |
| `dependencies: ['vsl@v0.1.47']` | same, exact pin still works |
| `dependencies: ['https://github.com/x/y']` | same |
| a module with no `version` field | still installable; `v list` shows `-` |
| `v.mod` with no new keys | parses identically, `unknown` stays empty |
| `$VMODULES/publisher/name/` flat layout | unchanged for major 0 and 1 |

The one behaviour change is intentional and is #29250's: once a project has a
lockfile, `v install` installs the locked revisions instead of re-resolving.
That is what "reproducible" means.

## Phasing

Splitting this up is not a formality — it is the main thing that makes it
reviewable. Each phase is independently useful and independently landable.

**Phase 0 — repair `vlib/semver`.**
A corpus test against the node-semver ranges grammar records 135 cases. It found
21 divergences. #29428 fixed the 13 that were range expansion: partial versions
read as exact pins, `^0.0.x`, unbounded `0.x`, the bare-major hyphen upper bound,
and a few parse shapes. The 7 left are all prerelease — ordering, and whether a
prerelease satisfies a range at all — which is ordering rather than expansion and
belongs in a separate patch.

**That count is wrong, and the reason is worth recording.** The corpus was written
by hand from the grammar, so it only asked the questions I thought to ask. Running
a differential fuzzer against node-semver 7.8.5 instead — 3999 generated ranges,
seeded and reproducible — finds **194 divergences in range expansion alone**, and
a shape matrix of `op` against an incomplete version finds 663 more across 52
range shapes. Two families are already isolated and both reproduce unchanged on
master:

- **`expand_tilda` confuses "minor is 0" with "minor is absent".** `~2.0.0` should
  be `>=2.0.0 <2.1.0-0`; it comes out as `<3.0.0`. Exactly 9 range shapes are
  wrong — `~M.0`, `~M.0.0` and `~M.0.0-beta.1` for `M` in 0, 1, 2 — and the bare
  `~2` form is correct, which is what makes it a zero/absent confusion rather than
  a missing ceiling. This is the same mistake #29428 fixed in `expand_caret`.
- **A comparison operator against an incomplete version gets no ceiling.** `<=0`
  means `<1.0.0-0`; here it is read as `<=0.0.0`. 52 of the 70 such shapes
  node-semver accepts are wrong.

**Phase 0 shipped as #29569, and the numbers above were the starting point rather
than the answer.** The two families here were 21 of the divergences; the shape matrix
and the corpus were hiding the rest, so the 194 grew to **302** once the matrix was
run over 6000 ranges against node-semver 7.8.5. Those 302 reduced to six root
causes, and #29569 (per-operand expansion routing, the operator rewrite, and the
remaining `can_expand`/tilde/hyphen/`-0` bounds) takes the differential result to
**0 divergences across four seeds — about 16000 ranges** — with false accepts down
from 79 to 11-13.

Two things about that number are worth keeping. It is a *differential* result against
node-semver, not a corpus one: the hand-written corpus still sits at 136 conforming
cases and agreed with node-semver on all of them both before and after, so it could
not have found any of the six causes. And the remaining 11-13 false accepts are
ranges V answers `true` for that node-semver rejects — mostly unparseable input
rather than arithmetic, which is what the 1364-in-one-seed unparseable count in the
harness says.

What the original number established, and what still holds, is the scale:
**phase 0 is not a cleanup, it is the largest single
item in this RFC by a wide margin**, and I would not have known that from the
hand-written corpus.

Also then open: what an unparseable range should report instead of a bare `false`.
The fuzzer makes the cost of that visible too — 882 of the generated cases are ranges
node-semver rejects outright, and this module answered all of them `false`, so a caller
could not tell a broken constraint from a genuine miss. Two (`1.` and `1.0.0 - 2.2.`)
answer `true`. **That is closed now**: `satisfies_or_error` and `is_valid_range`
report it as an error, and `select_version_tag` rejects a broken constraint up front.

**Phase 1 — constraints and a resolver, no layout change.**
Ranges in `v.mod`, the resolver, lock integration, version-aware `v outdated`,
`v update --precise`, `v mod graph`, and constraint attribution in the `v why`
that already exists. One version per module, exactly as today. This is where the
value is, and it needs **no compiler change at all** — it is entirely inside
`cmd/tools/vpm/` plus phase 0.

**A first slice of this landed as #29600, and it is narrower than this section
describes.** `v install vsl@v0.1.47` now resolves to a concrete tag: the range is
recognised, `git ls-remote --tags` is asked for the candidates, the highest
satisfying one is selected, and that tag is what gets installed. Three things are
worth recording about what that is and is not:

- **The range is a selection, not a constraint.** It is resolved once, at install
  time, to a single tag. Nothing downstream knows a range was involved, so there is
  no joint solving: `validate_range_destinations` refuses two ranges for the same
  module outright, with "joint version-range resolution is not yet supported" as
  the message. The RFC's phase 1 assumed ranges that survive into the lockfile and
  get reconciled against each other; that is still unwritten.
- **The range travels on the dependency string, not in `v.mod`.** `vsl@v0.1.47` is
  the syntax, which is the `@` separator `parse.v` already had. Whether a range can
  also be declared in `v.mod` is open, and the answer changes what the lockfile has
  to record.
- **Tag validation is stricter than the parser's.** `version_tag` round-trips the
  core and rejects leading zeros and identifiers the module cannot represent, which
  is a real improvement over accepting whatever a repository happens to tag.

So phase 1 is started rather than outstanding, and the part that remains is the part
the RFC actually argued was valuable: the resolver, and lock integration with it.

**The resolver's core landed in #29680.** `collect_constraints` gathers every
constraint placed on each module, and `select_version_tag_with_constraints` picks the
highest tag satisfying all of them — or returns an error naming the requirements that
could not be met. Without that, a conflict between two dependents reads as "no tag
matched" and the user has no idea why.

What is still missing is the part that makes it a resolver rather than a selector:
backtracking. Each module is resolved against the constraints on it, but a module's
own dependencies are not re-resolved when its version changes. That needs the graph
walked in dependency order, and it is the step a differential fuzzer becomes necessary
for — the property stops being checkable by enumeration once the search order matters.

**Backtracking landed in #29680.** `resolve_with_backtracking` walks the modules in
dependency order, tries each from its highest version down, and steps back to the
previous module when a choice dead-ends. The position map is what makes it backtracking
rather than a single pass: without it a module that fails ends the run, with it the
previous module tries its next version.

The search is exponential in the worst case, which is the cost the RFC warns about. It
is bounded in practice by the number of versions a module publishes, and it stops at the
first consistent assignment rather than searching for the best one.

**`v mod graph` also landed in #29680.** It prints the dependency graph — every module
and the modules it imports, indented by depth. Each module is printed once, at its first
occurrence, so a diamond does not repeat a subtree. That is the difference between a
graph and a tree, and it is why the output is not simply nested indentation.

**Phase 2 — the manifest additions.**
`dev_dependencies` (and retiring the compiler-side table), `dependency_overrides`,
`min_v`. Still no layout change, and — corrected while implementing this — **no
compiler change at all**. `Manifest.unknown` is already public and already holds
unrecognised keys as `map[string][]string`, so all three keys round-trip through the
existing parser, a scalar `min_v` included.

Two claims in the draft of this RFC were wrong here, and both are worth recording
because each would have sent a reader looking in the wrong file:

- ~~The only compiler-adjacent edit is reading `dev_dependencies` where
  `module_deps.v` is currently hardcoded.~~ There is no such edit. I verified all
  three keys round-trip before relying on it.
- ~~`dev_dependencies` means deleting `module_deps.v`.~~ `module_deps.v` is 230
  lines, not the 11 the draft cites: it also holds the clone-with-retry, the
  module-root search, and the wait-for-a-concurrent-install. What is retired is the
  `external_module_dependencies_for_tool` constant and its accessor — the install
  machinery stays.

`dependency_overrides` is the one of the three that phase 1 constrains, and only
partly. The `name: version` form — force this version, regardless of what was asked —
shipped in #29680: it is a selection, not a redirection, so it needs no graph. The
selector forms (`vsl>c: 1.0.2`, `legacy@v3>risky: -`, `somepkg@>=2: 2.4.1`) do need
one, because "only where vsl asks for c" and "delete that edge" are statements about
the dependency graph, and `Parser.modules` is still a flat map. So the resolver is
what stands between the useful half of this feature and the precise half.

**The first selector form shipped in #29680.** `vsl>c: 1.0.2` now applies only where
vsl asks for c, using a graph built from the manifests already parsed. That graph is
flat — one level, no transitive edges — which is all this form needs. The remaining
two are still waiting: `legacy@v3>risky: -` needs to remove an edge rather than
redirect one, and `somepkg@>=2: 2.4.1` needs to check a consumer's constraint against
the version being forced.

**Phase 3 — `retracted`.**
Deliberately last. See the drawback below: it is the only feature here whose cost
scales with the number of versions you *didn't* pick.

**Phases 0 and 1 together would replace the unchecked ROADMAP line.**

### What I am deliberately not proposing here

**Coexisting majors (`/vN`) should be a separate RFC.**

I designed it, it is good, and it is about 60 lines of this document — but it
needs a compiler decision that deserves its own discussion, and bundling it makes
this RFC easier to reject as a whole. Concretely: `/vN` is only correct if the
compiler *enforces* the suffix, and enforcement means changing module resolution
and every error message about it. That is a language-visible change and this
should not be where it gets argued about.

So: this RFC gets the constraint language and the resolver right, and leaves a
design ready for the `/vN` RFC to build on. The layout section below is written
out in full precisely so that RFC does not start from nothing — and so this one
gets reviewed on the parts that are actually vpm's business.

The `/vN` design is summarised in the Guide-level section because it is the mental
model that makes the rest make sense; treat it as "this is where we are going",
not "this is in scope".

# Drawbacks

These are the reasons not to do the in-scope parts. I have left out the objection
that "a package manager is a lot of work" — that is true of every proposal ever
made and is not an argument.

**Making `version` real breaks existing modules.** `version` in `v.mod` is
currently a free-form string that nothing validates; `parser_test.v:23` round-trips
`'0.7.7'` and nothing else checks it. Requiring it, and requiring the git tag to
match it, makes every module with it wrong uninstallable. That needs a migration
window and a warning phase, and it will generate support load.

**A resolver is a permanent commitment.** Backtracking resolvers accumulate edge
cases for years — npm, Cargo, and uv all have multi-year bug histories that are
almost entirely about resolution. This is the largest ongoing cost in the
proposal, and it does not go away once it is written.

**Retraction is expensive per unit of value.** To know whether `0.1.46` is
retracted, you need metadata about a version you did *not* select. Either the
registry serves it, or vpm fetches a `v.mod` per candidate tag. The first needs
work in a second repository; the second costs a network round trip per candidate.
This is why it is in phase 3.

**Ranges on the command line are a footgun.** `v install vsl@>=1.0 <2.0` is two
shell arguments. Every ecosystem with ranges has this bug and every one of them
still has it.

**New output formats to own.** `v why` and `v outdated` are user-facing text that
people script against and file issues about. `v outdated` in particular has to
answer "why did it *not* update", which is genuinely hard, and getting it subtly
wrong is worse than not shipping it.

**`vlib/semver` became load-bearing and it was not ready.** I wrote that fuzzing it
against a corpus was "a prerequisite, not a follow-up". Doing that is what turned
up the 21 divergences listed above, so the warning was correct — and a differential
fuzzer then turned up 302 in total, so it was badly understated.

This was the largest single piece of unplanned work in this RFC and the one a
reviewer would least expect to price correctly from reading it. It is now paid for
rather than outstanding: #29428 took the cases the hand-written corpus happened to
cover, #29478 the prerelease ordering, and #29569 the rest, at 0 divergences over
four seeds. The pricing lesson stands, though, and it is the reason phase 1 is
proposed with its own testing plan rather than on trust: **the corpus was not a
substitute for a differential fuzzer, and no reviewer should read a green corpus
here as evidence about anything.**

The same lesson applies to #29600, which is why its limitation is quoted rather than
paraphrased above: a feature that resolves one range to one tag is easy to test and
easy to believe, and the failure it cannot see is the one where two ranges for the
same module disagree.

**This does not fix name squatting.** V has no namespace isolation;
`normalize_mod_path` (`common.v:229-231`) lowercases and maps `-` to `_`, so
distinct upstream names can collide on disk. Versioning is orthogonal to that
and does not help.

**This does not solve coexisting majors.** Deferring `/vN` means that if two
incompatible majors is the actual pain in this ecosystem, phases 1 to 3 are a lot
of work in the wrong direction. I do not think it is — the common case is "I want
a bugfix without the breakage", not "I need both of these at once" — but it is the
judgement I am least sure of, and it is the one that would make this RFC the wrong
RFC.

For whoever writes the follow-up: `/vN` is a real tax on maintainers. Every major
bump means a new directory, a new tag convention, and every consumer's imports
change. Cargo avoids it by unifying or erroring, npm by nesting, and only Go
pushes it to users — because Go's compiler *enforces* it from the first import. A
half-enforced version, where vpm installs `v2` into place and the compiler only
hints, is worse than not having it: confusing when it triggers and silently wrong
when it does not.

# Rationale and alternatives

## Why ranges rather than Go's minimum-only model

Go's MVS is elegant because every constraint is a hard floor. The build list is
the pointwise maximum of all requirements, so there is nothing to search and
nothing to backtrack, and `go.sum` needs no version list at all — the official
docs are explicit that "the build list is not saved in a 'lock' file" because
MVS is deterministic.

That elegance depends on the property V's `v.mod` does not have. `dependencies`
entries may name a branch, a URL, or an exact tag, and there is no concept of a
ceiling at all. `'vsl@v0.1.47'` today means "that one", not "at least that one" —
so adopting MVS would silently change the meaning of every existing `v.mod`.
And semver ranges are what people already arrive with; `^` and `~` are the
lingua franca of every other tool here.

The honest cost: we do not get MVS's predictability, and we take on a search.

## Why backtracking rather than PubGrub

uv uses PubGrub, an incremental SAT-style solver, and its error messages are the
best in the ecosystem. It is also a substantially more complex thing to build,
debug, and explain to a maintainer who has to own it forever.

For V's actual graph sizes — a `v` compiler build imports on the order of tens of
modules, not thousands — PubGrub's performance argument does not apply. Its
error-message argument does, but a dedicated printer gets most of the value at a
fraction of the complexity. If resolution turns out to be slow in practice,
PubGrub is a drop-in replacement for the search step and nothing else changes.

## Why semver rather than PEP 440

uv uses PEP 440, which has `~=` instead of `^` and permits epochs, `.post1`, and
calendar versions like `2025.10.5`. (pub does not — it is on semver 2.0.0-rc.1,
specifically because that version allows build identifiers like `+12345`.)

V's ecosystem is already semver-shaped: `v.mod` documents `version: '0.0.1'`,
the compiler is `0.5.2`, and `vlib/semver` exists and implements semver.
Introducing a second version grammar into one language is a cost with no
corresponding benefit.

## Why the import path carries the major, rather than duplicating in the resolver

The reason to make `/vN` the mechanism is that it makes the diamond problem
disappear rather than solving it. Two incompatible versions of `args` are not
two copies a solver has to keep consistent — they are two names, and the import
statement says which one you mean.

The alternative, npm's, is to nest a second copy under the dependent and let the
resolver place things. That requires the import path to stop meaning "where this
code lives", which in V it very much does. `import nedpals.args` has to name one
directory.

Cargo's alternative — unify if possible, hard error if not — is arguably better
behaved, but it only works if a major bump is *always* semver-incompatible. In V
it is not: `0.x` means "unstable", and the whole ecosystem is full of modules
whose minor bumps break things.

## Why not a second content hash

npm records an SRI `integrity`, Cargo a `checksum`, pnpm an `integrity`, uv a
`sha256` per artifact, Zig a multihash. It is a good idea in general and wrong
here.

#29250 already records the full commit SHA. For a `git clone`, the commit SHA
*is* the content address of exactly the bytes that get used. Adding a tarball
hash creates a second source of truth for the same fact, which can disagree, and
then someone has to decide which one to believe. One hash, verified, beats two
hashes, cross-checked.

The day vpm stops cloning git and starts fetching artifacts — `vca`, per
[rfcs#27](https://github.com/vlang/rfcs/issues/27) — this reverses, and the lock
needs artifact hashes.

## Why keep the `@` separator

Because it already exists and already works. `'vsl@v0.1.47'` parses today at
`parse.v:96` and is already half-documented at
[vlang/v#19709](https://github.com/vlang/v/issues/19709). A new syntax would
invalidate every published `v.mod` to no end.

## Why not solve this in the registry

Everything in phase 1 and 2 works against plain git URLs. `v install
https://github.com/nedpals/v-thing@^2.1` needs no registry at all, and
`parse.v:115-177` already handles external URLs by requiring a `v.mod` in them.

That is a real strength: it means this does not depend on vpm.vlang.io's
roadmap, and a vpm that can do all of this from git is still useful to people
who never publish to the registry. It is also why `retracted` is awkward — the
retraction data lives in a `v.mod` inside the repository, which is one extra
fetch per candidate version. A registry endpoint would fix it.

## The impact of not doing this

`ROADMAP.md:83` stays unchecked, and the four impossible things stay impossible.
Concretely: a V project cannot express a dependency ceiling, cannot host two
incompatible majors of one dependency, cannot reproduce its build, and cannot
explain its own dependency tree. Every V project that works around this does it
by hand, in its own way, in a `v.mod` comment.

# Prior art

How each one declares and records what it resolved:

| | Manifest | Lock | Constraint grammar |
|---|---|---|---|
| **npm** | `package.json` | `package-lock.json` | node-semver, full incl. `\|\|` |
| **Go** | `go.mod` | `go.sum` only, **no version list** | **exact only** |
| **Cargo** | `Cargo.toml` | `Cargo.lock` (TOML) | `^ ~ = > <`, **no `\|\|`** |
| **Bun** | `package.json` | `bun.lock` (JSONC) | node-semver |
| **pnpm** | `package.json` + `pnpm-workspace.yaml` | `pnpm-lock.yaml` | node-semver |
| **uv** | `pyproject.toml` | `uv.lock` (TOML) | **PEP 440**, `~=`, no `^` |
| **Mix** | `mix.exs` | `mix.lock` | `~>` only |
| **pub** | `pubspec.yaml` | `pubspec.lock` | `^` and comparisons, no `\|\|` |
| **Zig** | `build.zig.zon` | **none** | **none** — the hash *is* it |
| **vpkg** | `vpkg.json` | `.vpkg-lock.json` | **exact only** |
| **vpm** | `v.mod`, `dependencies []string` | **none** | **none** |

And how each one behaves when the constraints disagree:

| | Resolution | Coexisting majors | Integrity |
|---|---|---|---|
| **npm** | highest, nests on conflict | nested `node_modules` | SRI sha512 |
| **Go** | MVS, max of minimums | **`/vN` import suffix** | `h1:` dirhash |
| **Cargo** | backtracking, unify-or-error | duplicated per major | `checksum` |
| **Bun** | highest satisfying | as npm | integrity |
| **pnpm** | backtracking + peer resolution | content-addressable store | SRI sha512 |
| **uv** | PubGrub + forking | markers + resolution forks | `sha256` per artifact |
| **Mix** | conservative union | — | Hex checksum |
| **pub** | newest compatible, **skips deps' dev deps** | — | sha256 |
| **Zig** | none | n/a | multihash is the key |
| **vpkg** | pin-to-latest | flat list, **no graph** | branch-tip commit only |
| **vpm** | first writer wins | flat, one version | **none** |

## The parts worth copying, and why

**Go's `/vN`.** The only mechanism in the table that makes incompatible versions
coexist without the resolver's help, and V's `publisher.name` naming makes it
nearly free. Copied in full.

**Go's `go mod why`.** The ancestor of `npm explain`, `pnpm why`, `bun why`,
`cargo tree --invert`, and `dart pub deps`. Every one of those ecosystems
concluded independently that without it nobody can debug a lockfile.

**Cargo's `--precise` and `overrides`.** `--precise` is the "pin exactly this
one" escape hatch. `[patch]` is the "no, I insist" escape hatch. You need both,
and they are small.

**pnpm's convergence override.** `name@:` pins a version only for consumers whose
constraint already admits it. It fixes real conflicts without creating new ones,
which is a strictly better default than npm's unconditional override.

**pub's four-column `outdated`.** Current / Upgradable / Resolvable / Latest.
Each column diagnoses a different class of staleness. I have not found this
anywhere else, and it is the most useful version-diagnostics UI surveyed.

**pub's dev-dependency rule.** "It ignores the dev dependencies of any dependent
packages." Simple, correct, and it is why nobody's Python install has pytest's
own test dependencies in it.

**pub's mandatory `environment: sdk:`.** Forcing every package to declare its
minimum toolchain is a good forcing function. V has no equivalent.

**Zig's hash-as-identity.** `url` is just one mirror; the hash is the truth.
Cheap to adopt later, and it is what makes mirrors and vendoring work.

**pnpm's `minimumReleaseAge`, default 24 hours.** One line of configuration that
removes an entire class of supply-chain attack, justified in a sentence: "malicious
releases are discovered and removed from the registry within an hour." Future
possibilities, not this RFC.

## The parts to avoid

**vpkg's lockfile.** A flat package list with no edges and no hashes. `url` and
`method` are empty for registry packages, so the only provenance field is
`latest_commit` — a branch tip, which is the one value guaranteed to change.
There is no way to answer "why is this version here", no way to detect a removed
transitive, and no integrity check at all.

**npm's dual lockfile representation.** `packages` plus a legacy `dependencies`
tree, kept for a major version, so every reader has to know which one is
authoritative.

**Bun writing credentials into the manifest.** "The URL, credentials included, is
written to `package.json` and to the lockfile."

**Go's pseudo-version invariants, if we adopt pseudo-versions.** Go requires that
a pseudo-version's base tag be an ancestor of the revision, that its timestamp
match the revision, and that the revision be reachable from a branch or tag.
Those three rules exist specifically to stop `v1.999.999-99999999999999-<sha>`
from bypassing MVS. #29250 already generates Go-style pseudo-versions, so if we
keep them we should keep the invariants. Once pseudo-versions are in the wild
they are permanent.

**Cargo's own advice against its own features.** Do not use `*` (banned on
crates.io anyway); do not use `>=2.0.0` ("can pull in any SemVer-incompatible
version"); do not pair `~1.3` with `1.4` in different modules ("this will fail to
resolve, even though minor releases should be compatible").

# Unresolved questions

Each of these has a recommendation. I have written them down rather than leaving
them open because an RFC that punts every decision reads as unfinished, and
because a concrete proposal is easier to disagree with than a question. If you
disagree with one, say so — that is the part I want feedback on.

## Decisions I have made, and would like challenged

1. **`/vN` is a separate RFC, not part of this one.** My reasoning is in Phasing:
   it is only correct if the compiler enforces the suffix, that is a language-visible
   change, and bundling it makes this RFC easier to reject whole. **The alternative**
   is to keep it here and accept a higher chance of total rejection for a feature
   that is not the urgent one.

2. **Adopt node-semver's full grammar, including `||` and hyphen ranges.** This
   cuts against intuition — those two forms are what users get wrong most, and
   Cargo ships neither. But rejecting them does not reduce work, it *adds* work:
   `vlib/semver/range.v` already accepts them — `||` is
   `r.comparator_sets.any(it.satisfies(ver))` (`range.v:34-35`) over the sets
   produced by `input.split(comparator_set_sep)` (`range.v:58`), and hyphen ranges
   are `expand_hyphen` (`range.v:189`). A "subset" means writing a second,
   divergent range parser to reject syntax the first one already takes. Two
   parsers is worse than one permissive one.

   The measurement above weakens this argument rather than overturning it. The
   grammar being *accepted* is not the same as the grammar being *implemented*:
   `||` only works with a space on each side, and a hyphen range with a bare-major
   upper bound expands to nothing. So the case is now "repair one parser" instead
   of "reuse a finished one". That is still the cheaper option, but it is a repair
   job, and it is an argument I could not have made honestly before measuring.
   **The alternative** is a deliberately small grammar with much better error
   messages, at the cost of a new parser.

3. **`dependency_overrides` may force a version, not just redirect a source.**
   Version-forcing is what people actually do when two constraints conflict;
   redirecting-only would not stop them reaching for `v update --precise` instead.
   Two guardrails: overrides only apply from the root module (never from a
   dependency, so a dependency cannot dictate the consumer's tree), and the
   convergence form `name@range:` is preferred because it cannot create a conflict.
   **The alternative** is source-only, which is safer and much less useful.

4. **Four columns in `v outdated`, not two.** `Resolvable` is the one that answers
   "why did it *not* update", which is the question a user actually has;
   `Upgradable` alone cannot distinguish "my constraint is too tight" from
   "someone else's is". Cost is one extra resolution pass, which is cheap next to
   getting it wrong. **The alternative** is shipping `Current`/`Upgradable`/`Latest`
   and discovering from issues that the middle case is the common one.

5. **Stay flat: `v why`, `v mod graph`. No `v mod` subcommand group.** vpm already
   has 11 flat subcommands (`vpm.v:16-17`) and users type them. Grouping `v mod`
   would be tidier and would break muscle memory for no gain at this size.
   **The alternative** is a group now, on the theory that it scales better once
   there are 20 subcommands.

## To settle during implementation

6. **`v why` walks the installed `v.mod` files; no lockfile format change.** Each
   installed module already carries its own `dependencies`, so the edges are
   available without growing #29250's format. Needs a prototype to confirm the
   walk gives the right answer when the installed tree contains leftovers from a
   previous resolution. **Fallback if it does not:** a `deps` array per lock entry,
   which is what `Cargo.lock` does.

7. **`version` becomes required, but warn before enforcing.** Concretely: a
   release where a missing or mismatched `version` warns, then one where it
   refuses. I would rather not skip this — a resolver picking between tags that
   disagree with the manifest is worse than not having versions — but the warning
   period is non-negotiable, and how long it runs is a maintainer decision.

8. **The compiler reads `dev_dependencies`, and the table goes away.** *(Settled: this
   is what shipped.)* `vdoc` declares its own `markdown` dependency and
   `ensure_modules_for_tool_are_installed` reads it from the tool's `v.mod`. This is
   strictly more general than the table it replaces, which is the argument, and
   `v build-tools` now scans the `cmd/tools` folders rather than iterating a map, so
   a new tool needs no compiler change. **The alternative** was leaving the table
   alone and treating `dev_dependencies` as vpm-only, which would mean the compiler
   still cannot know what a tool needs.

   The part that was wrong in the draft: nothing here needed a parser change, and
   `module_deps.v` was never going to be deleted, only trimmed.

9. **`retracted` is read from each candidate tag's `v.mod`, and only for
   candidates actually examined.** With a cap on how many tags are inspected, and
   aggressive caching. A registry endpoint would be better but requires work in a
   second repository, and phase 3 should not be blocked on that. **The alternative**
   is registry-only, which leaves git-only installs — a large part of the ecosystem
   today — unable to retract anything at all.

## Out of scope for this RFC

10. **Vendoring** (`go mod vendor`, `cargo vendor`). Once the lock is stable this
    is a small feature, but it is a separate conversation about what a vendored
    tree looks like on Windows.

11. **Workspaces.** Multiple `v.mod` files in one repository, with a shared lock.
    pnpm's `pnpm-workspace.yaml` and Cargo's workspace are both non-trivial, and
    both benefit from having a stable lock format first.

12. **Publishing.** How a version gets tagged, whether `v release` should exist
    (vpkg's `--inc major|minor|patch` with `--state alpha|beta|fix` is a nice
    single verb for it), and whether the registry should verify that a pushed tag
    matches the pushed `v.mod`. The last one is the actual fix for someone
    publishing `v0.2.0` under someone else's name.

13. **A registry-independent `+incompatible` marker.** Go's mechanism for "this
    major was released before we could enforce the suffix". Needed once `/vN`
    ships, not before.

14. **Namespace isolation.** Whether `publisher.name` should be reserved, and
    what happens when two publishers normalize to the same directory. A
    correctness problem that versioning makes slightly worse and does not solve.

# Future possibilities

**Catalogs.** Declare a version once for a whole repository and reference it
everywhere, as pnpm and Bun do. This is the fix for "twelve `v.mod` files, twelve
copies of `^0.1.47`", and it becomes much more valuable once workspaces exist.

**`minimum_release_age`.** pnpm defaults to 1440 minutes and states why: "in most
cases, malicious releases are discovered and removed from the registry within an
hour." One line of policy that removes a whole class of attack, and it applies to
transitive dependencies too.

**`--exclude-newer <date>`.** uv's reproducibility cutoff. `--exclude-newer
2026-01-01` or `--exclude-newer '7 days'` pins resolution against a moving
index, which is what you want in CI and in a published lockfile.

**Registry-qualified lock keys.** pnpm hit this in v11.20.0: before it, two
registries serving the same `name@version` collapsed onto one entry and whichever
resolved first decided the tarball everyone got. `name@internal:1.0.0` fixes it.
Without this, a lockfile is not a security boundary.

**`vca` and artifact hashes.** [rfcs#27](https://github.com/vlang/rfcs/issues/27)
wants to ship compiled libraries without source. The moment vpm fetches
artifacts instead of cloning git, the commit SHA stops being a content address
and the lock needs real artifact hashes, plus size and platform fields.

**Solver upgrade path.** If backtracking proves slow on a real graph, PubGrub is a
drop-in for the search step. Keeping the constraint interface and the error
printer separate from the search is what makes that possible.

**Watching what is stale.** `v outdated` today answers at a moment.
`v update --dry-run` in CI answers over time, and is how you find out that a
transitive dependency released a breaking change three months ago.
