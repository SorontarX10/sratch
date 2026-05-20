# Sratch

A programming language for AI agents, optimized for **token economy**, not
human readability. Every keyword is a single ASCII sigil; LLM calls and tool
calls are first-class primitives.

## Why

When an LLM writes (or reads) code at inference time, characters are tokens
and tokens are money + latency. Sratch is built around the principle that
the agent-author of the program is itself an LLM. Saving 30–60% of source
tokens on agent code is meaningful at scale.

Sratch trades human readability for:
- single-character keywords (`?`, `*`, `:`, `>`, `^`)
- first-class `@` for LLM calls, `#` for tool/builtin calls
- zero ceremony: no `let`, `fn`, `if`, `return`, `print`

## Build / run

```
cargo build --release
./target/release/sratch examples/fizz.sr
echo '>"hi"' | ./target/release/sratch -
./target/release/sratch -e ':sq(n){^n*n}
>sq(7)'
```

## Cheat sheet

| sratch                 | meaning                                |
|------------------------|----------------------------------------|
| `a=5`                  | assign                                 |
| `>x`                   | print                                  |
| `^x`                   | return                                 |
| `?c{a}:{b}`            | if/else                                |
| `*n{...}`              | repeat n times (`i` = counter)         |
| `*x:e{...}`            | for-in over list/str/dict/number       |
| `*?c{...}`             | while                                  |
| `:f(a,b){^a+b}`        | define function                        |
| `@"prompt"`            | call LLM, returns string               |
| `@p %"opus-4-7"`       | call LLM with explicit model           |
| `#sh("ls -la")`        | run shell, returns stdout              |
| `#get("https://...")`  | HTTP GET                               |
| `T F N`                | true / false / nil literals (env vars) |

See [`SPEC.sr.md`](SPEC.sr.md) for the full surface.

## Agent in 6 lines

```
h="ReAct agent. Reply SH:<cmd> or DONE:<text>\nGOAL:"+#in()
*?T{
  r=@h
  ?#has(r,"DONE:"){>r brk}
  ?#has(r,"SH:"){h=h+"\nO:"+#sh(#split(r,"SH:")[1])}:{h=h+"\nE"}
}
```

## Status

Tree-walking interpreter in Rust, no third-party crates. LLM/HTTP calls
shell out to `curl`. Set `ANTHROPIC_API_KEY` for live `@` calls; without it,
`@` returns a deterministic stub so programs stay runnable offline.
