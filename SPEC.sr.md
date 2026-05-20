# Sratch — token-economy spec

Single-char keywords, sigil-led statements. Newline OR `;` ends a statement.

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
```

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

## env
- `ANTHROPIC_API_KEY` — when set, `@` hits Anthropic; otherwise returns a stub.
- `SRATCH_MODEL` — default model id (default: `claude-haiku-4-5`).

## comments
A line beginning (after whitespace) with `'` is a comment until newline.
Comments cost tokens — omit in shipping agent code.

## minimum agent loop
```
h="sys\nGOAL:"+#in()
*?T{
  r=@h
  ?#has(r,"DONE:"){>r brk}
  ?#has(r,"SH:"){h=h+"\nO:"+#sh(#split(r,"SH:")[1])}:{h=h+"\nE"}
}
```
