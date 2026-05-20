# ReAct loop — source-size comparison

Same functional spec across all files:

> Read goal from stdin. Loop: call LLM with running history; if reply
> contains `DONE:` print and exit; if reply contains `SH:`, run the
> shell command after the marker and append `O:<stdout>` to the history;
> else append `E` (error) and continue.

Chars (excluding trailing newline), measured on the files in this dir:

| file        | chars | lines | vs sratch |
|-------------|------:|------:|----------:|
| sratch.sr   |    17 |     1 |      1.0× |
| bash.sh     |   473 |     6 |     27.8× |
| py.py       |   417 |     9 |     24.5× |
| js.js       |   562 |     7 |     33.0× |
| go.go       |  1094 |    18 |     64.3× |

`bench/sratch.sr` in full:

```
>~("\R\G"+#in())
```

How it gets this small:

1. **`~` is a runtime ReAct primitive.** It takes an initial prompt
   string, drives the LLM/shell/observation loop internally, and
   returns the final `DONE:` text. No user-level loop needed.
2. **Lex-time string compression.** Within a string literal, the
   escape codes `\R \D \S \G \O \E` expand to the agent vocabulary
   ("ReAct. Reply SH:<cmd> or DONE:<text>\n", "DONE:", "SH:",
   "GOAL:", "\nO:", "\nE"). `"\R\G"` is the entire 38-char system
   prompt + goal label in 4 source chars.

The original ~140-char explicit version still works (see
`examples/agent.sr`) — `~` is sugar over it.

BPE tokenizers (tiktoken / Claude) hit ~3.5–4 source chars per token
on code, so the char-count ratios proxy the token-count ratios
closely.
