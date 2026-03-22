## Running the raft spec

1. Run quint to generate trace files: 
```
quint run examples/raft/spec/raft.qnt --main raft_test --mbt --out-itf raft_trace.itf.json
   --max-steps 15
```

2. Run zig code agains the trace:
```
zig build run -- raft_trace.itf.json
```

