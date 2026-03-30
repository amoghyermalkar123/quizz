## Project:
Quizz is a zig port of the rust-based quint-connect project.

### What is Quizz/ Quint-connect: 
This is an effort to tie formal proofs written in a language like [quint](https://quint-lang.org/)
to actual implementations written in developer languages such as Zig (Quizz) and Rust (quint-connect).
The goal is to perform [MBT](https://en.wikipedia.org/wiki/Model-based_testing) as a compile/ testing feature of the project itself.
With quizz I am trying to perform MBT at comptime (although currently it runs at runtime, but thats the goal if possible)


## Running the raft spec

1. Run the raft example against the Quint spec:
```
zig build run -- examples/raft/spec/raft.qnt
```

## Quint Project:
Quint is a fantastic new language for writing formal specifications and also an ecosystem of new tools
for doing model-based testing and much more.

- Quint Language: https://quint-lang.org/
- Quint-Connect: https://github.com/informalsystems/quint-connect
