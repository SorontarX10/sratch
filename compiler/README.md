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

4. **emit_py.sra** — Sratch -> Python transpiler (planned). Same AST
   traversal, different target.

5. **eval.sra** — tree-walking evaluator in Sratch. Closes the loop:
   `eval(parse(lex(src)))` reproduces the Rust interpreter's behavior.
   At this point Sratch hosts itself.

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
