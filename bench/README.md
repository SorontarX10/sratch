# ReAct loop — source-size comparison

Same functional spec across all files:

> Read goal from stdin. Loop: call LLM with running history; if reply
> contains `DONE:` print and exit; if reply contains `SH:`, run the
> shell command after the marker and append `O:<stdout>` to the history;
> else append `E` (error) and continue.

Chars (excluding trailing newline), measured on the files in this dir:

| file        | chars | lines |
|-------------|------:|------:|
| sratch.sr   |   152 |     2 |
| bash.sh     |   473 |     6 |
| py.py       |   417 |     9 |
| js.js       |   562 |     7 |
| go.go       |  1094 |    18 |

BPE tokenizers (tiktoken/Claude) hit roughly 3.5–4 source chars per
token on code; the char-count ratios above are a tight proxy for the
token ratios. Sratch is ~3× more compact than Python and ~7× more
compact than Go for the same agent.
