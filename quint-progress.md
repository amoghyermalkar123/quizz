# Quint Raft Spec Progress

## Completed

- Quint basics: types, sets, maps, records, sum types
- State variables with `var`
- Actions with guards and state transitions
- `all {}` (conjunction) and `any {}` (disjunction)
- Non-determinism with `nondet` and `oneOf()`
- Invariants with `val`
- Simulation: `quint run`
- Model checking: `quint verify` (via Apalache)

## Spec Status

Leader election verified:
- `becomeCandidate` - follower starts election
- `grantVote` - node votes for candidate
- `becomeLeader` - candidate with majority becomes leader
- `stutter` - allows system to stay in stable state
- `electionSafety` invariant: at most one leader

Bugs found and fixed by model checker:
- Leaders must step down when higher term leader emerges
- Candidates can't become leader if higher term leader exists

## Next Steps

1. Log replication: `appendEntries` action
2. Log Matching invariant
3. Leader Completeness property
4. Node crash/restart modeling
5. Model-Based Testing: improving the quizz project, i.e. porting quint-connect (written in rust) to zig

## Verifying spec
quint verify examples/raft/spec/raft.qnt --main=raft_test --init=init --step=step
  --invariant=electionSafety --max-steps=20
