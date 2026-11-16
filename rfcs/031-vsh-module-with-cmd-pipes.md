- Topic Name: vsh_shell_module
- Start Date: 2026-05-20
- RFC PR: [vlang/rfcs#31](https://github.com/vlang/rfcs/pull/31)

# Summary

Add a `vsh` module to `vlib` providing shell-like command execution for
V scripts (`.vsh` files): `sh()`, `must()`, and a `Cmd` builder with
OS-level pipe support. The companion changes to `os.Process` (custom fd
injection via `set_stdin_fd`/`set_stdout_fd`/`set_stderr_fd`, Windows
handle inheritance, spawn error propagation) are included as foundational
infrastructure.

An alternative formulation would place the public API directly in `os`
(e.g. `os.shell()`, `os.cmd()`); the RFC evaluates both approaches.

A first implementation of this module can be found [here](https://github.com/dedesite/v/compare/master...dedesite:dedesite:vsh)

Note : I use deepseek-v4-flash to help me write the code, the commit and this RFC, I wanted to be transparent about that. Don't know the v politic about LLM generated code.

# Motivation

The original inspiration for this module comes from the ecosystem of
shell-scripting-in-general-purpose-languages that emerged in the
JavaScript/TypeScript world: [Google's zx](https://google.github.io/zx/)
and [Bun's built-in shell](https://bun.sh/docs/runtime/shell) bring
shell-like ergonomics to TypeScript by providing tagged templates and
builder APIs for subprocess execution. These projects demonstrated that
a typed language can be a compelling alternative to bash for system
scripts — safer, testable, and cross-platform — without sacrificing the
conciseness that shell users expect.

V scripts (`.vsh` files) follow the same vision: a single binary that
replaces shell scripts with a safer, faster, statically-typed language.
However, V lacked a standard way to run commands and compose them via
pipes. Developers had three unsatisfactory options:

1. **Shell out**: `os.execute('cmd1 | cmd2')` — fragile, OS-dependent
   quoting, inherits all shell injection risks, no separate stderr capture.
2. **Manual `os.Process`**: verbose `new_process`/`set_args`/`set_redirect_stdio`
   boilerplate for every command, no pipe support, easy to forget cleanup.
3. **Don't script**: fall back to Python or bash for glue code, defeating
   the purpose of `.vsh`.

The expected outcome is a zero-overhead, cross-platform command execution
API that feels natural to V developers and makes `.vsh` a credible
alternative to bash/Python for process orchestration.

## Use cases

- **Quick "output or crash"**: `files := vsh.must('ls -la /home')` — single
  line, panic on failure, ideal for setup scripts.
- **Full control**: `res := vsh.sh('git', 'status')` — inspect stdout,
  stderr, exit code separately, no shell involved.
- **Pipelines**: `vsh.cmd('echo', 'hello').pipe('grep', 'h').run()` —
  OS-level parallel pipes without shell or intermediate buffering.
- **Cross-platform**: `/dev/null` on Linux, `NUL` on Windows, handle
  inheritance via `_get_osfhandle`/`SetHandleInformation`.

# Guide-level explanation

## Quick start

```v okfmt
import vsh

// must() — run and get stdout, panic on failure
files := vsh.must('ls -la')
println(files)

// sh() — full control over stdout, stderr, and exit code
res := vsh.sh('echo', 'hello vsh')
println('stdout: ${res.output}')
if !res.success {
	eprintln('exit code: ${res.exit_code}')
	eprintln('stderr: ${res.stderr}')
}

// cmd().pipe().run() — multi-stage pipeline (OS-level pipes)
piped := vsh.cmd('echo', 'hello world').pipe('grep', 'hello').run()
println(piped.output)

// Check if a command exists
if vsh.sh('which', 'docker').success {
	println('docker is available')
}
```

## The three APIs

### `vsh.sh(args ...string) ShOutput`

Runs a command with the given arguments. The first argument is the
executable; the rest are passed as arguments. Returns an `ShOutput`
struct with separate stdout, stderr, and exit code.

- No system shell involved — arguments are passed directly to the
  executable via `os.Process`.
- Stderr is captured separately (not merged with stdout).
- Spawn failure (command not found, permission denied) returns
  `exit_code: -1` with an error message in `.output`.

### `vsh.must(cmd string) string`

Splits `cmd` by whitespace and runs it. Returns stdout on success.
Panics with stderr on failure.

Designed for quick scripts where a failed command should abort the
script. The panic message includes the stderr output.

### `vsh.cmd(args ...string) Cmd`

Creates a `Cmd` builder. Chain `.pipe()` calls and finish with `.run()`.

```v okfmt
import vsh

// Single stage (identical to sh())
single := vsh.cmd('echo', 'hello').run()

// Two-stage pipe: echo → grep (parallel, OS-level pipe)
two_stage := vsh.cmd('echo', 'hello world').pipe('grep', 'hello').run()

// Three-stage pipe
three_stage := vsh.cmd('echo', 'hello world').pipe('grep', 'hello').pipe('wc', '-w').run()
```

For multi-stage pipelines:
- Stages run in parallel with OS-level pipes.
- Stdout of stage N is piped to stdin of stage N+1.
- Intermediate stderr → `/dev/null` (or `NUL` on Windows).
- Only the last stage's stderr is captured.
- The exit code is from the last stage.

## `ShOutput` type

```v okfmt
pub struct ShOutput {
pub:
	output    string
	stderr    string
	exit_code int
	success   bool
}
```

`ShOutput` is a plain struct, not an `Option` or `Result`. This is
intentional for `.vsh` ergonomics: `must()` panics internally when you
want crash-on-failure, and the `success` bool is a simple `if` check
when you don't.

## Extensions to `os.Process`

To enable OS-level pipes, `os.Process` gains three new methods and
three new fields:

```v okfmt
// set_stdin_fd injects a custom fd for the child's stdin.
pub fn (mut p Process) set_stdin_fd(fd int)

// set_stdout_fd injects a custom fd for the child's stdout.
pub fn (mut p Process) set_stdout_fd(fd int)

// set_stderr_fd injects a custom fd for the child's stderr.
pub fn (mut p Process) set_stderr_fd(fd int)
```

Each setter enables `use_stdio_ctl` automatically. The corresponding
fields on `Process` are public so advanced users can set them directly:

```v ignore
pub mut:
    stdin_custom_fd  int = -1
    stdout_custom_fd int = -1
    stderr_custom_fd int = -1
```

**Lifetime contract**: `Process` does **not** take ownership of injected
fds. The caller manages their lifetime. This is by design: pipe fds for
a multi-stage pipeline span multiple Process instances.

# Reference-level explanation

## Single command execution (`sh()` / `must()` / 1-stage `cmd()`)

All three share the same internal `run_internal()` helper:

1. Create an `os.Process` with the given filename and args.
2. Call `p.set_redirect_stdio()` to capture stdout and stderr via pipes.
3. Call `p.wait()` (which spawns and waits).
4. Slurp stdout and stderr via `p.stdout_slurp()` and `p.stderr_slurp()`.
5. Close the process and return `ShOutput`.

Error handling: if the command is not found or cannot be spawned,
`os.Process` sets `p.code = -1` and `p.err` with a system error message.
The `ShOutput` returns `exit_code: -1` and `.success: false`.

## Multi-stage pipeline execution (`cmd().pipe().run()` with N > 1)

### Execution model

1. **Pipe creation**: N-1 `os.Pipe` pairs are created (Unix `pipe(2)`,
   Windows `CreatePipe`).
2. **Parallel spawn**: all N stages are spawned concurrently. Each stage
   gets:
   - stdin from the previous pipe's read end (or inherited for stage 0).
   - stdout to the current pipe's write end (or captured for last stage).
   - stderr to system null device for intermediate stages; captured for
     last stage via `set_redirect_stdio()`.
3. **Immediate fd close**: after spawning each stage, the parent closes
   its copy of the pipe's write end and the `/dev/null` fd. This prevents
   the parent from accidentally keeping the pipe open after the child
   exits.
4. **Read fd close**: after all processes are spawned, the parent closes
   its copies of all pipe read ends.
5. **Reverse wait**: processes are waited on in reverse order (last first).
   This prevents pipe backpressure deadlocks.
6. **Output slurp**: the last stage's stdout and stderr are read **before**
   `process.close()` (which closes the stdio fds).
7. **Cleanup**: all process handles are closed.

### Pipe lifecycle

```
Stage 0 ─stdout→ pipe[0] ─stdin→ Stage 1 ─stdout→ pipe[1] ─stdin→ Stage 2 (last)
                        stderr→ /dev/null         stderr→ /dev/null
```

For each intermediate stage, stderr is redirected to `/dev/null` (or
`NUL` on Windows). This is critical: without it, a stage that writes
more than the OS pipe buffer (typically 64 KB) to stderr would block
forever since nobody reads intermediate stderr pipes. The `/dev/null`
fd is opened before `p.run()` (so the child inherits it) and closed
after `p.run()` (in the parent).

### Why immediate write-end close?

The key deadlock scenario:

```
parent holds write_fd → child's pipe read never sees EOF
                       → parent waits forever on child → DEADLOCK
```

Closing the write end in the parent immediately after spawning ensures
only the child (next stage) holds the write end. When that child exits,
the pipe's read end gets EOF naturally. This avoids needing `O_CLOEXEC`
on the pipe fds.

## Unix implementation (`unix_spawn_process`)

For each stdio channel in the child (after fork):

```v okfmt
if p.stdin_custom_fd != -1 {
	C.dup2(p.stdin_custom_fd, 0)
	fd_close(p.stdin_custom_fd)
} else if use_stdio_ctl {
	// create pipe as before
}
```

After `dup2()`, the original custom fd is closed in the child to prevent
leaking it into the exec'd process. This is safe because `dup2()` already
duplicated the fd to the target number. Same logic applies for
`stdout_custom_fd` (duped to fd 1) and `stderr_custom_fd` (duped to fd 2).

## Windows implementation (`win_spawn_process`)

On Windows, a C runtime fd from `os.create()` must be converted to a
native `HANDLE` for `CreateProcess`:

1. `C._get_osfhandle(fd)` converts the C runtime fd to a Windows `HANDLE`.
2. `C.SetHandleInformation(handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)`
   marks the handle as inheritable — required by `CreateProcess` when
   `bInheritHandles == TRUE`.
3. The handle is assigned to `start_info.h_std_input`/`h_std_output`/
   `h_std_error` (pointer reinterpretation, not truncation — all are
   pointer-sized on x64).
4. On `SetHandleInformation` failure: `p.err` is set with `GetLastError()`,
   `p.status = .aborted`, and spawn returns `-1`. Pipe handles created
   for other channels are cleaned up before returning.
5. On `CreateProcess` failure: pipe handles are cleaned up, `p.err` is
   populated, spawn returns `-1`.

## Spawn error propagation

Before this change, `_spawn()` unconditionally set `p.status = .running`
even when the platform spawn function returned `-1`. This caused `fork()`
or `CreateProcess` failures to be silently ignored.

The fix: `_spawn()` checks `pid < 0` and returns `-1` without touching
`p.status`. `run()` checks the return value and returns early. The error
message is set via `p.err` by the platform-specific spawn function.

## Module structure

```
vlib/vsh/
├── vsh.v          — sh(), must(), Cmd, ShOutput, run_pipe(), run_internal()
├── vsh_test.v     — tests for all APIs
└── README.md      — documentation
```

The module depends on `os` (for `os.Process`, `os.Pipe`, `os.create`,
`os.fd_close`). No external dependencies.

# Drawbacks

1. **New module in vlib**: Every addition to `vlib` increases the
   maintenance surface. The `vsh` module is small (~200 lines of
   implementation) but its correctness depends on low-level fd management
   in `os.Process` across two platforms.

2. **API surface growth on `os.Process`**: The three `set_std*_fd()`
   methods and three new fields add complexity to the already-large
   `Process` struct. The caller-managed fd lifetime contract is unusual
   for V and could be misused.

3. **Windows HANDLE abstraction leak**: `_get_osfhandle` + `&u32` cast
   on Windows is fragile. Currently works under MinGW-w64; status under
   MSVC is unknown.

4. **Intermediate stderr is discarded**: Users who want to inspect
   intermediate stderr for debugging must currently pipe it to
   `/dev/null` unconditionally. No opt-in API exists yet.

5. **Parallel pipe semantics surprise**: Shell users expect `|` to be
   sequential (left-to-right execution). V's parallel pipes are
   semantically identical (OS pipes are parallel in all shells too),
   but the difference matters for side-effect ordering.

# Rationale and alternatives

## Why a new `vsh` module instead of putting this in `os`?

Two options were considered:

- **In `os`**: `os.sh()`, `os.must()`, `os.cmd()`. The convenience API
  would live alongside the low-level `os.Process` type.

- **In `vsh`** (chosen): A dedicated module for shell-like operations,
  keeping `os` focused on low-level OS primitives. The name `vsh` is
  short, memorable, and signals "V shell" to users.

Both approaches are viable. The RFC does not mandate `vsh` over
`os.*` — the core API shape (`sh()`, `must()`, `Cmd` builder, `ShOutput`)
is the important part. If reviewers prefer placing these in `os`, the
rename is mechanical.

## Why `cmd().pipe().run()` and not shell-like string parsing?

The builder pattern is explicit, safe, and requires no parsing.
Shell-like `vsh.pipe('echo hello | grep h')` would need argument
quoting rules, be more complex to implement, and introduce injection
vectors. The builder matches how Rust, Python, and Go handle subprocess
composition.

## Why parallel (OS-level pipes) and not sequential buffering?

- **Zero intermediate buffering**: sequential buffering requires reading
  the entire stdout of stage 1 before feeding it to stage 2. For large
  outputs (e.g. `cat huge_file | head -1`), this is wasteful.
- **Correctness with real-time streams**: Some processes produce output
  indefinitely. Parallel pipes propagate stdin/stdout in real time.
- **Familiar semantics**: OS pipes behave the same as shell pipes.

## Why a plain `ShOutput` struct instead of `Option<ShOutput>`?

`.vsh` scripts prioritise quick, ergonomic code. The `success` bool
provides the same safety as `Option` with less syntactic friction.
`must()` provides panic-on-failure for crash-early scripts.

## What is the impact of not doing this?

`.vsh` would remain limited to single commands via `os.execute()` (with
shell injection risk) or verbose `os.Process` boilerplate. It would
damage V's credibility as a scripting language.

# Prior art

- **Rust**: [`std::process::Command`](https://doc.rust-lang.org/std/process/struct.Command.html)
  is the closest analogue. `.stdout(Stdio::piped())` for fd injection,
  builder pattern, caller-managed fd lifetime. The `must()` pattern
  mirrors Rust's `String::from_utf8(output.stdout).unwrap()`.

- **Python**: [`subprocess.run()`](https://docs.python.org/3/library/subprocess.html#subprocess.run) with `capture_output=True` and
  `subprocess.Popen` chaining. Python's approach is more imperative;
  V's is more concise.

- **Zig**: [`std.process.Child`](https://ziglang.org/documentation/master/std/#std.process.Child) with explicit fd redirection. Zig's
  approach influenced the `set_std*_fd()` API design.

- **Go**: [`os/exec.Cmd`](https://pkg.go.dev/os/exec#Cmd) with `.Stdout`/`.Stdin` assignment. Go requires
  manual pipe plumbing (`cmd1.Stdout = cmd2.Stdin`) which is more
  verbose than V's builder chain.

- **Shell (bash, POSIX sh)**: The ultimate source of pipe semantics. V
  does not replicate shell syntax or globbing, only the OS-level pipe
  behavior.

- **[duct](https://github.com/oconnor663/duct.rs) (Rust)**: A Rust crate
  that provides shell-like pipe composition (`cmd!("echo", "hi").pipe(cmd!("grep", "h"))`)
  with OS-level pipes and no shell. duct's
  API design — a builder that composes subprocess commands via `.pipe()`
  and `.run()` — was a direct influence on the `Cmd` builder chain in
  this RFC. The crate's handling of pipe lifecycle (immediate write-end
  close in the parent, proper fd cleanup) informed the implementation
  design.

- **[zx](https://google.github.io/zx/) (Google)**: A JavaScript/TypeScript
  tool that wraps `child_process` with ergonomic tagged templates
  (`` await $`command arg` ``). zx popularised the idea of writing
  system scripts in a typed language rather than bash. Its influence is
  visible in the naming: `sh()` echoes `$` as the shell invocation,
  `must()` follows the convention of an "abort on failure" convenience
  wrapper seen in zx's `$.nothrow()` / `quiet()` modifiers.

- **[Bun Shell](https://bun.sh/docs/runtime/shell)**: Bun's built-in
  shell (`$` tagged template) provides cross-platform pipe support with
  redirections and environment variables, all without a system shell.
  Bun's approach of treating subprocess pipelines as first-class
  language expressions (rather than string parsing) influenced the
  decision to use a typed builder API rather than shell-string parsing.
  The `Cmd.builder().pipe().run()` pattern mirrors Bun's composability.

### Naming conventions

The function and type names in this RFC draw from prior art across
multiple ecosystems:

| Name | Source | Rationale |
|------|--------|----------|
| `sh` | POSIX shell, zx `$` | Short, matches `.vsh` extension |
| `must` | Rust, zx `$.nothrow()` | "Crash on failure" semantics |
| `Cmd` | Go, Rust `Command` | Standard builder type name |
| `run()` | Rust `Command::run()`, duct | Common "execute pipeline" verb |

# Unresolved questions

1. **Module placement**: Should this be `vlib/vsh/` or live as
   `os.sh()`, `os.must()`, `os.cmd()` in `vlib/os/`? The RFC is
   flexible on this — the API shape is the primary concern.

2. **Input from files**: Should `Cmd` gain a `.stdin(file)` method for
   file redirection? This is the natural next step but is out of scope
   for the initial RFC.

3. **Intermediate stderr**: Should there be an opt-in API to capture
   intermediate stderr? E.g. `cmd(...).capture_stderr(true).pipe(...)`.

4. **Timeout API**: Should `Cmd` support `.timeout(duration)` for
   automatic process termination?

5. **Environment variables**: Should `Cmd` gain `.env(key, val)` for
   per-pipeline environment? Currently environment inheritance from
   the parent process is the only option.

6. **Windows portability**: The `_get_osfhandle` + `SetHandleInformation`
   approach works under MinGW-w64. Its status under MSVC, clang-cl, or
   other Windows toolchains is untested.

# Future possibilities

- **File/pipe redirection**: `.stdin_from(file)`, `.stdout_to(file)`,
  `.stderr_to(file)` on `Cmd`.

- **Timeouts**: `.timeout(duration)` with SIGTERM/`TerminateProcess`.

- **Environment control**: `.env(key, val)` on `Cmd` or per-stage.

- **Working directory per stage**: `.cwd(path)`.

- **Exit code collection**: Access exit codes from all stages (like
  bash's `$PIPESTATUS`).

- **Comptime shell parsing**: A `v pipe('echo hello | grep h')` comptime
  function that parses shell-like pipe syntax at compile time and
  generates the equivalent `cmd().pipe().run()` chain — shell convenience
  without runtime injection risk.

- **Integration with V's test framework**: `vsh.must()` is immediately
  useful in test setup/teardown scripts.
