# Quizz Roadmap

This document defines an incremental implementation order for turning Quizz from a
Raft-shaped proof of concept into a general-purpose **model-based testing (MBT)** library
for Zig allocators, distributed protocols, and single-threaded state machines.

Phases are ordered by **feasibility first**, then **developer experience (DX) impact**.
Each phase should ship independently: tests pass, the Raft example keeps working, and
library consumers gain something concrete.

---

## Scope

Quizz does one thing: **replay Quint ITF traces against a Zig driver and compare spec
state to implementation state at each step.**

```
Quint spec  →  ITF trace  →  quizz.replay  →  state comparison  →  report
```

### In scope

- ITF parsing and trace loading
- Driver contract (step, reset, from_driver)
- Spec ↔ impl state mapping and equality
- Invariant checks during replay (properties defined in the spec, e.g. `electionSafety`)
- Domain adapters (single-process, multi-node cluster, allocator comparison)
- Reports, fixtures, and tooling for the replay loop

### Out of scope

These are separate concerns and belong in other projects or layers:

| Topic | Why it is out of scope |
|-------|------------------------|
| **Property-based testing** | Random sampling, statistical exploration, trace shrinking — Quizz replays concrete traces, it does not generate random test cases |
| **Deterministic simulation testing (DST)** | Virtual clocks, simulated networks, fault injection, seeded schedulers — runtime simulation for `std.Io`-driven code; see [`DST_RESEARCH.md`](./DST_RESEARCH.md) as background only |

