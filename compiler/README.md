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

4. **emit_py.sra** — Sratch -> Python transpiler ✅
   Same traversal scaffold as emit.sra, different target language.
   Maps Sratch sigils to Python (`?{}:{}` -> if/else, `*n{}` -> for
   in range, `*?` -> while, `:f(){}` -> def). Forwards common `#`
   builtins to Python idioms (`#push(L,x)` -> `L.append(x)`,
   `#has(d,k)` -> `k in d`, etc.). Includes a small Python prelude
   wrapping subprocess/urllib/json. `emit_py_demo.sra` transpiles
   `:fact(n){?n<=1{^1} ^n*fact(n-1)}` and runs the result through
   `python3`, getting `720`.

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
