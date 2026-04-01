# Deterministic Simulation Testing (DST) Research Document
## Integration Strategy for the Quizz Framework

**Version:** 1.0
**Date:** March 2026
**Author:** Research Compilation

---

## Table of Contents

1. [How Deterministic Simulation Testing Works](#1-how-deterministic-simulation-testing-works)
2. [Industry Implementations](#2-industry-implementations)
3. [Techniques and Patterns](#3-techniques-and-patterns)
4. [Developer Experience (DX) Considerations](#4-developer-experience-dx-considerations)
5. [Integration with Quizz Framework](#5-integration-with-quizz-framework)
6. [Best Practices](#6-best-practices)
7. [Sources](#7-sources)

---

## 1. How Deterministic Simulation Testing Works

### 1.1 Core Concept

Deterministic Simulation Testing (DST) is a testing methodology that enables **perfect reproducibility** of complex system behaviors, including race conditions, network failures, and timing-dependent bugs. Unlike traditional testing or chaos engineering, DST guarantees that any bug found can be reproduced exactly, making debugging tractable.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DETERMINISTIC SIMULATION TESTING                          │
│                                                                              │
│   Traditional Testing              DST                                       │
│   ==================              ===                                        │
│                                                                              │
│   Real Time ────────>          Virtual Time (Controlled)                     │
│   Real Network ─────>          Simulated Network                             │
│   Real Disk I/O ────>          In-Memory Storage                             │
│   OS Scheduler ─────>          Deterministic Scheduler                       │
│   Hardware RNG ─────>          Seeded PRNG                                   │
│                                                                              │
│   Result: Non-reproducible      Result: Perfect Reproducibility              │
│           "Heisenbug"                   Same Seed = Same Execution           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 The Five Pillars of DST

```
                         ┌─────────────────────┐
                         │   DETERMINISTIC     │
                         │   SIMULATION        │
                         │   TESTING           │
                         └──────────┬──────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │              │           │           │              │
         v              v           v           v              v
    ┌─────────┐   ┌─────────┐ ┌─────────┐ ┌─────────┐   ┌─────────┐
    │  Time   │   │  I/O    │ │ Random  │ │ Fault   │   │Invariant│
    │ Control │   │Abstract │ │ Control │ │Injection│   │Checking │
    └─────────┘   └─────────┘ └─────────┘ └─────────┘   └─────────┘
         │              │           │           │              │
         v              v           v           v              v
    Virtual       Network &    Seeded      Network,      Property
    Clock         Storage      PRNG        Disk,         Assertions
    Advancement   Simulation              Crash, Time    & Oracles
```

#### Pillar 1: Time Control

All time-dependent operations use a **virtual clock** controlled by the simulator:

```
Normal Execution:                    DST Execution:
─────────────────                    ──────────────
sleep(1000ms)                        sim.advance_time(1000ms)
   │                                    │
   └── Blocks for 1 real second         └── Instant, deterministic
                                            Time only advances when
                                            simulator decides
```

**Key Mechanism:**
- No wall-clock dependencies
- Time only advances when all actors are blocked
- Can simulate years of operation in seconds

#### Pillar 2: I/O Abstraction

All external I/O goes through an abstraction layer:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Application Code                             │
│                          │                                       │
│                          v                                       │
│                  ┌───────────────┐                              │
│                  │  I/O Interface │  (Abstract)                  │
│                  │  - read()      │                              │
│                  │  - write()     │                              │
│                  │  - send()      │                              │
│                  │  - recv()      │                              │
│                  └───────┬───────┘                              │
│                          │                                       │
│            ┌─────────────┼─────────────┐                        │
│            │             │             │                        │
│            v             v             v                        │
│      ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│      │ Real I/O │  │  Sim I/O │  │ Replay   │                  │
│      │ (Prod)   │  │  (Test)  │  │ (Debug)  │                  │
│      └──────────┘  └──────────┘  └──────────┘                  │
│                                                                  │
│   Selection: compile-time (comptime) or runtime (trait object)  │
└─────────────────────────────────────────────────────────────────┘
```

#### Pillar 3: Random Control

All randomness flows from a single, seeded PRNG:

```
Seed: 0xDEADBEEF
       │
       v
┌──────────────────┐
│  Master PRNG     │
│  (Xoshiro256)    │
└────────┬─────────┘
         │
    ┌────┴────┬────────────┬────────────┐
    v         v            v            v
Network   Fault        Workload     Timing
Delays    Injection    Generator    Jitter

Same seed = Identical sequence of "random" events
```

#### Pillar 4: Fault Injection

Controlled injection of failures during simulation:

```
Fault Injection Decision Flow:
==============================

For each I/O operation:
    │
    v
┌─────────────────────┐
│ Query Fault Oracle  │
│ (PRNG-based)        │
└──────────┬──────────┘
           │
    ┌──────┴──────┐
    v             v
 ┌──────┐    ┌──────┐
 │ PASS │    │ FAIL │
 └──────┘    └──┬───┘
                │
    ┌───────────┼───────────┬───────────┐
    v           v           v           v
 Drop       Corrupt      Delay       Timeout
 Packet     Data         500ms       Connection
```

**Fault Types:**

| Category | Specific Faults |
|----------|-----------------|
| **Network** | Packet loss, reordering, duplication, partition, asymmetric partition, latency spike |
| **Storage** | Read error, write error, corruption, partial write, disk full, fsync failure |
| **Process** | Crash, hang, slow response, OOM |
| **Time** | Clock skew, backward jump, drift |
| **Byzantine** | Conflicting responses, protocol violations |

#### Pillar 5: Invariant Checking

Continuous verification during simulation:

```
After each simulation step:
    │
    v
┌─────────────────────────────────────┐
│         Invariant Checker           │
├─────────────────────────────────────┤
│  - Data consistency                 │
│  - Linearizability                  │
│  - No data loss                     │
│  - State machine validity           │
│  - Protocol compliance              │
│  - Resource bounds                  │
└──────────────────┬──────────────────┘
                   │
         ┌─────────┴─────────┐
         v                   v
    ┌─────────┐         ┌─────────┐
    │  PASS   │         │  FAIL   │
    │Continue │         │ Report  │
    │Simulation│        │ + Seed  │
    └─────────┘         └─────────┘
```

### 1.3 Execution Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SIMULATION EXECUTION LOOP                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    ┌───────────────────────────────────────────────────────────────────┐    │
│    │                        Event Queue                                 │    │
│    │  [(t=100, msg_recv), (t=105, timeout), (t=110, disk_write)]       │    │
│    └───────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    v                                         │
│                        1. Pick earliest event                                │
│                                    │                                         │
│                                    v                                         │
│                        2. Advance virtual time                               │
│                           sim.time = 100                                     │
│                                    │                                         │
│                                    v                                         │
│                        3. Deliver to actor                                   │
│                           actor.on_message(msg)                              │
│                                    │                                         │
│                                    v                                         │
│                        4. Actor may schedule new events                      │
│                           sim.schedule(t=120, reply)                         │
│                                    │                                         │
│                                    v                                         │
│                        5. Check invariants                                   │
│                           check_consistency()                                │
│                                    │                                         │
│                                    v                                         │
│                        6. Log to trace (optional)                            │
│                           trace.append(event)                                │
│                                    │                                         │
│                                    v                                         │
│                        7. Repeat until done                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Reproducibility Guarantee

```
                    ┌─────────────────────────────┐
                    │       Seed: 0x12345678      │
                    │       Commit: abc123        │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    v                             v
            ┌──────────────┐              ┌──────────────┐
            │   Run #1     │              │   Run #2     │
            │              │              │              │
            │ Events:      │              │ Events:      │
            │ e1,e2,e3...  │   IDENTICAL  │ e1,e2,e3...  │
            │              │  =========== │              │
            │ Bug at t=500 │              │ Bug at t=500 │
            └──────────────┘              └──────────────┘
                    │                             │
                    └──────────────┬──────────────┘
                                   │
                                   v
                    ┌─────────────────────────────┐
                    │    SAME BUG, EVERY TIME     │
                    │    Debug with confidence    │
                    └─────────────────────────────┘
```

---

## 2. Industry Implementations

### 2.1 FoundationDB (The Pioneer)

FoundationDB pioneered DST in the database industry. Their approach:

**Architecture:**
- Custom actor framework called **Flow**
- All I/O through Flow primitives
- Single-threaded execution with simulated concurrency
- Comprehensive fault injection

**Key Innovation:** They built the testing infrastructure **before** the database, ensuring every line of code was testable from day one.

**Results:**
- Found bugs that would occur once per million machine-years
- Every major release blocker found in simulation, not production
- Runs trillions of test operations

**Source:** [FoundationDB Testing Documentation](https://apple.github.io/foundationdb/testing.html)

### 2.2 TigerBeetle (The VOPR)

TigerBeetle's VOPR (Viewstamped Operation Replicator) is currently the largest DST cluster in operation.

**Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        VOPR ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    ┌──────────────────────────────────────────────────────┐     │
│    │                  Seed + Git Commit                    │     │
│    │                         │                             │     │
│    │                         v                             │     │
│    │              ┌──────────────────┐                    │     │
│    │              │  Master PRNG     │                    │     │
│    │              └────────┬─────────┘                    │     │
│    │                       │                               │     │
│    │    ┌──────────────────┼──────────────────┐           │     │
│    │    v                  v                  v           │     │
│    │ ┌──────────┐   ┌──────────┐   ┌──────────┐          │     │
│    │ │ Network  │   │ Storage  │   │  Timing  │          │     │
│    │ │ Simulator│   │ Simulator│   │  Control │          │     │
│    │ └────┬─────┘   └────┬─────┘   └────┬─────┘          │     │
│    │      │              │              │                 │     │
│    │      └──────────────┼──────────────┘                 │     │
│    │                     v                                 │     │
│    │         ┌───────────────────────┐                    │     │
│    │         │   TigerBeetle Cluster │                    │     │
│    │         │   (Multiple Replicas) │                    │     │
│    │         │   Running in-process  │                    │     │
│    │         └───────────────────────┘                    │     │
│    │                     │                                 │     │
│    │                     v                                 │     │
│    │         ┌───────────────────────┐                    │     │
│    │         │   Invariant Checkers  │                    │     │
│    │         │   - Byte-identical    │                    │     │
│    │         │     replicas          │                    │     │
│    │         │   - Linearizability   │                    │     │
│    │         │   - 6,000+ assertions │                    │     │
│    │         └───────────────────────┘                    │     │
│    └──────────────────────────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Scale:**
- 1,000 CPU cores running 24/7
- 700x time acceleration
- ~2 millennia of simulated runtime per day
- 3.3 seconds of simulation = 39 minutes real-world testing

**Zig-Specific Patterns:**
- Comptime for zero-cost I/O abstraction
- No dynamic memory allocation (deterministic by design)
- Explicit error handling (no hidden control flow)

**Source:** [TigerBeetle VOPR Documentation](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md)

### 2.3 Antithesis (The Platform)

Antithesis is a commercial DST platform founded by former FoundationDB engineers. They raised $105M in December 2025.

**Key Innovation: The Determinator**

```
┌─────────────────────────────────────────────────────────────────┐
│                    ANTITHESIS DETERMINATOR                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                Your Software Stack                       │   │
│   │        (Unmodified Docker containers)                    │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              v                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │            Deterministic Hypervisor                      │   │
│   │                                                          │   │
│   │   Intercepts and controls:                               │   │
│   │   - All system calls                                     │   │
│   │   - Thread scheduling                                    │   │
│   │   - Time sources                                         │   │
│   │   - Random number generation                             │   │
│   │   - Network I/O                                          │   │
│   │   - Disk I/O                                             │   │
│   │                                                          │   │
│   │   Result: Fully deterministic execution                  │   │
│   │           WITHOUT modifying your code                    │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              v                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              Intelligent Fuzzer                          │   │
│   │   - Coverage-guided exploration                          │   │
│   │   - Fault injection scheduling                           │   │
│   │   - "Sometimes" assertions                               │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**"Sometimes" Assertions:**

Traditional assertions: `assert(x == y)` - must always be true
Sometimes assertions: `sometimes(leader_elected)` - must be true at least once

This enables testing of liveness properties and probabilistic behaviors.

**Notable Users:**
- Jane Street
- Ethereum (used for The Merge)
- MongoDB
- CockroachDB
- Confluent
- Palantir

**Source:** [Antithesis Documentation](https://antithesis.com/docs/resources/deterministic_simulation_testing/)

### 2.4 Jepsen (Black-Box Testing)

Jepsen is a complementary approach that tests **real systems** rather than simulations.

**Comparison:**

| Aspect | DST | Jepsen |
|--------|-----|--------|
| Environment | Simulated | Real |
| Reproducibility | Perfect | Limited |
| Speed | Fast (ms per test) | Slow (hours) |
| Fault types | All (simulated) | Network + process |
| Code changes | Required | None |
| Bug types found | Logic, concurrency | Integration, configuration |

**When to use each:**
- DST: Pre-production, deep logic verification
- Jepsen: Post-production, integration validation

**Source:** [Jepsen.io](https://jepsen.io)

---

## 3. Techniques and Patterns

### 3.1 I/O Abstraction Pattern (Zig)

```zig
/// Compile-time I/O backend selection
pub fn IO(comptime mode: IOMode) type {
    return struct {
        const Backend = switch (mode) {
            .real => RealIO,
            .simulation => SimulatedIO,
        };

        backend: Backend,

        pub fn read(self: *@This(), fd: i32, buf: []u8) !usize {
            return self.backend.read(fd, buf);
        }

        pub fn write(self: *@This(), fd: i32, data: []const u8) !usize {
            return self.backend.write(fd, data);
        }

        pub fn now(self: *@This()) u64 {
            return self.backend.now();
        }
    };
}

// Real implementation uses OS syscalls
const RealIO = struct {
    pub fn read(fd: i32, buf: []u8) !usize {
        return std.os.read(fd, buf);
    }

    pub fn now() u64 {
        return @intCast(std.time.nanoTimestamp());
    }
};

// Simulated implementation uses in-memory state
const SimulatedIO = struct {
    prng: std.rand.Xoshiro256,
    virtual_time: u64,
    fault_config: FaultConfig,

    pub fn read(self: *@This(), fd: i32, buf: []u8) !usize {
        // Fault injection
        if (self.shouldFail(.disk_read)) {
            return error.InputOutput;
        }

        // Simulated latency
        self.virtual_time += self.randomLatency();

        // Return from virtual storage
        return self.storage.read(fd, buf);
    }

    pub fn now(self: *@This()) u64 {
        return self.virtual_time;
    }
};
```

### 3.2 Event-Driven Simulation Loop

```zig
const Simulator = struct {
    const Event = struct {
        time: u64,
        target: ActorId,
        payload: EventPayload,
    };

    time: u64,
    prng: std.rand.Xoshiro256,
    event_queue: std.PriorityQueue(Event, void, eventComparator),
    actors: std.AutoHashMap(ActorId, *Actor),

    pub fn run(self: *Simulator, max_steps: usize) !void {
        var steps: usize = 0;

        while (steps < max_steps) : (steps += 1) {
            // 1. Get next event
            const event = self.event_queue.removeOrNull() orelse break;

            // 2. Advance time (never goes backward)
            std.debug.assert(event.time >= self.time);
            self.time = event.time;

            // 3. Deliver to actor
            const actor = self.actors.get(event.target) orelse continue;
            try actor.handle(event.payload);

            // 4. Check invariants
            try self.checkInvariants();
        }
    }

    pub fn schedule(self: *Simulator, delay: u64, target: ActorId, payload: EventPayload) !void {
        try self.event_queue.add(.{
            .time = self.time + delay,
            .target = target,
            .payload = payload,
        });
    }

    fn checkInvariants(self: *Simulator) !void {
        // Example: Check all replicas agree on committed state
        var it = self.actors.iterator();
        var reference: ?State = null;

        while (it.next()) |entry| {
            const state = entry.value_ptr.*.getCommittedState();
            if (reference) |ref| {
                if (!std.meta.eql(ref, state)) {
                    return error.InvariantViolation;
                }
            } else {
                reference = state;
            }
        }
    }
};
```

### 3.3 Fault Injection Framework

```zig
const FaultInjector = struct {
    prng: *std.rand.Xoshiro256,
    config: FaultConfig,

    const FaultConfig = struct {
        network_drop_rate: f64 = 0.01,     // 1% packet loss
        disk_error_rate: f64 = 0.001,       // 0.1% disk errors
        crash_probability: f64 = 0.0001,    // 0.01% crash per op
        latency_spike_rate: f64 = 0.05,     // 5% high latency
        partition_probability: f64 = 0.001, // 0.1% partition
    };

    pub fn shouldDropPacket(self: *@This()) bool {
        return self.prng.random().float(f64) < self.config.network_drop_rate;
    }

    pub fn shouldCorruptDisk(self: *@This()) bool {
        return self.prng.random().float(f64) < self.config.disk_error_rate;
    }

    pub fn getNetworkDelay(self: *@This()) u64 {
        const base_delay: u64 = 1; // 1ms base

        if (self.prng.random().float(f64) < self.config.latency_spike_rate) {
            // Tail latency: 100-1000ms
            return base_delay + self.prng.random().intRangeAtMost(u64, 100, 1000);
        }

        return base_delay + self.prng.random().intRangeAtMost(u64, 0, 10);
    }

    pub fn shouldPartition(self: *@This()) ?Partition {
        if (self.prng.random().float(f64) < self.config.partition_probability) {
            return Partition.random(self.prng);
        }
        return null;
    }
};
```

### 3.4 Network Simulator

```
┌─────────────────────────────────────────────────────────────────┐
│                    NETWORK SIMULATOR                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Message Flow:                                                  │
│                                                                  │
│   Node A                                         Node B          │
│      │                                              │            │
│      │─────── send(msg) ──────>│                   │            │
│      │                         │                   │            │
│      │                    ┌────v────┐              │            │
│      │                    │ Network │              │            │
│      │                    │ Sim     │              │            │
│      │                    └────┬────┘              │            │
│      │                         │                   │            │
│      │              ┌──────────┴──────────┐        │            │
│      │              │                     │        │            │
│      │              v                     v        │            │
│      │         ┌─────────┐          ┌─────────┐   │            │
│      │         │  DROP?  │          │ DELAY?  │   │            │
│      │         │ (PRNG)  │          │ (PRNG)  │   │            │
│      │         └────┬────┘          └────┬────┘   │            │
│      │              │                    │        │            │
│      │         Yes: discard        Schedule:      │            │
│      │         No:  continue       t+delay ───────>│            │
│      │                                   │        │            │
│      │                                   │<───────│            │
│      │                              recv(msg)     │            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

```zig
const NetworkSimulator = struct {
    prng: *std.rand.Xoshiro256,
    fault_injector: *FaultInjector,
    pending_messages: std.ArrayList(PendingMessage),
    partitions: std.AutoHashMap(NodePair, void),

    const PendingMessage = struct {
        deliver_at: u64,
        from: NodeId,
        to: NodeId,
        payload: []const u8,
    };

    pub fn send(
        self: *@This(),
        sim: *Simulator,
        from: NodeId,
        to: NodeId,
        payload: []const u8,
    ) !void {
        // Check partition
        if (self.isPartitioned(from, to)) {
            return; // Message silently dropped
        }

        // Check drop
        if (self.fault_injector.shouldDropPacket()) {
            return; // Message dropped
        }

        // Calculate delivery time
        const delay = self.fault_injector.getNetworkDelay();

        try self.pending_messages.append(.{
            .deliver_at = sim.time + delay,
            .from = from,
            .to = to,
            .payload = try self.allocator.dupe(u8, payload),
        });
    }

    pub fn partition(self: *@This(), group_a: []const NodeId, group_b: []const NodeId) void {
        for (group_a) |a| {
            for (group_b) |b| {
                self.partitions.put(.{ a, b }, {}) catch {};
                self.partitions.put(.{ b, a }, {}) catch {};
            }
        }
    }

    pub fn healPartition(self: *@This()) void {
        self.partitions.clearRetainingCapacity();
    }
};
```

---

## 4. Developer Experience (DX) Considerations

### 4.1 Incremental Adoption Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                 DST ADOPTION ROADMAP                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Phase 1: Time Injection (Low effort, Medium impact)            │
│  ═══════════════════════════════════════════════════            │
│  - Replace std.time with Clock trait                            │
│  - Tests run 1000x faster (no sleep())                          │
│  - Timeout logic becomes testable                               │
│                                                                  │
│  Phase 2: RNG Control (Low effort, High impact)                 │
│  ═══════════════════════════════════════════════════            │
│  - Seed all randomness from single PRNG                         │
│  - Log seed on failure                                          │
│  - Every test failure becomes reproducible                      │
│                                                                  │
│  Phase 3: Trace Logging (Low effort, High impact)               │
│  ═══════════════════════════════════════════════════            │
│  - Log all significant events with timestamps                   │
│  - Enable post-mortem debugging                                 │
│  - Build trace replay infrastructure                            │
│                                                                  │
│  Phase 4: Network Simulation (High effort, High impact)         │
│  ═══════════════════════════════════════════════════            │
│  - Abstract network behind Transport trait                      │
│  - Build in-memory network simulator                            │
│  - Add partition/delay/reorder controls                         │
│                                                                  │
│  Phase 5: Storage Simulation (High effort, Very High impact)    │
│  ═══════════════════════════════════════════════════            │
│  - Abstract storage behind Storage trait                        │
│  - Build crash-simulating backend                               │
│  - Add corruption/fsync failure modes                           │
│                                                                  │
│  Phase 6: Full DST (Very High effort, Maximum impact)           │
│  ═══════════════════════════════════════════════════            │
│  - All I/O through simulation layer                             │
│  - Adversarial scheduler                                        │
│  - Comprehensive fault injection                                │
│  - CI/CD integration                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Debugging Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    DST DEBUGGING WORKFLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. BUG DISCOVERY                                                │
│     ┌─────────────────────────────────────────────┐             │
│     │  $ zig build test-sim                       │             │
│     │  FAILED: Invariant violation                │             │
│     │  Seed: 0xDEADBEEF                          │             │
│     │  Trace: /tmp/trace-0xDEADBEEF.jsonl        │             │
│     └─────────────────────────────────────────────┘             │
│                         │                                        │
│                         v                                        │
│  2. REPRODUCTION                                                 │
│     ┌─────────────────────────────────────────────┐             │
│     │  $ zig build test-sim -- --seed 0xDEADBEEF │             │
│     │  (Exact same failure, every time)           │             │
│     └─────────────────────────────────────────────┘             │
│                         │                                        │
│                         v                                        │
│  3. TRACE ANALYSIS                                               │
│     ┌─────────────────────────────────────────────┐             │
│     │  $ trace-viewer /tmp/trace-0xDEADBEEF.jsonl │             │
│     │                                              │             │
│     │  t=1000: Node A writes X=5                  │             │
│     │  t=1005: Network partition (A | B,C)        │             │
│     │  t=1010: Node B writes X=10  <-- BUG       │             │
│     │  t=1015: Client reads X=10                  │             │
│     │  t=1020: Partition heals                    │             │
│     │  t=1025: INVARIANT VIOLATION                │             │
│     └─────────────────────────────────────────────┘             │
│                         │                                        │
│                         v                                        │
│  4. ROOT CAUSE IDENTIFIED                                        │
│     Bug: Leader election didn't wait for quorum                  │
│                         │                                        │
│                         v                                        │
│  5. FIX & REGRESSION TEST                                        │
│     - Apply fix                                                  │
│     - Add seed to regression suite                               │
│     - CI runs this seed on every commit forever                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 CI/CD Integration

```yaml
# .github/workflows/simulation.yml
name: Deterministic Simulation Testing
on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 2 * * *'  # Nightly

jobs:
  # Fast check on every PR
  simulation-quick:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      matrix:
        seed: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]  # 10 seeds in parallel
    steps:
      - uses: actions/checkout@v4
      - run: zig build test-sim -- --seed ${{ matrix.seed }} --duration 60

  # Extended check on main
  simulation-extended:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 120
    strategy:
      matrix:
        seed: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
    steps:
      - uses: actions/checkout@v4
      - run: zig build test-sim -- --seed ${{ matrix.seed }} --duration 300

  # Regression tests (known-bug seeds)
  regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          for seed in $(cat tests/seeds/regressions.txt); do
            zig build test-sim -- --seed $seed
          done
```

### 4.4 Common Pitfalls

| Pitfall | Cause | Solution |
|---------|-------|----------|
| **Hidden Non-Determinism** | HashMap iteration order | Sort keys before iterating |
| **TOCTOU Bug** | Time advances between check and use | Capture time atomically |
| **Insufficient Coverage** | Testing only happy path | Use adversarial fault injection |
| **Simulation/Production Gap** | Different code paths | Same binary with feature flags |
| **Slow Simulation** | Hot paths not optimized | Profile and parallelize |
| **Poor Failure Messages** | Missing context | Include seed, trace, expected vs got |

---

## 5. Integration with Quizz Framework

### 5.1 Current Quizz Architecture

Quizz currently bridges Quint formal specifications with Zig implementations:

```
┌──────────────────┐
│ Quint Spec (.qnt)│
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  quint run       │
│  (trace gen)     │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  ITF Traces      │
│  (JSON)          │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  Quizz Parser    │
│  (root.zig)      │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  Driver Replay   │
│  (runner.zig)    │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  State Compare   │
│  (spec vs impl)  │
└──────────────────┘
```

Today, this is best understood as **replay-oriented MBT**:
- Quint is the model and oracle source
- `quint run --mbt` generates concrete executions
- Quizz replays those executions against a Zig driver
- Quizz compares spec state and driver state after each step

### 5.2 How DST and MBT Relate

The original version of this document implied that DST would naturally replace MBT. In Quizz, that is not quite right.

**Model-Based Testing (MBT)** and **Deterministic Simulation Testing (DST)** operate at different layers:

| Concern | MBT in Quizz Today | DST | Combined MBT + DST |
|---------|--------------------|-----|--------------------|
| Main question answered | "What behavior is valid according to the spec?" | "Under which schedules, timings, and failures does the system break?" | "Does the implementation remain spec-correct under adversarial but reproducible executions?" |
| Source of behavior | Quint spec + generated ITF traces | Seeded simulator + controlled environment | Quint spec defines legal actions/oracles, simulator explores when/how they happen |
| Oracle | Expected post-state from trace | Invariants, assertions, liveness/safety checks | Spec state comparison plus simulation invariants |
| Exploration style | Replay of pre-generated traces | Seed-driven dynamic exploration | Seed-driven exploration constrained or checked by the model |
| Failure reproduction | Re-run same trace | Re-run same seed | Re-run same seed and/or export failing trace |

The practical relationship is:

- MBT tells Quizz **what** should happen and what correctness means.
- DST tells Quizz **how** to execute those behaviors under controlled time, randomness, scheduling, and faults.

Put differently: **DST without an oracle is deterministic fuzzing, not model-based testing**. For Quizz, the strongest story is not "replace MBT with DST", but **extend MBT from finite trace replay into deterministic, seed-driven exploration**.

That makes the current Quizz workflow a strong foundation:
- Replay MBT remains the simplest and most direct way to validate spec conformance
- DST becomes the execution engine used to widen coverage beyond fixed traces
- Failing DST runs should ideally produce artifacts that are as debuggable as today's replay traces

### 5.3 Can DST Be Integrated with Quizz?

**Yes, but only if DST is integrated as an additional execution mode, not as a drop-in replacement for the current replay loop.**

There are really two integration levels:

**Level 1: Quizz-native deterministic simulation**
- Reuse the current driver pattern: action dispatch, `from_driver()`, and comparable `State`
- Add seeded execution, virtual time, fault injection, and deterministic trace logging
- Express invariants in Zig over the driver's projected state
- This is practical with the current codebase

**Level 2: Full Quint-guided DST**
- Use Quint not only to emit offline traces, but also to define enabled actions, preconditions, and invariants during simulation
- This would let the simulator explore new executions while staying model-aware
- This is much higher effort because Quizz currently consumes Quint output offline; it does not evaluate Quint models online

So the answer is:
- **DST can integrate with Quizz today** as a deterministic execution engine plus invariant runner
- **Full MBT + DST integration is possible**, but it requires a new model adapter or code generation layer rather than just a new simulator module

The current codebase already provides several reusable pieces:
- The driver contract centers on advancing the implementation and projecting state back into a comparable form
- State conversion and structural equality already exist for cross-checking spec and implementation state
- Replay reports and the replay UI are still valuable for debugging DST failures

The main thing that does **not** fit unchanged is the current replay step representation. Today Quizz's replay step bundles:
- the action name
- nondeterministic picks
- the expected post-state from the ITF trace

That is perfect for replay MBT, but DST-generated executions usually have the first two items and **do not** have a precomputed post-state. A clean integration therefore needs to separate:
- **Action execution**: what the driver should do next
- **Oracle checking**: how correctness is evaluated after the action

### 5.4 Proposed DST Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                    QUIZZ + DST ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      Mode Selection                       │   │
│  │         (comptime: replay | simulation | production)      │   │
│  └────────────────────────────┬─────────────────────────────┘   │
│                               │                                  │
│          ┌────────────────────┼────────────────────┐            │
│          v                    v                    v            │
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐   │
│  │  Replay Mode  │    │   DST Mode    │    │   Prod Mode   │   │
│  │ (Current)     │    │   (NEW)       │    │   (Future)    │   │
│  └───────┬───────┘    └───────┬───────┘    └───────────────┘   │
│          │                    │                                  │
│          v                    v                                  │
│  ┌───────────────┐    ┌───────────────────────────────────┐    │
│  │ ITF Traces    │    │      Deterministic Simulator      │    │
│  │ from Quint    │    │                                   │    │
│  │ Fixed action  │    │  - Seeded PRNG                    │    │
│  │ sequences     │    │  - Virtual Time                   │    │
│  └───────┬───────┘    │  - Fault / Schedule Control       │    │
│          │            │  - Event Trace Logging            │    │
│          │            └────────────────┬──────────────────┘    │
│          │                             │                        │
│          v                             v                        │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  Execution Source                         │ │
│  │  ReplaySource (ITF)  or  SimSource (seeded events)       │ │
│  └────────────────────────────┬──────────────────────────────┘ │
│                               │                                │
│                               v                                │
│                    ┌──────────────────────┐                    │
│                    │   Driver Interface   │                    │
│                    │                      │                    │
│                    │  - apply(Action)     │                    │
│                    │  - from_driver()     │                    │
│                    │  - State type        │                    │
│                    └──────────┬───────────┘                    │
│                               │                                │
│                               v                                │
│                    ┌──────────────────────┐                    │
│                    │    Oracle Layer      │                    │
│                    │                      │                    │
│                    │  - Replay compare    │                    │
│                    │  - Zig invariants    │                    │
│                    │  - Future Quint      │                    │
│                    │    model adapter     │                    │
│                    └──────────────────────┘                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

The key architectural idea is to preserve Quizz's existing strengths while changing where execution comes from:

- **Replay mode** gets its next action and expected state from ITF
- **DST mode** gets its next action and environment decisions from a seeded simulator
- Both modes should flow through the same driver projection, reporting, and oracle machinery where possible

### 5.5 Integration Points

**1. Split replay-specific `Step` from reusable `Action`:**

Today, the driver consumes a replay-oriented step. A DST-capable design should introduce a smaller execution unit:

```zig
pub const Action = struct {
    name: []const u8,
    nondet_picks: Values,
};

pub const ReplayStep = struct {
    action: Action,
    expected_state: Values,
};
```

This preserves the current replay flow while letting DST drive the same implementation without inventing fake expected states.

**2. Simulator Module (`src/simulator.zig`):**

```zig
pub const Simulator = struct {
    seed: u64,
    prng: std.rand.Xoshiro256,
    virtual_time: u64,
    event_queue: EventQueue,
    fault_config: FaultConfig,
    trace: std.ArrayList(TraceEvent),

    pub fn init(seed: u64) Simulator {
        return .{
            .seed = seed,
            .prng = std.rand.Xoshiro256.init(seed),
            .virtual_time = 0,
            .event_queue = EventQueue.init(),
            .fault_config = FaultConfig.default(),
            .trace = std.ArrayList(TraceEvent).init(allocator),
        };
    }

    pub fn runSimulation(
        self: *Simulator,
        driver: anytype,
        config: SimConfig,
    ) !void {
        while (self.virtual_time < config.max_time) {
            // Generate action based on PRNG
            const action = self.generateAction();

            // Maybe inject fault
            if (self.shouldInjectFault()) {
                try self.injectFault();
            }

            // Execute action
            try driver.step(action);

            // Get driver state
            const driver_state = try driver.from_driver(allocator);

            // Check invariants (from Quint spec)
            try self.checkInvariants(driver_state);

            // Log to trace
            try self.trace.append(.{
                .time = self.virtual_time,
                .action = action,
                .state = driver_state,
            });

            // Advance time
            self.advanceTime();
        }
    }
};
```

**3. Execution Source Abstraction:**

Quizz's runner should consume an execution source rather than assuming every run comes from ITF:

```zig
pub const ExecutionSource = union(enum) {
    replay: ReplaySource,
    simulation: SimSource,
};
```

This lets `runner.zig` keep the reporting pipeline while swapping where actions originate.

**4. Action Generation from Spec:**

The Quint spec defines possible actions. The simulator can:
- Parse the spec to extract action definitions
- Generate valid action sequences dynamically
- Respect preconditions defined in spec

In practice, this is the hardest part of a **full** MBT + DST integration. Quizz currently gets actions indirectly through `quint run --mbt`; it does not yet have a model-runtime interface for "give me enabled actions from the current model state".

That makes a staged approach more realistic:
- Near term: generate actions from Zig-side knowledge plus seeded environment choices
- Mid term: seed simulations with existing ITF traces or use them as regression fixtures
- Long term: add a Quint model adapter or code generation path for enabled actions

**5. Invariant Extraction:**

Quint specs define invariants. These become runtime checks:

```zig
// Generated from Quint spec
fn checkInvariants(state: SpecState) !void {
    // From: invariant QuorumConsistency { ... }
    if (!quorumConsistency(state)) {
        return error.QuorumConsistencyViolation;
    }

    // From: invariant NoDataLoss { ... }
    if (!noDataLoss(state)) {
        return error.DataLossDetected;
    }
}
```

This area also has two levels of ambition:
- Immediate: let users register invariant callbacks in Zig over `Driver.State`
- Advanced: derive invariant checks from Quint so the simulator remains model-driven

### 5.6 API Design

```zig
pub const OracleMode = union(enum) {
    replay_compare: void,
    zig_invariants: []const InvariantFn,
    quint_model: ModelAdapter,
};

pub const DSTConfig = struct {
    seed: ?u64 = null,
    max_time: u64 = 10_000_000,
    max_steps: usize = 1_000_000,
    fault_config: FaultConfig = .{},
    oracle: OracleMode,
    spec_path: ?[]const u8 = null,
};

pub fn runDST(
    allocator: std.mem.Allocator,
    driver: anytype,
    config: DSTConfig,
) !DSTResult {
    var sim = Simulator.init(config.seed);
    defer sim.deinit();

    sim.runSimulation(driver, config) catch |err| {
        return DSTResult{
            .success = false,
            .seed = config.seed,
            .error = err,
            .trace_path = try sim.writeTrace(),
        };
    };

    return DSTResult{
        .success = true,
        .seed = config.seed,
        .steps_executed = sim.step_count,
        .time_simulated = sim.virtual_time,
    };
}

pub const DSTResult = struct {
    success: bool,
    seed: u64,
    steps_executed: usize,
    time_simulated: u64,
    trace_path: ?[]const u8,
    error: ?anyerror,
};
```

For Quizz specifically, the recommended adoption order is:

1. Keep replay MBT as the baseline mode
2. Refactor the driver contract around `Action` vs replay-only expected state
3. Add deterministic simulation with Zig invariants and reproducible event traces
4. Reuse ITF traces as regression fixtures and seed corpora
5. Only then invest in Quint-aware action and invariant extraction for full MBT + DST

---

## 6. Best Practices

### 6.1 Design Principles

1. **Determinism by Default**
   - All randomness from seeded PRNG
   - No wall-clock dependencies
   - Explicit time advancement

2. **Abstraction at I/O Boundary**
   - Single interface for real and simulated I/O
   - Use comptime selection (zero cost in production)
   - Keep abstraction minimal

3. **Same Binary, Different Modes**
   - Production and test code use same paths
   - Feature flags, not separate implementations
   - Reduces simulation/production gap

4. **Continuous Verification**
   - Check invariants after every step
   - Treat assertions as production code
   - 6,000+ assertions (TigerBeetle example)

5. **Seed-Based Reproducibility**
   - Log seed on every failure
   - CI runs known-failure seeds as regression
   - Minimize failing traces for debugging

### 6.2 Testing Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    TESTING PYRAMID FOR DST                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                         /\                                       │
│                        /  \     E2E / Integration               │
│                       /    \    (Real systems, Jepsen-style)    │
│                      /      \                                    │
│                     /────────\                                   │
│                    /          \  DST                             │
│                   /  FOCUS     \ (Simulated, deterministic)     │
│                  /    HERE      \                                │
│                 /────────────────\                               │
│                /                  \  Unit Tests                  │
│               /   Foundation       \ (Component-level)          │
│              /______________________\                            │
│                                                                  │
│  Allocation:                                                     │
│  - 70% DST (highest ROI for distributed systems)                │
│  - 20% Unit tests (fast feedback, component isolation)          │
│  - 10% Integration (production confidence)                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Failure Prioritization

| Priority | Failure Type | Example |
|----------|--------------|---------|
| **P0** | Data loss | Committed write disappears |
| **P0** | Safety violation | Two leaders elected |
| **P1** | Consistency | Stale read after write |
| **P1** | Deadlock | System stops making progress |
| **P2** | Performance | Tail latency spike |
| **P2** | Resource leak | Memory growth over time |
| **P3** | Cosmetic | Log formatting error |

### 6.4 Coverage Goals

```
Coverage Target Matrix:
══════════════════════

                        Single    Two-Fault    Complex
Failure Type            Fault     Combo        Scenario
─────────────────────────────────────────────────────────
Network partition       100%      80%          50%
Node crash              100%      80%          50%
Disk error              100%      60%          30%
Clock skew              80%       40%          20%
Byzantine               50%       20%          10%

Protocol State          Coverage
─────────────────────────────────
All states              100%
All transitions         100%
Error handling paths    95%
Recovery paths          95%
```

---

## 7. Sources

### Primary References

1. **Antithesis DST Documentation**
   - [Deterministic Simulation Testing Primer](https://antithesis.com/docs/resources/deterministic_simulation_testing/)
   - [How Antithesis Works](https://antithesis.com/product/how_antithesis_works/)
   - [Writing a Deterministic Hypervisor](https://antithesis.com/blog/deterministic_hypervisor/)

2. **TigerBeetle**
   - [VOPR Documentation](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md)
   - [Safety Concepts](https://docs.tigerbeetle.com/concepts/safety/)
   - [Browser Simulator Demo](https://tigerbeetle.com/blog/2023-07-11-we-put-a-distributed-database-in-the-browser/)
   - [A Descent Into the Vortex](https://tigerbeetle.com/blog/2025-02-13-a-descent-into-the-vortex/)

3. **FoundationDB**
   - [Testing Documentation](https://apple.github.io/foundationdb/testing.html)

4. **Industry Adoption**
   - [Jane Street Leads $105M Round in Antithesis](https://www.prnewswire.com/news-releases/jane-street-leads-antithesiss-105m-series-a-to-make-deterministic-simulation-testing-the-new-standard-302631076.html)
   - [WarpStream DST Implementation](https://www.warpstream.com/blog/deterministic-simulation-testing-for-our-entire-saas)
   - [CockroachDB: Taming Demonic Nondeterminism](https://www.cockroachlabs.com/blog/demonic-nondeterminism/)

5. **Technical Deep Dives**
   - [RisingWave: Deterministic Simulation Era](https://www.risingwave.com/blog/deterministic-simulation-a-new-era-of-distributed-system-testing/)
   - [Amplify Partners: DST Primer](https://www.amplifypartners.com/blog-posts/a-dst-primer-for-unit-test-maxxers)
   - [Pierre Zemb: Learn About DST](https://pierrezemb.fr/posts/learn-about-dst/)
   - [FOSDEM 2025: Squashing the Heisenbug](https://archive.fosdem.org/2025/schedule/event/fosdem-2025-4279-squashing-the-heisenbug-with-deterministic-simulation-testing/)

6. **Rust Implementations**
   - [S2.dev: DST for Async Rust](https://s2.dev/blog/dst)
   - [Polar Signals: DST in Rust](https://www.polarsignals.com/blog/posts/2025/07/08/dst-rust)

7. **Complementary Approaches**
   - [Jepsen](https://jepsen.io)
   - [Principles of Chaos Engineering](https://principlesofchaos.org)

---

## Appendix A: Zig Implementation Patterns

### A.1 Comptime I/O Selection

```zig
pub const IOMode = enum { real, simulation, replay };

pub fn createIO(comptime mode: IOMode) type {
    return switch (mode) {
        .real => @import("real_io.zig").RealIO,
        .simulation => @import("sim_io.zig").SimulatedIO,
        .replay => @import("replay_io.zig").ReplayIO,
    };
}

// Usage in driver
pub fn RaftDriver(comptime io_mode: IOMode) type {
    const IO = createIO(io_mode);

    return struct {
        io: IO,
        // ... rest of driver
    };
}
```

### A.2 Deterministic Allocator

```zig
pub const DeterministicAllocator = struct {
    backing: std.mem.Allocator,
    allocation_count: usize = 0,
    failure_schedule: []const bool = &.{},

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *DeterministicAllocator = @ptrCast(@alignCast(ctx));

        if (self.allocation_count < self.failure_schedule.len and
            self.failure_schedule[self.allocation_count]) {
            self.allocation_count += 1;
            return null; // Simulate OOM
        }

        self.allocation_count += 1;
        return self.backing.rawAlloc(len, ptr_align, ret_addr);
    }
};
```

---

## Appendix B: Comparison Matrix

| Feature | Quizz (Current) | Quizz + DST | TigerBeetle | Antithesis |
|---------|-----------------|-------------|-------------|------------|
| Formal spec integration | Yes (Quint) | Yes | No | No |
| Deterministic replay | Yes (traces) | Yes (seeds) | Yes | Yes |
| Dynamic exploration | No | Yes | Yes | Yes |
| Fault injection | No | Yes | Yes | Yes |
| Time control | No | Yes | Yes | Yes |
| Code modification required | No | Minimal | Yes | No |
| Language | Zig | Zig | Zig | Any (containers) |
| Open source | Yes | Yes | Yes | No |

---

*Document generated through comprehensive research on DST implementations and best practices. For integration assistance, refer to the Quizz project documentation.*
