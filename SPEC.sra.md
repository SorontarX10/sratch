# Sratch — token-economy spec

Source files use the `.sra` extension. Single-char keywords,
sigil-led statements. Newline OR `;` ends a statement.

## stmt
```
a=e           assign
a[i]=e        index-assign
>e            print
^e            return
?c{s}         if
?c{s}:{s}     if/else (nest for elif)
*n{s}         repeat n times (i = 0..n-1 in scope)
*x:e{s}       for x in e  (e: list|str|dict-keys|number-range)
*?c{s}        while
:f(a,b){s}    define function
brk cnt       break / continue
expr          bare expression
```

## expr
```
literals:  42  3.14  "txt"  [a,b]  {k:v}
prelude:   T F N            (true / false / nil; user may shadow)
ops:       + - * / %    (+ on str/list = concat; * str,n = repeat)
cmp:       == != < > <= >=
logic:     & |              (and / or, short-circuit)  !x (not)
index:     e[i]    e.k       (.k == e["k"])
call:      f(a,b)
@e         LLM(prompt=e)              -> string
@e %m      LLM with model m           -> string
#t(a,b)    call tool t                -> value
~e         ReAct(initial=e)           -> final DONE: text
```

## string escapes (agent-vocab dictionary)
```
\n \t \r \\ \" \0    standard
\R   "ReAct. Reply SH:<cmd> or DONE:<text>\n"
\D   "DONE:"
\S   "SH:"
\G   "GOAL:"
\O   "\nO:"
\E   "\nE"
```
Expanded at lex time; one source char of escape = up to 38 chars of
runtime string. `"\R\G"` builds the entire ReAct system+goal header.

## tools (#name)
```
io:     p(..)  in()
str:    len(x)  str(x)  num(x)  split(s,sep)  join(l,sep)  up(s)  lo(s)
        trim(s)  has(x,k)
list:   push(l,..)  pop(l)  rng(n)  rng(lo,hi)
dict:   keys(d)  vals(d)  has(d,k)
fs:     rd(p)  wr(p,s)
sys:    sh(cmd)  get(url)  post(url,body)
json:   j(v)        encode
        uj(s)       decode
```

## providers
`@` / `~` dispatch by model-name prefix:
- `claude-*` (default) → Anthropic; needs `ANTHROPIC_API_KEY`
- `gpt-*` / `o1*` / `o3*` / `o4*` / `chatgpt*` → OpenAI; needs `OPENAI_API_KEY`

Without the matching key, the call returns a deterministic stub
(`[stub:<model>] <prompt>`) so programs remain runnable offline.

## env
- `SRATCH_MODEL` — default model id (default: `claude-haiku-4-5`)
- `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` — provider credentials
- `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` — override API base URLs

## comments
A line beginning (after whitespace) with `'` is a comment until newline.
Comments cost tokens — omit in shipping agent code.

## minimum agent loop

Built-in primitive form (17 chars):
```
>~("\R\G"+#in())
```

Explicit form for custom tools / control flow:
```
h="\R\G"+#in()
*?T{
  r=@h
  ?#has(r,"\D"){>r brk}
  ?#has(r,"\S"){h=h+"\O"+#sh(#split(r,"\S")[1])}:{h=h+"\E"}
}
```

## env
- `SRATCH_AGENT_MAX` — max iterations for `~` (default 20).
- `SRATCH_TRACE`     — when set, `~` prints `<<reply` / `>>O:obs` to
  stderr each iteration.
