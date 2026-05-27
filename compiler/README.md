# Sratch self-hosting bootstrap

The Rust reference implementation in `src/` interprets `.sra` files
directly. This `compiler/` directory is the path to self-hosting: a
Sratch compiler written in Sratch.

## Roadmap

1. **lex.sra** — lexer in Sratch ✅
   Reads source string, emits a list of `[t,v]` token pairs.
   Recognized: numbers, strings (with full escape dictionary including
   agent vocabulary `\R\D\S\G\O\E`), identifiers, single- and
   two-character operators (`== != <= >= *? =~`), line comments (`'`).

2. **parse.sra** — recursive-descent parser. Consumes the token list
   from `lex.sra`, emits an AST encoded as nested lists. Mirrors the
   Pratt-style parser in `src/parser.rs`.

3. **emit.sra** — AST -> Sratch source pretty-printer ✅
   Walks the AST nested-list form back to source. Wraps binaries in
   parens for precedence safety; re-escapes string literals. Used as
   the first end-to-end correctness check via parse(emit(parse(src)))
   == parse(src). `compiler/emit_demo.sra` runs the full round trip
   and prints "ROUND-TRIP OK".

4. **emit_{js,py,sh,html}.sra** — multi-target transpilers ✅
   Same AST traversal pattern, one file per target. `quad_demo.sra`
   compiles ONE Sratch source to four targets and runs the three
   runnables (JS via `node`, Python via `python3`, Bash via `bash`)
   to confirm identical output. HTML wraps the JS in a self-contained
   page with `console.log` redirected to a `<pre>`.

   Token economy on the demo program (recursive fact + list ops):
   - Sratch source:   67 tok /   87 chars (1.0×)
   - Python output:  279 tok /  621 chars (4.2×)
   - Bash output:   1195 tok / 2139 chars (17.8×, scalar-only subset)
   - JS output:     2000 tok / 3242 chars (29.9×, hefty inline runtime)
   - HTML output:   2498 tok / 4236 chars (37.3×, JS + DOM wrapper)

   Adding a new target = one file exposing `<lang>_emit(ast)`. The
   per-target file owns its inline runtime + per-AST-tag dispatch;
   no shared framework needed.

### Per-target notes

- **emit_js.sra** — JavaScript with inline `sr` runtime.
   Same AST traversal scaffold as emit.sra, different target. Emits
   a self-contained `.js` file: inline `sr` runtime that bridges
   Sratch semantics (truthiness, `+`/`*` on strings/lists, negative
   indexing, `iter()` over numbers/strings/dicts, glob match via
   RegExp, common `#` tools) followed by the transpiled program.
   Hoists per-block locals into a single `let`. `emit_js_demo.sra`
   transpiles `:fact(n){?n<=1{^1} ^n*fact(n-1)}` plus a small extra
   test program, runs the result through `node`, and prints
   `720, 1, 4, 9, 16, 10,20,30,40, hello`. Out of scope so far:
   `@` (LLM) and `~` (agent) — they throw at runtime.

- **emit_py.sra** — Python target. Maps Sratch sigils to native
  idioms (`#push(L,x)` -> `L.append(x)`, `#has(d,k)` -> `k in d`).
  Compact runtime (no inline `sr` object, just module-level helpers).

- **emit_sh.sra** — Bash, restricted subset. Scalars, lists as
  space-separated strings (no nesting/dicts), arithmetic, control
  flow, functions with single return via stdout capture. Tools:
  `p in sh len str num push join split has rng`. `@`/`~`/dicts
  unsupported. List literal `[1,2,3]` becomes `"1 2 3"`; for-in
  splats unquoted to force word splitting.

- **emit_html.sra** — wraps `emit_js` output in a self-contained
  `.html` page with `console.log` redirected to a `<pre>`. Open the
  file in a browser, output renders in the page.

5. **eval.sra** — tree-walking evaluator in Sratch ✅
   Closes the bootstrap. Maintains its own environment as
   `ENV={"scopes":[{}],"barriers":[]}` (same shape as the Rust impl,
   including function barriers). Dispatches AST tags, forwards `#`
   builtin tool calls to the native interpreter, handles recursion
   via tagged Flow lists `["N"]`/`["R",v]`/`["K"]`/`["C"]`.
   `compiler/eval_demo.sra` evaluates four programs end-to-end:
   `add(3,4)`, `fact(6)`, FizzBuzz 1..6, and list-mutating squares.

## Modules

Two ways to load a compiler module:

```
#inc("compiler/parse.sra")        ' defs land as plain globals
#inc("compiler/parse.sra", "P")   ' defs mangled to P_*, plus P dict
```

With a prefix, `#inc` collects every top-level def/assign name and
rewrites that name plus every reference to it (anywhere in the file)
to `P_name`. After eval, it builds a dict `P = {name: P_name, ...}`
so callers can write `P.parse(tks)` without remembering the mangled
form. Module-internal state (`toks`, `pi`, `ENV`) is declared at the
top of the file so it gets mangled too — that's what makes
helper functions (`peek`, `bump`) able to mutate it across calls
under function-barrier scoping.

Internal helpers still start with `_` (`_prog`, `_stmt`, `_expr`,
`_atom`) — that convention covers the no-prefix case where defs land
in the plain global namespace. With a prefix you don't strictly need
the underscores, but the names stay short.

## Token format

Each token is a 2-element list `[t, v]`:

| `t` | meaning  | examples of `v`                   |
|-----|----------|-----------------------------------|
| `n` | number   | `"42"`, `"3.14"`                  |
| `s` | string   | decoded contents, escapes expanded |
| `i` | ident    | `"foo"`, `"cnt"`, `"T"`           |
| `o` | op/punct | `"+"`, `"=="`, `"\n"`, `"{"`, `"~"` |

Newlines are emitted as `["o","\n"]` so the parser can use them as
statement separators (identical to the Rust reference).

## Running

```
./target/release/sratch compiler/demo.sra
```

Demo lexes the program `a=5+1\n?a==6{>"hi"}` and prints the token
stream. Once `parse.sra` lands, demo will chain into it.

## Thinking in Sratch

When designing new compiler passes we sketch in Sratch syntax rather
than English pseudocode. Example planning note for the parser:

```
:parse_expr(){^parse_or()}
:parse_or(){l=parse_and()
  *?peek()=="|"{eat() r=parse_and() l=["bin","|",l,r]}
  ^l
}
```

The pseudocode IS the language. This is the point of Sratch.