Quint provides the model and traces. A future DST toolkit (built on Zig 0.16's `std.Io`)
would simulate the **runtime** your code runs in. Quizz checks whether your **state**
matches the spec. They are complementary but independent.

---

## Guiding Principles

1. **Layer the API** — parse, replay, and run are separate concerns. Consumers should
   not need Quint installed to replay a checked-in trace.
2. **Make the driver contract explicit** — comptime-checked, documented, and enforced.
3. **Fix papercuts before adding features** — metadata loss, manual `state_suffix`, and
   opaque errors block adoption more than missing adapters.
4. **Ship adapters, not examples** — domain patterns (single process, cluster, allocator)
   belong in the library, not copied from `examples/raft`.
5. **Break cleanly while pre-release** — Quizz has no external users yet. Replace old
   APIs in the same phase that introduces the new surface; do not keep shims or dual
   entry points.

---

## Phase Overview

| Phase | Theme | Feasibility | DX Impact | Depends On |
|-------|-------|-------------|-----------|------------|
| 0 | Foundation & API layering | High | High | — |
| 1 | Driver contract & lifecycle | High | High | 0 |
| 2 | State mapping & ITF fidelity | High | High | 0 |
| 3 | Errors, reports & test ergonomics | High | High | 0, 1 |
| 4 | Single-process adapter | Medium | High | 1, 2, 3 |
| 5 | Invariant checking | Medium | Medium | 0, 3 |
| 6 | Cluster driver adapter | Medium | Medium | 1, 2, 3 |
| 7 | Allocator testing oracle | Medium | Medium | 1, 3 |
| 8 | Tooling & codegen | Low | High | 2, 4, 6 |

---

## Phase 0 — Foundation & API Layering

**Goal:** Decouple the library from the CLI runner so Quizz works inside `zig build test`
without Quint on `PATH`.

**Why first:** Highest feasibility, highest DX return. Every later phase builds on a
clean public surface.

### Deliverables

- [ ] `RunOptions` struct (`src/options.zig`) replacing hardcoded Quint flags
  - `spec_path`, `main_module`, `n_traces`
  - `state_suffix` (temporary papercut; removed in Phase 2)
  - `stop_on_first_failure`, `report_path`, `verbosity`
  - `buildQuintArgs()` for testability
- [ ] Replace monolithic `run_test` with three layers:
  - `quizz.Parser.parse` / `quizz.loadTraces` — ITF → `[]Trace`
  - `quizz.replay` — traces + driver → `Report`
  - `quizz.run` — options → generate (Quint) → load → replay → write report
- [ ] Remove `run_test`; migrate `examples/raft/raftdriver.zig` to `quizz.run`
- [ ] Preset profiles: `quizz.options.defaults`, `.quick`, `.thorough`
- [ ] Export from `root.zig`: `RunOptions`, `Report`, `Parser`, `Step`, `replay`,
  `loadTraces`, `run`, `from_spec`, `eqlValue`

### Success Criteria

- Raft example passes via `quizz.run` with `RunOptions`.
- A unit test replays a checked-in ITF fixture with no Quint invocation.
- Quint flags are no longer hardcoded in `runner.zig`.

---

## Phase 1 — Driver Contract & Lifecycle

**Goal:** Make the driver interface explicit, comptime-checked, and safe to use across
multiple traces in one test run.

**Why now:** Without `reset()` and ownership rules, multi-trace replay and library
embedding are fragile regardless of domain.

### Deliverables

- [ ] `quizz.defineDriver(comptime Driver: type) type` — comptime validation of:
  - `State`, `step`, `from_driver`, `reset`
  - optional: `deinitState`, `compare`
- [ ] Document the driver contract in README (3 required methods + optional hooks)
- [ ] `driver.reset()` called automatically before each trace replay
- [ ] `State.deinit(gpa)` convention documented; helper in `state.zig` for HashMap-heavy
  states
- [ ] `quizz.replayWithLeakCheck(gpa, driver, traces)` — optional `DebugAllocator` wrapper
  for test suites
- [ ] Per-trace scratch arena inside `replay` (already partially present; formalize and
  document)

### Success Criteria

- A comptime error fires when a driver is missing `reset`.
- Replaying 16 traces in one test produces zero leaks on success.
- Raft driver updated to the formal contract.

---

## Phase 2 — State Mapping & ITF Fidelity

**Goal:** Remove manual `state_suffix` and preserve ITF metadata so spec ↔ impl mapping
is discoverable, not guessed.

**Why now:** `state_suffix = "raft_test::raft"` is the biggest papercut for new users.
Fixing ITF metadata loss is a known bug with low risk and high clarity gain.

### Deliverables

- [ ] Preserve top-level trace metadata (`#meta`, `vars`, `loop_index`) in `Trace`
- [ ] Preserve per-state `#meta` fields in `State.meta`
- [ ] Declarative field mapping on driver `State` fields:
  ```zig
  currentTerm: std.StringHashMap(i64) = .{ .quizz = "currentTerm" },
  // or full path override:
  role: std.StringHashMap(NodeRole) = .{ .quizz = "raft_test::raft::role" },
  ```
- [ ] Auto-discovery mode: infer Quint prefix from ITF `vars` and match struct fields by
  suffix or exact name
- [ ] Filter spec variables: ignore `mbt::actionTaken`, `mbt::nondetPicks`, and other
  internal keys when building comparable state
- [ ] Deprecate free-form `state_suffix` parameter; remove in a later release

### Success Criteria

- Raft example works with zero hardcoded namespace strings.
- Parsed trace exposes `vars` and metadata for debugging / UI.
- Unit tests cover auto-mapping, explicit override, and prefixed Quint modules.

---

## Phase 3 — Errors, Reports & Test Ergonomics

**Goal:** Make failures actionable and reports stable enough for tooling (CI, replay UI,
IDE integration).

**Why now:** High feasibility, directly improves daily use for every domain. Should land
before adapters so they inherit good diagnostics from day one.

### Deliverables

- [ ] Structured error type:
  ```zig
  pub const MismatchError = struct {
      trace_index: usize,
      state_index: usize,
      action: []const u8,
      field: ?[]const u8,
      spec_fragment: []const u8,
      driver_fragment: []const u8,
  };
  ```
- [ ] Versioned `Report` schema (`schema_version: "1"`) written to `quizz_run.json`
- [ ] `stop_on_first_failure: false` — collect all mismatches per run
- [ ] Checked-in ITF fixtures under `tests/fixtures/` with offline replay tests
- [ ] Human-readable failure summary on stderr (trace, step, action, first differing field)
- [ ] Update replay viewer to consume versioned report schema (see [`REPLAY_UI_PLAN.md`](./REPLAY_UI_PLAN.md))
- [ ] `src/log.zig` — verbosity-controlled logging (`.quiet`, `.normal`, `.verbose`)

### Success Criteria

- A failing replay prints which field diverged without opening JSON.
- CI runs fixture replay tests with no Quint dependency.
- Replay UI renders multi-trace, multi-failure reports.

---

## Phase 4 — Single-Process Adapter

**Goal:** Make the common case — one state machine, one thread — require minimal boilerplate.

**Why now:** Medium feasibility, very high DX for the widest audience (FSMs, parsers,
protocol logic in one process). Builds directly on Phases 1–3.

### Deliverables

- [ ] `quizz.SingleProcessDriver(comptime Impl: type, comptime actions: anytype) type`
  - wraps `dispatch` / `case` machinery
  - requires `Impl.snapshot(gpa) !State` instead of hand-rolled `from_driver`
- [ ] Minimal example: counter / mutex / small FSM spec (new `examples/counter/`)
- [ ] Template driver in docs showing ~30 lines for a new spec
- [ ] README section: "Testing a single state machine"

### Success Criteria

- New counter example is < 100 lines total (spec + driver + impl).
- Counter example uses `SingleProcessDriver` with no HashMap-of-nodes pattern.
- Existing Raft example unchanged until Phase 6.

---

## Phase 5 — Invariant Checking

**Goal:** Assert spec-defined properties on driver state during trace replay, in addition
to step-by-step state equality.

**Why now:** Quint specs already define invariants (e.g. Raft `electionSafety`). Checking
them on the implementation during replay catches bugs that a single field mismatch might
not surface clearly. This is still MBT — invariants are evaluated on each replay step,
not via random exploration.

### Deliverables

- [ ] Invariant hooks on driver or `RunOptions`:
  ```zig
  invariants: []const fn (*Driver) bool,
  ```
- [ ] Accept explicit invariant list in `RunOptions` (names for reporting)
- [ ] Run invariants on driver state after every replay step
- [ ] Report invariant violations separately from state mismatches in `quizz_run.json`

### Success Criteria

- Raft `electionSafety` equivalent checked on driver state each step.
- Invariant failure produces a clear report entry (trace, step, invariant name).
- Invariants are optional — drivers with none behave exactly as today.

---

## Phase 6 — Cluster Driver Adapter

**Goal:** Reduce boilerplate for multi-node specs where Quint models global map-shaped
state (`NodeId → Term`, `NodeId → Role`, etc.) and the driver holds one impl per node.

**Why here:** Medium feasibility. The Raft example already works via direct trace replay;
this phase only standardizes the pattern. No simulated network or virtual clock — actions
from the trace are applied directly to nodes, as today.

### Deliverables

- [ ] `quizz.ClusterDriver(comptime NodeImpl: type, comptime actions: anytype) type`
  - manages `StringHashMap(NodeImpl)` keyed by node ID
  - wires `dispatch` / `case` for cluster-wide actions
  - provides a default `from_driver` projection for map-shaped `State` fields
- [ ] Refactor Raft example to use `ClusterDriver` (behavior unchanged)
- [ ] Document cluster driver pattern: global spec state ↔ per-node impl state
- [ ] README section: "Testing a multi-node protocol"

### Success Criteria

- Raft example uses `ClusterDriver`; line count in `raftdriver.zig` drops meaningfully.
- All existing Raft replay tests pass unchanged.
- A new user can scaffold a 3-node cluster driver without copying Raft boilerplate.

---

## Phase 7 — Allocator Testing Oracle

**Goal:** Support testing Zig allocators against abstract allocation models where full
state equality is awkward or insufficient.

**Why here:** Medium feasibility, domain-specific. Needs pluggable comparison (Phase 3
patterns) and lifecycle hooks (Phase 1).

### Deliverables

- [ ] `quizz.AllocationTracker` — wrap any `Allocator`, record alloc/free/realloc/alignment
- [ ] `quizz.AllocatorOracle` — compare live block set, peak usage, alignment violations
- [ ] Pluggable comparison in `RunOptions`:
  ```zig
  compare: union(enum) {
      state_equality,
      custom: *const fn (spec: State, impl: State) CompareResult,
      allocation: AllocatorOracleConfig,
  },
  ```
- [ ] Example: `examples/arena/` or `examples/bump/` with Quint spec modeling block IDs
- [ ] Checks: no double-free, no use-after-free, no leak at trace end

### Success Criteria

- Example allocator passes replay on valid traces and fails on an intentional leak bug.
- Comparison mode is swappable without changing replay loop structure.
- Report distinguishes allocation failures from state mismatches.

---

## Phase 8 — Tooling & Codegen

**Goal:** Reduce manual duplication between Quint specs and Zig drivers.

**Why last:** Lowest feasibility, depends on stable field mapping (Phase 2) and adapter
patterns (Phases 4, 6). Highest long-term DX once the runtime library is mature.

### Deliverables

- [ ] `quizz init` — scaffold spec + driver + test from template (CLI or build step)
- [ ] Quint → Zig codegen spike: emit `State` struct fields from spec variables
- [ ] Quint → Zig codegen: emit action dispatch table skeleton from spec actions
- [ ] Package layout: publish examples as copyable templates, not repo-internal only
- [ ] Stable `quizz_run.json` JSON Schema published for third-party tools

### Success Criteria

- `quizz init my_fsm` produces a compiling project that passes a trivial replay test.
- Codegen-generated Raft `State` matches hand-written `SpecState` (diff test).
- External tools can validate reports against published schema.

---

## Cross-Cutting Work (ongoing)

These items span phases and should be addressed as each phase lands:

| Item | Target Phase | Notes |
|------|--------------|-------|
| README rewrite for library consumers | 0, 4 | Quick start, API reference |
| `build.zig.zon` paths include examples/templates | 4, 8 | Package manager consumers |
| Replay UI parity with report schema | 3 | See [`REPLAY_UI_PLAN.md`](./REPLAY_UI_PLAN.md) Phase 3 |
| Comptime driver validation tests | 1 | Compile-fail tests for bad drivers |
| Memory ownership docs | 1, 2 | When to `dupe`, when scratch arena suffices |
| AGENTS.md update | each phase | Keep AI/dev guidance in sync |

---

## Dependency Graph

```
Phase 0 (API layering)
    ├── Phase 1 (driver contract)
    │       ├── Phase 4 (single-process adapter)
    │       ├── Phase 6 (cluster adapter)
    │       └── Phase 7 (allocator oracle)
    ├── Phase 2 (state mapping)
    │       ├── Phase 6 (cluster adapter)
    │       └── Phase 8 (codegen)
    └── Phase 3 (errors & reports)
            ├── Phase 5 (invariant checking)
            ├── Phase 6 (cluster adapter)
            └── Phase 7 (allocator oracle)
```

---

## Recommended First Milestone (MVP Library)

Ship Phases **0 + 1 + 2 + 3** as the first library milestone. At that point Quizz is:

- Usable from `zig build test` without Quint (fixture replay)
- Explicit about driver requirements
- Free of manual namespace suffixes
- Actionable on failure

Phases 4–7 extend domain coverage (single process, invariants, cluster, allocators).
Phase 8 is tooling and automation.

---

## Related Documents

- [`REPLAY_UI_PLAN.md`](./REPLAY_UI_PLAN.md) — native macOS replay viewer (Zig)
- [`README.md`](../README.md) — current user-facing documentation (update per phase)
- [`DST_RESEARCH.md`](./DST_RESEARCH.md) — background research only; out of scope for Quizz
