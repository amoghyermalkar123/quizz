# Replay UI Plan

Native macOS replay viewer for Quizz, implemented in **Zig**. Replaces the legacy web
prototype at `prototype/replay-ui/`.

This document is the implementation plan. No UI code ships until the data layer (Phase 1)
is tested.

---

## Purpose

Inspect output from Quizz replay runs — primarily `quizz_run.json` — without a browser.

The viewer is **read-only**. It does not run Quint, generate traces, or execute drivers.
It loads a report, lets you step through actions, and compares spec state to driver state
at each step.

---

## Scope

### In scope

- Load `quizz_run.json`
- Event stream sidebar (per trace, per step)
- Transport controls (back, forward, scrub, play/pause)
- Side-by-side spec vs driver state panes
- Path-level diff highlighting
- Inspector for the selected step (action, trace id, indices, match status)
- macOS desktop app (local binary / `.app` bundle)

### Out of scope (for now)

- Running `quizz run` from inside the UI
- Live reload / file watching
- Raw ITF trace viewing (Phase 5 optional)
- Web UI maintenance (`prototype/replay-ui/` is deprecated)

---

## Technology Choice

**UI:** [Gooey](https://github.com/duanebester/gooey) — the only UI stack for v1. No fallback
toolkit (no ImGui, no zgui, no GLFW).

**Diff:** external **CLI tool** ([jd](https://github.com/josephburnett/jd) by default) invoked via
`std.process` — stdout parsed into `UiDiff`. No custom diff engine, no vendored Zig diff sources.

### Gooey

[Gooey](https://github.com/duanebester/gooey) is a hybrid immediate/retained Zig UI framework with
**macOS/Metal** as a first-class target. Relevant to this viewer:

- **CoreText** monospace rendering on macOS
- **Scroll containers** and **virtualized lists** (`run-uniform-list`, `run-data-table`) for the
  event stream and long JSON panes
- **Native file open dialogs** (`run-file-dialog`) — no Cocoa glue required
- **Actions & keybindings** — ⌘O, ←/→, space map cleanly to `Cx` actions
- **Light/dark theming** built in
- **`run-code-editor`** example — potential base for syntax-highlighted JSON panes

Tradeoffs: API marked *early development* (evolving), Zig 0.15.2+ (aligns with Quizz).

**Decision:** Gooey for all UI on macOS. The data layer (`report`, `diff_cli`, `format`) stays
separate from Gooey view code under `apps/replay/ui/` for testability — headless tests can
parse CLI JSON output without a window.

---

## Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Open…  │  ◀  ▶  ⏸  │  ───●──────────  │  Passed / Failed   │
├──────────────┬──────────────────────────┬───────────────────┤
│ Summary      │  Spec State  │ Driver     │ Inspector         │
│              │              │ State      │                   │
│ Event stream │  (monospace, │ (monospace,│ Action: grantVote │
│ ● init       │   scroll)    │  scroll)   │ Trace: trace_11   │
│ ● stutter    │              │            │ Step: 10          │
│ ● grantVote  │  diff paths  │ diff paths │ 3 differing paths │
│   (mismatch) │  highlighted │ highlighted│                   │
└──────────────┴──────────────────────────┴───────────────────┘
```

### Regions

| Region | Content |
|--------|---------|
| **Toolbar** | Open file, transport, step scrubber, run status |
| **Sidebar** | Trace summary + scrollable event list with match/mismatch indicators |
| **Center** | Two synchronized scroll panes: spec state (left), driver state (right) |
| **Inspector** | Metadata for the selected step |

### Keyboard shortcuts (target)

| Key | Action |
|-----|--------|
| ⌘O | Open report |
| ← / → | Previous / next step |
| Space | Play / pause |

---

## Architecture

UI lives in a separate executable under `apps/replay/`. It **imports the `quizz` module**
for parsing and types — no duplicate JSON logic in the UI layer.

```
quizz/ (library)                 apps/replay/ (executable)
├── root.zig                     ├── main.zig           Gooey app + event loop
├── Parser.parseValue            ├── app.zig            session + playback state
├── json.zig                     ├── report.zig         quizz_run.json → Session
├── Values                       ├── format.zig         Values → monospace lines
└── (future Report type)         ├── diff_cli.zig       spawn CLI, parse stdout → UiDiff
                                 └── ui/                Gooey-specific views (swappable)
                                     ├── sidebar.zig
                                     ├── compare.zig
                                     ├── inspector.zig
                                     └── transport.zig
```

### Data types (UI layer)

```zig
pub const ReplayStep = struct {
    replay_index: usize,
    trace_key: []const u8,
    state_index: usize,
    action: []const u8,
    matched: ?bool,
    spec_json: []const u8,       // written to temp file for diff CLI
    driver_json: ?[]const u8,
    spec_state: quizz.Values,    // for format.zig display
    driver_state: ?quizz.Values,
};

pub const ReplaySession = struct {
    source_path: ?[]const u8,
    steps: []ReplayStep,
    trace_keys: []const []const u8,
    has_mismatch: bool,
};
```

Report parsing starts in `apps/replay/report.zig`. Once the report schema is versioned
(see [ROADMAP.md](./ROADMAP.md) Phase 3), promote `Report` into `quizz` proper.

---

## Loading JSON

Two file types, two code paths. Both use Zig 0.16's `std.Io` for file I/O (same pattern as
`quizz.Parser.parse` in `src/root.zig`).

### `quizz_run.json` (v1 — primary)

Written by `runner.zig` via `quizz_json.valueAlloc` on a `StringHashMap` of step reports.
Each step's `spec_state` and `driver_state` are **Driver.State structs serialized to JSON
objects** (plain JSON — not ITF `#bigint` / `#map` wrappers).

**Load pipeline:**

```
std.Io.Dir.readFileAlloc(io, path)
        ↓
std.json.parseFromSlice(std.json.Value, gpa, bytes, …)
        ↓
for each trace_key → []StepRecord
        ↓
for each step: quizz.Parser.parseValue(gpa, json_value) → quizz.Values
        ↓
ReplaySession (flat step list, sorted trace keys)
```

Reuse `quizz.Parser.parseValue` — it already converts `std.json.Value` into the native
`Values` tagged union. Report snapshots are plain JSON scalars, arrays, and objects.

```zig
// apps/replay/report.zig (sketch)
pub fn loadReport(gpa: Allocator, io: std.Io, path: []const u8) !ReplaySession {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);

    const parsed = try std.json.parseFromSlice(
        std.json.Value, gpa, bytes, .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    // Walk parsed.value.object, build flat step list …
}
```

**String-encoded fallback:** If a future report embeds `spec_state` as a JSON string
(double-encoded), detect `.string` and parse a second time before `parseValue`.

**Memory:** `ReplaySession.deinit(gpa)` frees all retained data. Use an arena per file load;
dup only what the session keeps across reloads.

**Entry points:**

| Source | When |
|--------|------|
| CLI arg | `quizz-replay path/to/quizz_run.json` |
| Gooey file dialog | File → Open (Phase 2+) |
| Auto-discover | `./quizz_run.json` in cwd on launch (Phase 4) |
| Drag-and-drop | Optional Phase 4 (Gooey supports DnD) |

### ITF traces (Phase 5 — optional)

For raw `.itf.json` files (no driver pane):

```
quizz.Parser.parse(gpa, io, path)
        ↓
quizz.Parser.parseState(gpa, json_state)  per state
        ↓
ReplayStep with specState only, driverState = null
```

Reuse `runner.zig`'s `load_traces` / `parse_trace_file` — promote to `quizz.loadTraces`
per library roadmap Phase 0.

---

## Diff Computation

Quizz already computes **whether** states match at replay time via `eql.eqlValue` on typed
`Driver.State`. The UI needs **where** they differ.

| Layer | Input | Output | Used by |
|-------|-------|--------|---------|
| Replay (`eql.zig`) | Typed structs | `bool` | `runner.zig` → `matched` field |
| UI (`diff_cli.zig`) | two JSON files / bytes | Path-level diffs | Highlighting, inspector |

Do not drive UI diff off `eqlValue` alone — it returns no path information.

### Survey: [awesome-zig](https://github.com/zigcc/awesome-zig)

Checked the curated list for a consumable **JSON structural diff** library. Nothing relevant:

| Listed | Relevant? |
|--------|-----------|
| [zimdjson](https://github.com/ezequielramis/zimdjson), [nektro/zig-json](https://github.com/nektro/zig-json), [serde.zig](https://github.com/OrlovEvgeny/serde.zig) | Parse/serialize only |
| [prettizy](https://github.com/javiorfo/prettizy) | Pretty-print only |
| [odiff](https://github.com/dmtrKovalenko/odiff) | **Image** comparison, not JSON |
| [zig-doctest](https://github.com/kristoff-it/zig-doctest) | Doc testing |

Not listed but investigated separately:

| Project | Verdict |
|---------|---------|
| [fastjsondiff](https://github.com/adilkhash/fastjsondiff) | Zig core exists but ships as Python/C FFI only — **not** a Zig package |
| [diffz](https://github.com/ziglibs/diffz) | Text/line diff (diff-match-patch), not structural JSON |

**Conclusion:** No suitable Zig library to `@import`. Use an external CLI with machine-readable
stdout.

### CLI tool: [jd](https://github.com/josephburnett/jd) (default)

[jd](https://github.com/josephburnett/jd) is a single-binary JSON/YAML structural diff tool
(Go). Good fit for macOS:

```bash
brew install jd
jd -f=patch spec.json driver.json
```

**Why jd:**

- One static binary — no Node, no Python runtime for diffing
- Mature structural diff (LCS for arrays, minimal patches)
- **JSON Patch (RFC 6902) output** via `-f=patch` — easy to parse with `std.json` in Zig
- Well documented; common in JSON tooling workflows

Example stdout (`-f=patch`):

```json
[
  { "op": "replace", "path": "/role/n2", "value": "Follower" },
  { "op": "add", "path": "/votesReceived/n2/-", "value": "n3" },
  { "op": "remove", "path": "/foo" }
]
```

**Alternative:** [json-compare-cli](https://www.npmjs.com/package/json-compare-cli) (`json-diff
--json --no-color`) if jd is unavailable — requires Node.js but has a native diff JSON schema with
`path`, `type`, `from`, `to` fields. Configure via `DiffOptions.command`.

### Integration — subprocess + stdout parse

```
apps/replay/diff_cli.zig
        ↓  write temp files (or reuse step cache paths)
   jd -f=patch spec.tmp driver.tmp
        ↓  capture stdout
   std.json.parse → []JsonPatchOp
        ↓  normalize RFC 6901 paths → dot paths
   UiDiff { rows, changed_paths, changed_ancestors }
```

```zig
// apps/replay/diff_cli.zig
pub const DiffOptions = struct {
    /// argv prefix; default: &.{ "jd", "-f=patch" }
    command: []const []const u8 = &.{ "jd", "-f=patch" },
};

pub const UiDiff = struct {
    rows: []DiffRow,
    changed_paths: StringHashMap(void),
    changed_ancestors: StringHashMap(void),
};

pub fn compareJson(
    gpa: Allocator,
    io: std.Io,
    spec_json: []const u8,
    driver_json: []const u8,
    options: DiffOptions,
) !UiDiff;
```

**Steps inside `compareJson`:**

1. Write `spec_json` and `driver_json` to temp files under the system temp dir
2. Spawn CLI via `std.process` with captured stdout (include stderr on failure)
3. Parse stdout as JSON array of patch operations
4. Map each op:

   | jd / RFC 6902 | UI `DiffKind` | Notes |
   |---------------|---------------|-------|
   | `add` | `added` | `new_value` from `value` field |
   | `remove` | `removed` | `old_value` optional — fetch from spec_json if needed |
   | `replace` | `changed` | `value` is new; old from spec at path |

5. Normalize path: RFC 6901 `/role/n2` → dot notation `role.n2` (strip leading `/`, replace `/`
   with `.`, handle array indices)
6. Build `changed_paths` + `changed_ancestors` for pane highlighting
7. Cache `UiDiff` per step index

**Error handling:**

- CLI not on `PATH` → clear error: `"jd not found; install with: brew install jd"`
- Non-zero exit → include stderr in error message
- Invalid JSON stdout → `error.DiffParseFailed`

**Configuration:**

```zig
const opts = DiffOptions{}; // default jd

// fallback for json-diff
const opts = DiffOptions{
    .command = &.{ "json-diff", "--json", "--no-color" },
};
```

Document required tool in `apps/replay/README.md` and root README Step 4.

### Where JSON bytes come from

At report load time, retain each step's `spec_state` and `driver_state` as **JSON text**
alongside parsed `quizz.Values`:

```
parse step record
  ├── spec_json: []const u8     ← written to temp file for jd
  ├── driver_json: ?[]const u8
  ├── spec: quizz.Values        ← for format.zig display tree
  └── driver: ?quizz.Values
```

Re-serialize from parsed values with stable key ordering (`quizz_json`) so diff input is
consistent across runs.

### Precomputed `matched`

Trust `matched` from the report for sidebar icons. Still **run the diff CLI** so highlight
logic is tested independently. When `matched == true`, expect an empty patch array.

### Unit tests

- Mock stdout: feed a fixed RFC 6902 JSON array into the parser (no jd required in CI)
- Optional integration test gated on `jd` being present (`which jd`)
- Identical spec/driver → empty patch array
- Single `replace` op → one `changed` row + ancestor highlight
- Real `quizz_run.json` step with `matched: true` → empty diff (integration)

---

## Diff Viewing

Three complementary views from one `UiDiff` per selected step (via `diff_cli.zig`).

### 1. Side-by-side JSON panes (primary)

Two scrollable panes: **Spec State** (left), **Driver State** (right).

Walk `quizz.Values` recursively via `format.zig`, emit monospace lines each tagged with a
dot-path. Apply background tint per line:

| Condition | Background |
|-----------|------------|
| Path in `changed_paths` | Red tint |
| Path in `changed_ancestors` only | Orange tint |
| Otherwise | Default |

**Synchronized scroll:** Single `scroll_y` (and `scroll_x`) in `AppState`. When either Gooey
scroll container moves, update both from the same field.

**Gooey approach:** Start with two `Scroll` containers + manual line rendering with
path-aware background quads. Evaluate `run-code-editor` later for syntax highlighting.

### 2. Diff table (compact)

When diffs exist, show a virtualized table (Gooey `data-table` pattern):

```
Path              Spec           Driver
role.n2           Candidate      Follower
```

Clicking a row scrolls both panes to that path.

### 3. Match summary (always visible)

- `matched == true` → green "Matched"
- `matched == false` → red "Mismatch" + differing path count

### Re-render strategy

On step change only (not every frame):

1. Look up `ReplayStep`
2. `diff_cli.compareJson(spec_json, driver_json)` if driver present
3. `format.zig` → path-annotated line lists
4. Pass to Gooey render

---

## Input Format

### Primary: `quizz_run.json`

Top-level object keyed by trace id (`trace_0`, `trace_11`, …). Each value is an array of
step records:

```json
{
  "trace_11": [
    {
      "state_index": 10,
      "action": "grantVote",
      "matched": true,
      "spec_state": { ... },
      "driver_state": { ... }
    }
  ]
}
```

`spec_state` and `driver_state` are embedded JSON objects produced by `quizz_json.valueAlloc`
in `runner.zig`. See [Loading JSON](#loading-json) for the parse pipeline.

Trace keys are sorted by numeric suffix (`trace_(\d+)`).

### Future: ITF traces

Optional Phase 5 — see [Loading JSON](#loading-json). Not required for v1.

---

## Build Integration

Add to root `build.zig`:

```zig
const replay_mod = b.addModule("quizz-replay", .{
    .root_source_file = b.path("apps/replay/main.zig"),
    ...
});
replay_mod.addImport("quizz", quizz_mod);
replay_mod.addImport("gooey", gooey_mod);

const replay_exe = b.addExecutable(.{ .name = "quizz-replay", ... });

const replay_ui_step = b.step("replay-ui", "Launch replay viewer");
replay_ui_step.dependOn(&run_replay.step);
```

### Dependencies (`build.zig.zon`)

| Package | Purpose |
|---------|---------|
| [gooey](https://github.com/duanebester/gooey) | macOS/Metal UI |

**Runtime dependency (not in `build.zig.zon`):**

| Tool | Install | Purpose |
|------|---------|---------|
| [jd](https://github.com/josephburnett/jd) | `brew install jd` | JSON structural diff (default) |

---

## Implementation Phases

### Phase 1 — Headless core

**Goal:** Report loading and diff logic with tests. No window.

- [ ] `apps/replay/report.zig` — load `quizz_run.json` via `std.Io`, parse into `Values` + retain JSON bytes
- [ ] `apps/replay/diff_cli.zig` — spawn `jd -f=patch`, parse stdout → `UiDiff`
- [ ] `apps/replay/format.zig` — `Values` → path-annotated text lines for rendering
- [ ] Unit tests using repo `quizz_run.json` as fixture
- [ ] `build.zig` test step includes replay module tests

**Done when:** `zig build test` parses the Raft report and diff tests pass on known steps.

---

### Phase 2 — Minimal window

**Goal:** Open a macOS window and browse steps.

- [ ] Add Gooey dependency; spike `run-file-dialog` + virtual list patterns
- [ ] `main.zig` — Gooey app init, `Cx` + render loop
- [ ] Open file via CLI arg; Gooey native file dialog in Phase 4
- [ ] Sidebar: virtualized event list (`run-uniform-list` pattern)
- [ ] Center: single formatted JSON pane for current step
- [ ] ← / → via Gooey actions / keybindings

**Done when:** You can open a report and click through every step.

---

### Phase 3 — Full compare view

**Goal:** Feature parity with the old web prototype's core workflow.

- [ ] Dual spec / driver panes with synchronized scroll (shared `scroll_y` in `AppState`)
- [ ] Path-based diff highlighting (red = changed leaf, orange = ancestor)
- [ ] Diff table in inspector for compact mismatch view
- [ ] Transport bar: play, pause, scrubber, speed setting
- [ ] Inspector panel (action, trace, indices, match status, diff count)
- [ ] Status badge: Passed / Failed for the loaded report

**Done when:** A mismatch step clearly shows which paths diverge without reading raw JSON.

---

### Phase 4 — macOS polish

**Goal:** Feel like a real Mac app, not a dev harness.

- [ ] Auto-open `./quizz_run.json` from cwd on launch if present
- [ ] Gooey native file open dialog (already supported on macOS)
- [ ] App bundle: `Info.plist`, icon, `quizz-replay.app`
- [ ] Menu bar: File → Open, View → transport shortcuts
- [ ] Gooey light/dark theme follows system

**Done when:** Double-clicking the `.app` or running `zig build replay-ui` opens the viewer.

---

### Phase 5 — Optional extensions

- [ ] Load ITF traces via `quizz.Parser` (spec-only mode)
- [ ] Live reload when `quizz_run.json` is regenerated
- [ ] "Run test and open report" hook from `zig build run`

---

## Relationship to Quizz Roadmap

| Roadmap phase | Replay UI impact |
|---------------|------------------|
| Phase 3 (versioned report schema) | UI parser follows `schema_version`; update `report.zig` |
| Phase 3 (structured errors) | Inspector shows field-level mismatch when available |
| Phase 5 (invariants) | Inspector lists invariant failures per step |

The replay UI does **not** block library roadmap work. Phase 1 of this plan can start
in parallel with Quizz roadmap Phase 0.

---

## Deprecation

`prototype/replay-ui/` (HTML/JS/CSS) is **deprecated** once Phase 3 of this plan ships.
Do not invest in the web UI. Keep it until Zig viewer reaches parity, then delete.

Update [README.md](../README.md) to point here when Phase 2 lands.

---

## Success Criteria (v1 complete)

Phase 3 + Phase 4 done:

1. `zig build replay-ui` opens the viewer on macOS
2. Loading the Raft `quizz_run.json` shows all traces and steps
3. Mismatch steps highlight differing paths in spec vs driver panes
4. No browser required; `jd` must be on `PATH` for diff highlighting
5. All replay UI logic is Zig; `quizz` library is the single source of parsing truth

---

## Related Documents

- [ROADMAP.md](./ROADMAP.md) — library roadmap (report schema, errors)
- [README.md](../README.md) — Quizz usage and `quizz_run.json` output
- `prototype/replay-ui/app.js` — reference for diff *viewing* behavior to port (computation delegated to `jd` CLI)
