## Running the raft spec

1. Run the raft example against the Quint spec:
```
zig build run -- examples/raft/spec/raft.qnt
```

## Replay UI prototype

An interactive browser prototype for replay visualization lives in
`prototype/replay-ui/`.

- Open `prototype/replay-ui/index.html` in a browser to load `quizz_run.json`
  by default.
- Load either a replay report like `quizz_run.json` or a raw `.itf.json` trace.
- The prototype is tuned for invariant debugging: playback controls, selected
  action context, spec-vs-driver state comparison, and JSON-path diffs for the
  selected step.
