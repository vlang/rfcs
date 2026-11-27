- Topic Name: `heterogeneous_compute`
- Start Date: 2026-11-27
- RFC PR: [vlang/rfcs#00000](https://github.com/vlang/rfcs/pull/00000)
- V Issue: TBD

# Summary

This RFC proposes a first-class, backend-independent architecture for heterogeneous computing in V. The goal is to let V programs use CPUs, GPUs, and other compute accelerators through explicit, predictable APIs without making a particular vendor SDK, compiler framework, or accelerator runtime mandatory for ordinary V programs.

The proposal has three related but distinct parts:

1. **Host-side compute APIs** for discovering devices, managing device memory, transferring data, submitting work, and synchronizing execution.
2. **A V-native device-kernel model** that allows explicitly marked V functions to be compiled for supported accelerator targets, subject to a documented device-compatible subset of V.
3. **A separate tensor/graph execution model** for accelerators whose programming model is based on tensor operations and compiled computation graphs, including TPU-class systems.

The design deliberately separates the language-facing API, compiler representation, runtime, and target backends. It does not require the existing V compiler backend to be replaced, and it does not require LLVM or MLIR to become mandatory dependencies.

This RFC establishes architectural direction and constraints. It does not freeze the final syntax, public API, intermediate representation, or initial backend list. Those details should be resolved through review and implementation prototypes before stabilization.

# Motivation

V is a general-purpose compiled language whose design emphasizes simplicity, predictable behavior, fast compilation, explicit control, and a small mandatory toolchain. Modern applications increasingly need to use accelerators for graphics-adjacent computation, scientific workloads, image and video processing, simulation, machine learning, and data processing.

Today, V programs can call native libraries and foreign APIs, but relying exclusively on bindings to CUDA, HIP, OpenCL, Vulkan, Metal, or vendor-specific libraries leaves several gaps:

- There is no common V-level model for device discovery, buffers, queues, events, and explicit data transfers.
- Writing a kernel requires switching to another language or maintaining generated source separately from the V program.
- Backend-specific APIs make it difficult to share algorithms across hardware vendors.
- Runtime behavior, memory ownership, synchronization, and error handling are not described by a coherent V-level contract.
- Tensor accelerators such as TPUs do not map naturally to the same execution model as thread-oriented GPU kernels.

The proposal aims to give V programmers a coherent way to express and execute accelerator work while preserving the characteristics that make V useful as a systems and application language.

## Goals

- Provide a coherent, explicit host API for heterogeneous devices.
- Allow selected V functions to be compiled as device kernels without introducing a second general-purpose language.
- Keep host code and device code in the same source-level language while clearly distinguishing their execution environments.
- Define explicit device-memory ownership, data movement, launch, and synchronization semantics.
- Support multiple backends through a capability-aware abstraction rather than a lowest-common-denominator design.
- Keep accelerator toolchains and runtimes optional and isolated from ordinary V builds.
- Leave room for tensor and graph execution models used by TPU and other specialized accelerators.
- Preserve existing V program behavior and avoid mandatory changes to the default compiler pipeline.

## Non-goals

This RFC does not propose:

- Replacing CUDA, HIP, Vulkan, Metal, WebGPU, OpenCL, or other native APIs.
- Guaranteeing identical performance or identical hardware capabilities across all backends.
- Making every V feature available inside device kernels.
- Automatically moving arbitrary V code or data between CPU and accelerators.
- Making GPU or TPU support a mandatory dependency of the V compiler or standard library.
- Requiring a single compiler framework such as LLVM or MLIR for all V targets.
- Defining a complete machine-learning framework, neural-network library, or vendor-specific tensor compiler.
- Requiring TPU support in the first implementation.

# Guide-level explanation

The intended user experience has two separate programming models that share common device and runtime concepts.

## 1. Host-side device and execution API

Ordinary V code is responsible for selecting a device, allocating device memory, transferring data, submitting work, and deciding when results are needed. These operations should be explicit. The runtime must not silently copy arbitrary values between host and device memory.

The following is illustrative API pseudocode. It communicates the intended model and is not a commitment to exact names or syntax:

```v
import compute

fn main() {
    mut device := compute.default_device()!

    mut a := device.alloc[f32](1024)!
    mut b := device.alloc[f32](1024)!
    mut result := device.alloc[f32](1024)!

    device.copy_from_host(mut a, input_a)!
    device.copy_from_host(mut b, input_b)!

    mut queue := device.queue()
    event := queue.dispatch(
        vector_add,
        grid: compute.grid_1d(4),
        block: compute.block_1d(256),
        a,
        b,
        result,
        1024,
    )!

    event.wait()!
    output := device.copy_to_host(result)!
}
```

The API should make the following concepts available, subject to final naming and factoring:

- `Device`: a physical or logical compute device and its capabilities.
- `Buffer[T]`: owned device-accessible storage with a known element type and size.
- `DeviceSlice[T]` or an equivalent view: a bounded view into device storage.
- `Queue`: an ordered submission stream for transfers and compute operations.
- `Event`: a handle representing completion or failure of submitted work.
- `Program` or `Kernel`: a compiled device program and its entry points.
- `Capabilities`: supported features, limits, memory properties, and optional extensions.
- `Dispatch`: launch dimensions and kernel arguments.

The API should use V's normal error-handling conventions for failures such as missing devices, unsupported operations, allocation failures, compilation failures, and execution errors.

## 2. V-native device kernels

A device kernel is an explicitly marked V function compiled for an accelerator target. An attribute is the preferred direction because it makes device execution opt-in and fits V's existing attribute mechanism. The exact attribute name and syntax remain open for review.

Illustrative pseudocode:

```v
@[gpu_kernel]
fn vector_add(
    a gpu.DeviceSlice[f32],
    b gpu.DeviceSlice[f32],
    mut output gpu.DeviceSlice[f32],
    n u32,
) {
    i := gpu.global_id(.x)

    if i < n {
        output[i] = a[i] + b[i]
    }
}
```

The function is still written using V syntax, but it is not an ordinary host function. It is checked and compiled under a device execution model. Device builtins such as global invocation IDs, workgroup IDs, local invocation IDs, barriers, and atomics should be exposed through a small, documented module or intrinsic set rather than through implicit compiler magic.

The compiler must reject operations that are not supported by the selected device execution model. Diagnostics should identify the unsupported operation and, where possible, explain an alternative.

The initial device subset is expected to include scalar integer and floating-point types, booleans, suitable fixed-layout structs, bounded arrays or slices, arithmetic, comparisons, branches, loops, and explicitly supported memory and synchronization operations. Dynamic allocation, operating-system APIs, file and network I/O, strings, maps, goroutines, channels, reflection, and unrestricted dynamic dispatch should be unavailable in the initial kernel model.

This is a proposed starting point, not a final exhaustive list. The accepted subset must be defined precisely and must be validated by the compiler rather than relying on backend-specific errors.

## 3. Tensor and graph execution

Not all accelerators expose a thread-and-workgroup programming model. TPU-class devices commonly execute compiled tensor programs or computation graphs. For that reason, tensor execution should be a separate programming model built on shared device and runtime concepts.

Illustrative pseudocode:

```v
import compute.tensor

fn main() {
    mut graph := tensor.Graph.new()

    a := graph.input[f32]([1024, 1024])!
    b := graph.input[f32]([1024, 1024])!

    c := graph.matmul(a, b)
    d := graph.relu(c)

    program := graph.compile(.xla)!
    result := program.run({
        'a': input_a
        'b': input_b
    })!
}
```

This API is illustrative and is not proposed as part of the first GPU-kernel milestone. Tensor graphs have different constraints from ordinary GPU kernels, including shape specialization, graph-level optimization, and backend-specific operator support. They should not be forced into the same abstraction as a thread-level kernel.

A future implementation could lower a V tensor graph through a portable representation such as StableHLO and execute it through an appropriate runtime such as PJRT/XLA. The architecture should allow this without making XLA a dependency for users who only need GPU kernels.

# Reference-level explanation

## 1. Architectural layers

The implementation should separate the following layers. These are conceptual responsibilities; they do not mandate an exact directory structure or package boundary.

### 1.1 Language and frontend

The existing V parser and type checker should remain the source of truth for V syntax and ordinary language semantics. Device declarations should be recognized through existing language mechanisms where possible, especially attributes and module-level declarations.

The compiler should identify device entry points and the declarations reachable from them. Host and device code must not be confused merely because they appear in the same source file.

### 1.2 Device semantic validation

A device-specific validation pass should check:

- Whether a declaration is permitted in device code.
- Whether called functions are device-compatible.
- Whether types have a supported device representation and layout.
- Whether pointer and slice operations stay within permitted device address spaces.
- Whether synchronization and atomic operations are used in valid contexts.
- Whether the kernel's required capabilities are supported by the selected target.

The pass should operate on typed compiler information rather than attempting to infer validity from generated source text.

### 1.3 Device intermediate representation

The compiler should introduce a target-independent representation for device operations. The representation should be sufficiently explicit to preserve:

- Scalar types and conversions.
- Control flow and function calls.
- Loads and stores.
- Address spaces and memory access properties.
- Kernel entry points and parameters.
- Global, workgroup, and local invocation identifiers.
- Workgroup/shared memory where supported.
- Barriers and atomic operations.
- Required capabilities and resource limits.

The IR should not expose vendor-specific instructions as its only representation. Backend-specific optimizations may introduce target-specific operations in later lowering stages, provided capability requirements remain explicit.

A small V-owned IR is a reasonable starting point. Using MLIR or another compiler framework may be evaluated as an implementation option, but no such framework should be a mandatory dependency of the language or of ordinary V builds solely because this feature exists.

### 1.4 Code generation

Device code generation should be isolated from the existing host backend. Initial code generation can target a portable shader or compute representation, while later backends can target native intermediate languages or toolchains.

Candidate targets include:

- WGSL through WebGPU-compatible runtimes.
- SPIR-V for Vulkan and compatible compute environments.
- PTX for NVIDIA CUDA environments.
- AMDGPU code through HIP/ROCm toolchains.
- MSL and Metal runtime integration for Apple platforms.

The exact supported set must be established by demonstrated implementation and testing. A target must not be advertised as supported merely because source code can be emitted for it.

### 1.5 Runtime and backend interface

The runtime should provide a common host-facing contract for device discovery, resource management, data transfer, queue submission, completion, and error reporting.

Backends should implement this contract while exposing backend-specific capabilities through explicit queries or typed extension APIs. A common interface must not pretend that every backend supports the same limits, memory model, synchronization primitives, or numeric operations.

The initial implementation may use an existing runtime such as `wgpu-native` for a portable end-to-end path. Such a choice is an implementation strategy, not a permanent restriction on the compiler IR or public API. Native CUDA, HIP, Vulkan, and Metal integrations can be added independently.

The runtime should not require every backend to be linked into every V executable. Backend discovery and loading should be optional and should fail with actionable errors when a requested backend is unavailable.

## 2. Kernel execution model

The kernel model should define a launch as an explicit operation with:

- A selected device and queue.
- A kernel entry point.
- A grid or dispatch extent.
- A workgroup or block size where the target model uses one.
- Typed arguments and resource bindings.
- Any required dynamic shared-memory size or equivalent resources.

The compiler and runtime must validate statically knowable constraints at compile time and runtime-dependent constraints before dispatch. Invalid launch dimensions, missing resources, unsupported capabilities, and incompatible argument layouts must produce errors rather than undefined behavior where validation is possible.

The design should distinguish the logical dispatch model from backend-specific execution terminology. For example, CUDA uses grids and blocks, while WebGPU uses workgroups and workgroup sizes. The public abstraction should use concepts that can be mapped explicitly and should not imply that every backend has identical scheduling behavior.

## 3. Device subset and call graph

A kernel and every function reachable from it must satisfy the device subset. A host-only function must not be callable from a kernel. The compiler should report the path from the kernel to the unsupported declaration when practical.

Initial restrictions should favor predictable compilation and portability:

- No implicit heap allocation in device code.
- No operating-system or host-runtime services.
- No strings, maps, channels, goroutines, reflection, or general-purpose dynamic interfaces in the initial subset.
- No unrestricted function pointers or dynamic dispatch.
- No implicit capture of host closures or host variables.
- No implicit host pointer dereferencing from device code.
- No implicit memory transfer or hidden synchronization.

The compiler may later support additional features when their representation and semantics can be defined consistently across supported backends. Unsupported features should fail explicitly rather than silently fall back to host execution.

## 4. Memory, ownership, and safety

Host memory and device memory are distinct resources. The API must make it possible to determine where a buffer resides, who owns it, and when it can be used or released.

The design should specify:

- Ownership and lifetime rules for device allocations.
- Whether and how buffer views borrow their underlying allocation.
- Rules for using a buffer while queued work may still access it.
- Whether host-visible or unified-memory allocations are represented as distinct buffer types or capabilities.
- Alignment, layout, and ABI requirements for types transferred to device memory.
- Bounds behavior for device slices and the guarantees that can be enforced in each backend.
- The behavior of allocation and transfer failures.

The preferred default is explicit allocation and explicit transfer. The implementation should prevent releasing or mutating resources in ways that violate outstanding queue work, using V's ownership and lifetime mechanisms where feasible and runtime validation where compile-time enforcement is not possible.

Device-side pointers must not be treated as ordinary host pointers. Any unsafe escape hatch should be explicit, narrowly scoped, and documented as backend- or device-specific.

## 5. Queues, events, and synchronization

The runtime should define ordering guarantees for operations submitted to a queue. It should support waiting for a specific event and, where useful, waiting for a queue to become idle.

The API should not force a global device synchronization after every dispatch. Synchronization should be explicit and as narrow as possible. Cross-queue dependencies should be represented through events or equivalent dependency primitives.

The semantics of host access to a resource while device work is in flight must be documented. A program must not observe partially written results unless it explicitly uses an API that permits such access.

Kernel-level barriers and atomics are separate from host-side event synchronization and must have clearly documented scopes and memory-order guarantees.

## 6. Capabilities and portability

The portable API should provide capability queries for relevant limits and optional features. Examples include workgroup size limits, supported numeric types, subgroup operations, shared memory, atomic operations, timestamp queries, and specialized matrix instructions.

There should be two levels of portability:

1. **Portable subset:** programs use features supported by the declared baseline and are expected to compile on every backend that claims that baseline.
2. **Capability-specific code:** programs may require optional features and must declare or check those requirements explicitly.

The API should not promise that all devices support the same precision, subgroup width, memory behavior, or performance characteristics.

Compile-time target specialization may be provided where it can be implemented deterministically. Runtime capability checks should remain available when the actual device is not known until execution.

A backend must report unsupported features accurately. It must not silently emulate an operation with materially different semantics or performance unless that emulation is documented and explicitly acceptable.

## 7. Compilation and build integration

The default V build must remain unaffected by unused accelerator functionality. A project that does not import or compile compute features should not need a GPU SDK, shader compiler, vendor driver, or accelerator runtime.

The implementation should define how device artifacts are produced and packaged. The preferred direction is deterministic ahead-of-time compilation when the target toolchain is available, with any runtime compilation or JIT mode being explicit and optional.

Build configuration should make the target backend and relevant compiler/toolchain versions visible. Cached artifacts must account for source code, compiler version, target architecture, backend version, and relevant compile-time options.

Cross-compilation must be considered: building on a machine without the target device should be possible when the necessary target compiler is installed. Running the resulting program may still require a compatible device and runtime.

## 8. Tensor and graph execution boundary

Tensor graph execution should share device discovery, resource ownership, result handling, and backend selection concepts where appropriate. It should not be forced to use the kernel IR if graph-level operations need a different representation.

A future tensor subsystem may define typed tensors, shapes, graph construction, graph compilation, and execution. A backend such as XLA may consume a graph representation such as StableHLO and use a runtime such as PJRT.

This RFC does not standardize a complete tensor operator set or guarantee that every tensor graph can run on every backend. Operator coverage, shape constraints, precision behavior, and graph compilation are backend-specific concerns that must be exposed through capabilities and diagnostics.

## 9. Testing and diagnostics

The feature should be tested in layers:

- Host API and runtime tests that do not require a physical accelerator, using mocks or a software backend where appropriate.
- Device-kernel compile tests for valid and invalid device-subset programs.
- Backend conformance tests for buffer transfers, dispatch, synchronization, errors, and supported capabilities.
- Tests on real hardware for every backend claimed as supported.
- Performance benchmarks that compare equivalent workloads and report hardware, driver, compiler, and runtime versions.

A backend should not be marked fully supported solely because it passes compile-only tests. Support claims should distinguish compile-time support, runtime availability, hardware-tested status, and known limitations.

Compiler diagnostics should identify whether an error comes from V device validation, target code generation, backend compilation, resource validation, or runtime execution.

# Drawbacks

- This feature introduces substantial compiler, runtime, testing, and documentation complexity.
- Device programming has different execution, memory, and synchronization models from ordinary CPU code; a common API can obscure important differences if designed too aggressively.
- A restricted device subset may surprise users who expect every V feature to work in kernels.
- Supporting multiple vendors requires ongoing maintenance as hardware, drivers, toolchains, and standards evolve.
- Some backends require substantial external toolchains and may not be practical to build or test in every CI environment.
- A portable intermediate representation may initially prevent access to some hardware-specific optimizations unless extension mechanisms are designed carefully.
- Runtime compilation can reduce deployment simplicity, while ahead-of-time compilation can make cross-compilation and artifact distribution more complex.
- TPU and tensor-graph support is a significant additional project and should not be mistaken for a small extension to GPU kernels.

# Rationale and alternatives

## Why a layered architecture?

A layered design allows V to share the concepts that genuinely overlap between compute devices while preserving differences in execution models. It also allows the host API, kernel compiler, runtime, and backend implementations to evolve independently.

Keeping accelerator support optional protects the simplicity and build characteristics of ordinary V programs. A separate device compilation path avoids forcing a redesign of the established host compiler backend.

## Alternatives considered

### CUDA-only integration

A CUDA-only design would provide a direct path to NVIDIA hardware and a mature toolchain, but it would make the language feature vendor-specific and would exclude other devices from the core programming model. CUDA can be an important backend without defining the public architecture.

### Foreign-function bindings only

Bindings to CUDA, HIP, OpenCL, Vulkan, or vendor libraries are useful and should remain possible. However, bindings alone do not provide V-native kernel authoring, a common resource model, or compiler-enforced device restrictions.

### WebGPU-only design

WebGPU and WGSL provide a useful portable baseline and are attractive for an initial implementation. However, making WebGPU the permanent abstraction ceiling could limit access to native features and specialized compute capabilities. It should be an initial backend option, not the definition of all V compute semantics.

### Mandatory LLVM or MLIR adoption

LLVM and MLIR provide valuable compiler infrastructure, including GPU-related dialects and transformations. Requiring one of them for all V builds would increase toolchain complexity and could conflict with V's goals of simple, fast, and self-contained compilation. They may be used by optional backends or implementation experiments without becoming mandatory dependencies.

### Automatic CPU/GPU offloading

Automatically moving arbitrary V code to a device would require complex escape analysis, data movement inference, synchronization, and fallback behavior. It would make performance and memory behavior less predictable. This proposal favors explicit kernel declarations, explicit buffers, and explicit dispatch.

### One unified kernel and tensor model

A single model might appear simpler, but thread-oriented kernels and tensor graph compilers have different semantics and optimization requirements. Sharing runtime concepts while keeping the programming models distinct is more honest and extensible.

# Prior art

The proposal draws on the following projects and standards:

- **CUDA:** a mature explicit GPU programming model built around kernels, execution hierarchies, memory spaces, and synchronization. It demonstrates the power and complexity of a native vendor platform.
- **HIP/ROCm:** a vendor-specific GPU platform that illustrates the value of a CUDA-like model beyond NVIDIA hardware.
- **SYCL:** a single-source heterogeneous programming model. Its separation of host and device execution and its capability model are useful references.
- **WebGPU and WGSL:** a portable API and shader language that can provide an approachable initial compute backend, with deliberate limits compared with native vendor APIs.
- **wgpu-native:** a native implementation of the WebGPU API with a C interface, which may reduce the integration burden for an initial V runtime backend.
- **Triton:** a higher-level GPU kernel language and compiler, particularly relevant to tiled computations and machine-learning workloads.
- **CubeCL:** an example of a Rust-based multi-backend compute-kernel abstraction.
- **MLIR GPU dialect:** a reference for representing GPU launch operations, address spaces, and device-specific lowering in compiler infrastructure.
- **OpenXLA, StableHLO, and PJRT:** relevant prior art for tensor graph compilation and execution across accelerator backends, including TPU environments.

These projects are references, not dependencies or specifications that V must reproduce. V should adopt only the concepts that fit its own language and implementation goals.

# Unresolved questions

The RFC process and prototype implementations should resolve at least the following questions before the design is stabilized:

1. What exact attribute syntax should mark a device kernel and device-callable helper functions?
2. Should kernel launch dimensions be passed as named dispatch configuration, declared through attributes, or support both?
3. What is the smallest useful and implementable initial device subset?
4. Which V types should have a guaranteed device ABI, and how should struct layout and alignment be specified?
5. How should bounds checks work in kernels, and what guarantees can be offered across backends?
6. Which ownership and borrowing guarantees can be enforced statically for in-flight device operations?
7. Should the initial portable backend use `wgpu-native`, direct SPIR-V/Vulkan integration, or another implementation?
8. What is the minimal backend conformance suite required before a backend can be called supported?
9. How should backend-specific features be represented without making portable code unreadable?
10. Should the device IR be V-owned, based on an existing framework, or allow multiple lowering paths?
11. How should device artifacts be built, cached, distributed, and cross-compiled?
12. What level of runtime backend loading is appropriate, and should any stable plugin ABI be introduced?
13. Should tensor graph execution be specified in a follow-up RFC after the kernel and runtime foundations are validated?
14. What CI hardware and emulation strategy can provide reliable coverage without requiring every contributor to own accelerator hardware?

# Future possibilities

Once the basic architecture is proven, the following areas may be explored independently:

- CUDA, HIP, Vulkan/SPIR-V, Metal, and additional WebGPU backends.
- Specialized subgroup, warp, wave, cooperative, and matrix operations.
- Shared-memory tiling, asynchronous copies, and target-specific optimization passes.
- Profiling, tracing, kernel debugging, and device-side diagnostics.
- Kernel specialization, tuning, and reproducible artifact caching.
- Multi-device execution and explicit peer-to-peer transfers.
- CPU compute backends for testing and workloads where accelerators are unavailable.
- Tensor operations, graph optimization, and StableHLO/XLA integration.
- TPU and other dataflow/tensor accelerators through dedicated graph-oriented backends.
- Standard libraries for BLAS, FFT, image processing, and other accelerator workloads, preferably by integrating mature native libraries where appropriate.

These possibilities are not commitments made by this RFC. Each requires separate evaluation of semantics, portability, implementation cost, and maintenance burden.

# References

- [V RFC repository and process](https://github.com/vlang/rfcs)
- [V RFC template](https://github.com/vlang/rfcs/blob/master/000-template.md)
- [V contribution guide](https://github.com/vlang/v/blob/master/CONTRIBUTING.md)
- [NVIDIA CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [AMD HIP documentation](https://rocm.docs.amd.com/projects/HIP/en/latest/)
- [Khronos SYCL](https://www.khronos.org/sycl/)
- [WebGPU specification](https://www.w3.org/TR/webgpu/)
- [WGSL specification](https://www.w3.org/TR/WGSL/)
- [wgpu-native](https://github.com/gfx-rs/wgpu-native)
- [Triton](https://triton-lang.org/)
- [CubeCL](https://github.com/tracel-ai/cubecl)
- [MLIR GPU dialect](https://mlir.llvm.org/docs/Dialects/GPU/)
- [OpenXLA](https://openxla.org/)
- [StableHLO](https://openxla.org/stablehlo)
- [PJRT](https://openxla.org/xla/pjrt)
