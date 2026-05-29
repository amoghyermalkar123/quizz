# Phase 0 — Foundation & API Layering

Step-by-step guide to complete [Phase 0 in ROADMAP.md](./ROADMAP.md). Read that section first for
goal, deliverables, and success criteria.

**Goal:** Decouple the library from the CLI runner so Quizz works inside `zig build test` without
Quint on `PATH`.

**End state:** Three public layers — parse/load, replay, run — plus configurable options.
`run_test` is removed; Raft calls `quizz.run` directly.

**Pre-release API policy:** Quizz has no external users. Phase 0 deletes `run_test` and migrates
call sites in the same PR — no shims, no dual entry points. See [Guiding Principles](./ROADMAP.md#guiding-principles) in ROADMAP.

---

## Current Baseline (before you start)

```
src/
  root.zig      — Trace, State, Values, Parser (partial); exports only run_test (to be removed)
  runner.zig    — monolithic run_test: generate → load → replay → write report
  driver.zig    — Step, dispatch, case
  state.zig     — from_spec (private to module)
  eql.zig       — eqlValue (private to module)
  json.zig      — JSON helpers for reports
```

What already exists (reuse, do not rewrite):

| Piece | Location | Notes |
|-------|----------|-------|
| ITF parsing | `Parser.parse`, `Parser.parseState` in `root.zig` | JSON → `ItfTrace`, then per-state `State` |
| Trace loading loop | `load_traces` in `runner.zig` | Private; reads `*.itf.json` from a directory |
| Replay loop | `replay_traces` in `runner.zig` | Public in file but not exported from `root.zig` |
| Quint invocation | `generate_traces` in `runner.zig` | Hardcoded `--n-traces=16`, `--mbt`, main module |
| Report writing | `writeReplayReport` | Inline `StepReport` struct, writes `quizz_run.json` |
| Monolithic entry | `run_test(gpa, io, driver, spec, state_suffix)` | Used by `examples/raft/raftdriver.zig`; **delete in Phase 0** |

What is missing for Phase 0:

- `src/options.zig` with `RunOptions` and preset profiles
- Public `loadTraces`, `replay`, `run`
- Exported `Report`, `Step`, `from_spec`, `eqlValue`
- Configurable Quint flags (no hardcoding in `runner.zig`)
- Offline fixture replay test (no Quint)
- Remove `run_test`; migrate Raft to `quizz.run`

---

## Architecture Target

```
                    ┌─────────────────────────────────────┐
                    │  quizz.run(gpa, io, driver, opts)   │
                    │  options → generate → load → replay │
                    └──────────────┬──────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          ▼                        ▼                        ▼
   generate (Quint)         loadTraces                 replay
   RunOptions.buildQuintArgs   Parser + dir scan      driver + compare
          │                        │                        │
          └────────────────────────┴────────────────────────┘
                                   ▼
                            Report → quizz_run.json
```

There is no compatibility shim. Callers use `quizz.run` (full pipeline) or `quizz.replay`
(fixtures / tests) directly.

## Step A — Create `RunOptions` (`src/options.zig`)

1. Add `src/options.zig`.
2. Define `RunOptions`:

   ```zig
   pub const RunOptions = struct {
       spec_path: []const u8,
       main_module: ?[]const u8 = null,   // default: derive from spec stem + "_test"
       n_traces: u32 = 16,
       state_suffix: ?[]const u8 = null,  // temporary; removed in Phase 2
       stop_on_first_failure: bool = true,
       report_path: []const u8 = "quizz_run.json",
       verbosity: Verbosity = .normal,

       pub const Verbosity = enum { quiet, normal, verbose };
   };
   ```

3. Add `buildQuintArgs(self, gpa, out_prefix: []const u8) ![]const []const u8`:
   - Resolve `main_module` via `deriveMainModuleName` (move from `runner.zig` or call shared helper).
   - Build argv slice: `"quint", "run", spec_path, "--main", main, "--mbt", n-traces, out-itf`.
   - Return owned strings where needed; document caller frees with `freeQuintArgs` or use arena.

4. Add preset profiles in the same file:

   ```zig
   pub const defaults = RunOptions{};
   pub fn quick(spec_path: []const u8) RunOptions { ... n_traces = 4 ... }
   pub fn thorough(spec_path: []const u8) RunOptions { ... n_traces = 64 ... }
   ```

5. Unit test `buildQuintArgs`: assert flag count, `--n-traces=4` for `.quick`, main module derivation.

**Checkpoint:** `zig build test` compiles with `options.zig` imported nowhere yet.

---

## Step B — Extract and export `Report`

1. Move the inline `StepReport` struct and the trace-keyed report map out of `replay_traces`.
2. Create a public `Report` type (new file `src/report.zig` or top of `runner.zig`):

   ```zig
   pub const StepReport = struct {
       state_index: usize,
       action: []const u8,
       matched: bool,
       spec_state_json: []const u8,
       driver_state_json: []const u8,
   };

   pub const Report = struct {
       traces: std.StringHashMap(std.ArrayList(StepReport)),
       // deinit, jsonStringify
   };
   ```

3. Keep JSON shape compatible with today's `quizz_run.json` so the replay UI still works.
4. Export `Report` and `StepReport` from `root.zig`.

**Checkpoint:** Existing replay output byte-for-byte equivalent (or diff only whitespace).

---

## Step C — Public `loadTraces`

1. Rename/move `load_traces` + `parse_trace_file` + `deinitTrace` into a dedicated surface:
   - Either keep in `runner.zig` and re-export, or add `src/load.zig`.
2. Public signature:

   ```zig
   pub fn loadTraces(
       gpa: std.mem.Allocator,
       io: std.Io,
       trace_dir_path: []const u8,
   ) ![]Trace
   ```

   - Caller owns returned slice; provide `deinitTraces(gpa, traces)` or document `defer` loop.
3. Optionally add `loadTraceFile(gpa, io, filepath) !Trace` for single-file fixtures.
4. Export from `root.zig`.

**Checkpoint:** Small test loads a directory with one `.itf.json` and asserts `states.len > 0`.

---

## Step D — Public `replay`

1. Refactor `replay_traces` → `replay`:

   ```zig
   pub fn replay(
       gpa: std.mem.Allocator,
       io: std.Io,
       driver: anytype,
       traces: []const Trace,
       opts: ReplayOptions,
   ) !Report
   ```

   where `ReplayOptions` holds at least `state_suffix` and `stop_on_first_failure` (subset of
   `RunOptions`, or pass `RunOptions` directly).

2. **Do not write files inside `replay`.** Return `Report`; let `run` (or the caller) write JSON.
   This is the key layering win — tests call `replay` without side effects.

3. Move report-writing logic to `writeReport(gpa, io, report, path)`.

4. Export `replay` and `Step` from `root.zig` (`Step` already lives in `driver.zig`).

**Checkpoint:** Call `replay` from a test with in-memory traces; assert `Report` contents, no
`quizz_run.json` created unless test asks for it.

---

## Step E — Public `run` (orchestrator)

1. Implement `run`:

   ```zig
   pub fn run(
       gpa: std.mem.Allocator,
       io: std.Io,
       driver: anytype,
       opts: RunOptions,
   ) !void
   ```

2. Body (same temp-dir pattern as today, but driven by `opts`):
   - Create temp dir under `tmp/quizz-{random}`.
   - Call Quint with `opts.buildQuintArgs(...)`.
   - `const traces = try loadTraces(gpa, io, tmp_dir); defer deinitTraces(...)`.
   - `const report = try replay(gpa, io, driver, traces, opts);`
   - `try writeReport(gpa, io, report, opts.report_path);`
   - Return `error.TraceFailed` (or first mismatch error) when `stop_on_first_failure` and a step
     failed.

3. Remove hardcoded `--n-traces=16` and main-module logic from `generate_traces`; delegate to
   `RunOptions`.

4. Export `run` and `RunOptions` from `root.zig`.

**Checkpoint:** `zig build run -- examples/raft/spec/raft.qnt` still produces a passing run.

---

## Step F — Remove `run_test` and migrate Raft

1. Update `examples/raft/raftdriver.zig` to call `quizz.run`:

   ```zig
   try quizz.run(gpa, io, &driver, .{
       .spec_path = spec_path,
       .state_suffix = state_suffix,
   });
   ```

   Or use a preset: `quizz.options.defaults(spec_path)` with `.state_suffix` overridden.

2. Delete `run_test` from `runner.zig` and remove its export from `root.zig`.

3. Grep the repo for `run_test` — README, AGENTS.md, comments — and update references to
   `quizz.run`.

**Checkpoint:** `zig build run -- examples/raft/spec/raft.qnt` passes; `grep run_test` returns
nothing outside git history.

---

## Step G — Export remaining public surface

Update `root.zig` exports to match ROADMAP:

```zig
pub const RunOptions = @import("options.zig").RunOptions;
pub const options = @import("options.zig"); // presets: .defaults, .quick, .thorough
pub const Report = @import("report.zig").Report; // or runner.Report
pub const Parser = ...; // already in root
pub const Step = @import("driver.zig").Step;
pub const replay = @import("runner.zig").replay;
pub const loadTraces = @import("runner.zig").loadTraces; // or load.zig
pub const run = @import("runner.zig").run;
pub const from_spec = @import("state.zig").from_spec;
pub const eqlValue = @import("eql.zig").eqlValue;
```

Re-export types already on `root.zig`: `Trace`, `State`, `Values`, `QuizDriver` / driver helpers.

**Checkpoint:** External module can `const quizz = @import("quizz");` and use all symbols above.

---

## Step H — Checked-in ITF fixtures

1. Create `tests/fixtures/` (or `testdata/` — pick one and stay consistent).
2. Add at least one minimal ITF file (2–3 states). Options:
   - Run Quint once locally and commit output, or
   - Hand-author a tiny valid ITF JSON matching `ItfTrace` schema.
3. Include variables your test driver expects (`mbt::actionTaken`, spec fields).

Suggested layout:

```
tests/fixtures/
  counter_minimal.itf.json   # 2 states, 1 action — good for unit replay
```

**Checkpoint:** `Parser.parse` + `loadTraces` succeed on the fixture without Quint.

---

## Step I — Offline replay unit test

Add a test in `src/runner.zig` (or `tests/replay_test.zig` wired in `build.zig`):

1. Define a minimal comptime driver inline (counter or noop FSM):
   - `State` struct with one field.
   - `step`, `from_driver`, no Quint needed.
2. `const traces = try loadTraces(..., "tests/fixtures");`
3. `const report = try replay(gpa, io, &driver, traces, .{ ... });`
4. Assert all steps `matched == true`.
5. **Do not** call `run` or `generate_traces` — this proves offline replay.

Wire the fixture path via `b.path("tests/fixtures/...")` in `build.zig` if tests need a known
cwd, or embed fixture bytes with `@embedFile`.

**Checkpoint:** `zig build test` passes on a machine with **no Quint installed**.

---

## Step J — Preset profile smoke test

1. Test `options.quick("spec.qnt").n_traces == 4` (or chosen value).
2. Test `buildQuintArgs` for `.thorough` includes higher trace count.
3. Optional integration test: `run` with `.quick` if Quint is available (guard with `if (detectQuint())`).

---

## Step K — Verbosity hooks (minimal)

Phase 0 only needs the enum on `RunOptions`; full logging lands in Phase 3. For now:

- `.quiet` — suppress `std.debug.print` on success paths.
- `.normal` — print failure summary (keep today's `"trace failed, states don't match"`).
- `.verbose` — print trace count, temp dir, quint argv.

Do not add `src/log.zig` yet unless you want a stub; ROADMAP assigns that to Phase 3.

---

## Step L — `build.zig` adjustments

1. Ensure module tests include fixture path if using relative paths from cwd.
2. Optionally add a dedicated test step for offline replay only.
3. Raft executable calls `quizz.run` — no `run_test` anywhere.

---

## Step M — Documentation touch-ups (minimal)

Per ROADMAP cross-cutting table, a full README rewrite spans Phases 0 and 4. For Phase 0, add:

1. **README** — Replace `run_test` examples with `quizz.run` and add a library-only snippet:

   ```zig
   const report = try quizz.replay(gpa, io, &driver, traces, .{ .state_suffix = "..." });
   try quizz.run(gpa, io, &driver, .{ .spec_path = "spec.qnt", .state_suffix = "..." });
   ```

   Note that `run` requires Quint while `replay` + fixtures do not.

2. **AGENTS.md** — Update architecture section: list new modules and public API.

Do not rewrite the full README yet.

---

## Verification Checklist (Phase 0 complete when all pass)

| # | Criterion | How to verify |
|---|-----------|---------------|
| 1 | Raft via `quizz.run` | `zig build run -- examples/raft/spec/raft.qnt` |
| 2 | No `run_test` | `grep -r run_test .` returns nothing (excluding `.git`) |
| 3 | Offline replay | `zig build test` with Quint **not** on PATH |
| 4 | No hardcoded Quint flags | `grep -n "n-traces=16" src/runner.zig` returns nothing; only `options.zig` / `buildQuintArgs` |
| 5 | Public exports | All symbols in ROADMAP Phase 0 export list reachable from `quizz` module |
| 6 | Report compatibility | `quizz_run.json` still loads in prototype replay UI (smoke test) |
| 7 | Layer separation | `replay` returns `Report` without writing files; `run` orchestrates |

---

## Suggested File Layout After Phase 0

```
src/
  root.zig       — re-exports only
  options.zig    — RunOptions, presets, buildQuintArgs
  report.zig     — Report, StepReport, writeReport (optional split)
  runner.zig     — run, replay, generate_traces
  load.zig       — loadTraces, deinitTraces (optional split from runner)
  driver.zig     — Step, dispatch, case
  state.zig      — from_spec
  eql.zig        — eqlValue
  json.zig       — unchanged
tests/
  fixtures/
    counter_minimal.itf.json
```

Splitting `load.zig` / `report.zig` is optional; keeping them in `runner.zig` is fine if files stay
under ~350 lines.

---

## Implementation Order (dependency-safe)

```
A (options) ──► E (run) ──► F (remove run_test, migrate Raft)
B (report)  ──► D (replay) ──┘
C (loadTraces) ──► D ──► I (offline test)
G (exports) — after D, E, F
H (fixtures) — before I
J, K, L, M — parallel once core API lands
```

Recommended single-PR sequence: **A → B → C → D → E → F → G → H → I → verify**.

---

## Common Pitfalls

1. **Double-free on report keys** — existing comment in `replay_traces` around `trace_key`; preserve
   the `getOrPut` ownership pattern when extracting `Report`.

2. **Replay writes side effects** — tests become flaky if `replay` always writes `quizz_run.json`.
   Only `run` (or explicit `writeReport`) should touch the filesystem.

3. **Trace ownership** — document who calls `deinitTrace` / `deinitTraces`; `loadTraces` allocator
   contract must match `run`'s defer chain.

4. **Io parameter** — public APIs should take `io: std.Io` consistently (Zig 0.16 `std.Io` model);
   match the signature used by `run`.

5. **Comptime driver type** — `replay` uses `Driver.State` from `@TypeOf(driver)`; keep the same
   inference as today's `replay_traces`.

---

## What Phase 0 Deliberately Defers

| Item | Phase |
|------|-------|
| `defineDriver` comptime validation | 1 |
| `driver.reset()` between traces | 1 |
| Auto field mapping / no `state_suffix` | 2 |
| Structured `MismatchError`, report schema version | 3 |
| `src/log.zig` | 3 |
| Single-process / cluster adapters | 4, 6 |

---

## Next Step After Phase 0

Proceed to [Phase 1 — Driver Contract & Lifecycle](./ROADMAP.md#phase-1--driver-contract--lifecycle):
`defineDriver`, mandatory `reset`, leak-checked replay, ownership docs.

The recommended MVP milestone is Phases **0 + 1 + 2 + 3** before investing in domain adapters.
