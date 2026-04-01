# Quizz

Quizz is a framework for model-based testing in Zig using Quint.

It helps you take a Quint specification, generate traces from that spec, replay those traces against a Zig implementation, and check whether the implementation behaves the way the model says it should.

## The Problem Quizz Solves

When we build distributed systems, protocols, or stateful workflows, we often have two things:

- a formal or semi-formal spec that describes the correct behavior
- an implementation that is supposed to follow that behavior

The hard part is closing the gap between them.

Quizz solves that by turning a Quint spec into executable test traces and replaying those traces against a Zig driver. Instead of manually comparing expected behavior to implementation behavior, Quizz does the replay and state comparison step for you.

In practice, this means you can use Quint to describe system behavior and Zig to implement the real logic, while Quizz acts as the testing bridge between the two.

## Basic Working

At a high level, Quizz works like this:

1. Quint generates one or more ITF traces from your spec.
2. Quizz parses those traces into Zig data structures.
3. Quizz replays each action in the trace against a Zig driver.
4. After every action, Quizz compares the spec state to the driver state.
5. Quizz writes the results to `quizz_run.json` so you can inspect what matched and what did not.

The Zig side provides the driver logic.

The Quint side provides the expected behavior.

Quizz connects the two.

## Installation

### Requirements

- Zig `0.15.2` or newer
- [Quint](https://quint-lang.org/) installed and available on your `PATH`

Quizz invokes `quint run` internally, so Quint is required for generating traces from specs.

### Build

```bash
zig build
```

### Run tests

```bash
zig build test
```

### Run the example

```bash
zig build run -- examples/raft/spec/raft.qnt
```

That command builds the bundled Raft example, runs the Quint spec, replays the generated traces against the Zig driver, and writes a report to `quizz_run.json`.

## Raft Example Walkthrough

The Raft example is the best place to start if you want to understand how Quizz is meant to be used.

Relevant files:

- [`examples/raft/spec/raft.qnt`](./examples/raft/spec/raft.qnt): the Quint model
- [`examples/raft/raftdriver.zig`](./examples/raft/raftdriver.zig): the Zig driver used for replay
- [`examples/raft/raft.zig`](./examples/raft/raft.zig): the example Raft state machine implementation

### Step 1: Run the example

```bash
zig build run -- examples/raft/spec/raft.qnt
```

This asks Quint to generate traces from the Raft spec and then replays them through the Zig driver.

### Step 2: Look at the driver

In [`examples/raft/raftdriver.zig`](./examples/raft/raftdriver.zig), the driver does three key things:

- declares the state shape that should be compared against the spec
- implements a `step` function that handles spec actions like `init`, `becomeCandidate`, and `grantVote`
- implements `from_driver` so the live Zig state can be projected into a comparable snapshot

This is the core pattern for using Quizz with your own system.

### Step 3: Inspect the output

After replay, Quizz writes `quizz_run.json` in the project root.

That file contains per-trace replay results with:

- the action that was taken
- whether the step matched
- the spec state
- the driver state

If a mismatch happens, `quizz_run.json` is the first place to inspect.

### Step 4: Open the replay UI

This repo also includes a lightweight UI for inspecting replay output:

- [`prototype/replay-ui/index.html`](./prototype/replay-ui/index.html)

It is useful for stepping through traces and comparing spec state and driver state side by side.

## Project Shape

- [`src/root.zig`](./src/root.zig): public library entry point and ITF parsing
- [`src/driver.zig`](./src/driver.zig): replay step extraction and action dispatch
- [`src/runner.zig`](./src/runner.zig): trace generation, replay, and report writing
- [`src/state.zig`](./src/state.zig): spec-state conversion helpers
- [`src/json.zig`](./src/json.zig): JSON serialization for replay output

## Known Issues

- Parsed traces currently drop ITF metadata on conversion into Quizz's native types. Top-level trace metadata, declared variables, and richer per-state `#meta` fields are not preserved in the returned [`Trace`](./src/root.zig) and [`State`](./src/root.zig) values, so callers cannot inspect that information after parsing.

## In One Sentence

Quizz lets you use Quint as the model, Zig as the implementation language, and replay-based comparison as the testing loop between them.
