' bench/lang_tokens.sra — empirical Python vs Sratch token cost.
'
' For each task: writes both impls to /tmp, runs both, normalizes
' output to "line1 line2 ..." for comparison, counts #tk on the
' source, and asserts both produce the expected output. Reports
' totals plus break-even against a minimal Sratch cheatsheet.
'
' Honest: we measure SOURCE tokens only. Real LLM cost includes
' prompt/thinking/iterations; this bench is the floor of the savings.

' Normalize output: collapse all whitespace runs (newlines, spaces,
' tabs) to single spaces, strip ends. Removes incidental spacing in
' list reprs ("[1, 2, 3]" vs "[1,2,3]") that aren't semantic.
:norm(s){
  out=""
  *c:s{?c==" "|c=="\n"|c=="\t"|c=="\r"{?#len(out)>0&out[#len(out)-1]!=" "{out=out+" "}}:{out=out+c}}
  ^#trim(out)
}
:nospace(s){
  out="" *c:s{?c!=" "&c!="\n"&c!="\t"&c!="\r"{out=out+c}}
  ^out
}

mark=:(b){?b{^"ok"} ^"FAIL"}

tasks=[
  ["fizzbuzz","1 2 F 4 B F 7 8 F B 11 F 13 14 FB",
"for i in range(1,16):
  if i%15==0: print('FB')
  elif i%3==0: print('F')
  elif i%5==0: print('B')
  else: print(i)
",
"*i:15{n=i+1 ?n%15==0{>\"FB\"}:{?n%3==0{>\"F\"}:{?n%5==0{>\"B\"}:{>n}}}}"],

  ["fact(8)=40320","40320",
"def f(n): return 1 if n<=1 else n*f(n-1)
print(f(8))
",
":f(n){?n<=1{^1} ^n*f(n-1)}
>f(8)"],

  ["fib(10)=55","55",
"def f(n): return n if n<2 else f(n-1)+f(n-2)
print(f(10))
",
":f(n){?n<2{^n} ^f(n-1)+f(n-2)}
>f(10)"],

  ["sum digits of 12345=15","15",
"print(sum(int(c) for c in '12345'))
",
"s=0 *c:\"12345\"{s=s+#num(c)}
>s"],

  ["reverse hello","olleh",
"print('hello'[::-1])
",
"r=\"\" *c:\"hello\"{r=c+r}
>r"],

  ["word count","3",
"print(len('ala ma kota'.split()))
",
">#len(#split(\"ala ma kota\",\" \"))"],

  ["sum CSV ints","15",
"print(sum(int(x) for x in '1,2,3,4,5'.split(',')))
",
"s=0 *x:#split(\"1,2,3,4,5\",\",\"){s=s+#num(x)}
>s"],

  ["count vowels in programming","3",
"print(sum(1 for c in 'programming' if c in 'aeiou'))
",
"n=0 *c:\"programming\"{?#has(\"aeiou\",c){n=n+1}}
>n"],

  ["count 'b's in aabbbc","3",
"print('aabbbc'.count('b'))
",
"n=0 *c:\"aabbbc\"{?c==\"b\"{n=n+1}}
>n"],

  ["flatten one level","[1,2,3,4]",
"print([y for x in [[1,2],[3,4]] for y in x])
",
"r=[] *x:[[1,2],[3,4]]{*y:x{#push(r,y)}}
>r"]
]

py_tot=0
sra_tot=0
ok=0

>"task                         py_tok  sra_tok  ratio  status"
>"---                          ------  -------  -----  ------"

*t:tasks{
  name=t[0]
  exp=t[1]
  py=t[2]
  sra=t[3]
  #wr("/tmp/bt.py",py)
  #wr("/tmp/bt.sra",sra)
  pyout=nospace(#sh("python3 /tmp/bt.py 2>&1"))
  sraout=nospace(#sh("./target/release/sratch /tmp/bt.sra 2>&1"))
  expn=nospace(exp)
  pyok=pyout==expn
  sraok=sraout==expn
  pyt=#tk(py)
  srat=#tk(sra)
  py_tot=py_tot+pyt
  sra_tot=sra_tot+srat
  ?pyok & sraok{ok=ok+1}
  ratio=srat*100/pyt
  pad=name+"                              "
  >pad[0]+pad[1]+pad[2]+pad[3]+pad[4]+pad[5]+pad[6]+pad[7]+pad[8]+pad[9]+pad[10]+pad[11]+pad[12]+pad[13]+pad[14]+pad[15]+pad[16]+pad[17]+pad[18]+pad[19]+pad[20]+pad[21]+pad[22]+pad[23]+pad[24]+pad[25]+pad[26]+pad[27]+pad[28]+"  "+#str(pyt)+"     "+#str(srat)+"     "+#str(ratio)+"%   py:"+mark(pyok)+" sra:"+mark(sraok)
}

>""
>"=== aggregate ==="
>"correct          : "+#str(ok)+"/"+#str(#len(tasks))
>"python total     : "+#str(py_tot)+" tokens"
>"sratch total     : "+#str(sra_tot)+" tokens"
saved=py_tot-sra_tot
>"sratch saved     : "+#str(saved)+" tokens ("+#str(saved*100/py_tot)+"%)"

>""
>"=== cheatsheet break-even ==="
cs="sratch:
?c{a}:{b} if/else
*n{...} repeat (i=counter)
*x:e{...} for-in
*?c{...} while
:f(a,b){^a+b} def
:(a,b){...} lambda
>x print  ^x return  brk cnt
ops: + - * / % == != < > <= >= & | !  =~ glob
#p #len #str #num #push #pop #has #split #join #sh #rd #wr #tk
[1,2,3] list  {k:v} dict
T F N true/false/nil
@p LLM  ~p ReAct  #use(p,{n:lambda}) tool-use
#inc(path) or #inc(path,\"M\") for M.fn()"
cs_tok=#tk(cs)
>"cheatsheet       : "+#str(cs_tok)+" tokens (paid once per session)"
>"saved per task   : "+#str(saved/#len(tasks))+" tokens"
?saved>0{
  be=cs_tok/(saved/#len(tasks))
  >"break-even at   : "+#str(be)+" tasks (after this Sratch is net cheaper)"
}:{
  >"NO SAVINGS — Sratch costs more on this set"
}

spec_tok=#tk(#rd("SPEC.sra.md"))
>"full SPEC.sra.md : "+#str(spec_tok)+" tokens"

>""
>"=== agent-domain (source-only; idiomatic SDK Python vs native Sratch) ==="
>"task                          py_tok  sra_tok  ratio"
>"---                           ------  -------  -----"

agent=[
  ["single LLM call",
"from anthropic import Anthropic
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'hi'}]).content[0].text)
",
">@\"hi\""],

  ["multi-turn (3 msgs)",
"from anthropic import Anthropic
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'q1'},{'role':'assistant','content':'a1'},{'role':'user','content':'q2'}]).content[0].text)
",
">@[\"q1\",\"a1\",\"q2\"]"],

  ["ReAct loop (SH/DONE protocol)",
"from anthropic import Anthropic; import subprocess
c = Anthropic(); h = 'goal'
for _ in range(20):
  r = c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':h}]).content[0].text
  if 'DONE:' in r: print(r); break
  if 'SH:' in r:
    o = subprocess.run(['bash','-c',r.split('SH:')[1].strip()],capture_output=True,text=True).stdout
    h += '\\nO:'+o
  else: h += '\\nE'
",
">~\"goal\""],

  ["native tool-use",
"from anthropic import Anthropic
c = Anthropic(); tools=[{'name':'sh','description':'run shell','input_schema':{'type':'object','properties':{'cmd':{'type':'string'}}}}]
msgs=[{'role':'user','content':'list files'}]
for _ in range(20):
  r = c.messages.create(model='claude-haiku-4-5',max_tokens=1024,tools=tools,messages=msgs)
  for b in r.content:
    if b.type=='text': print(b.text)
    elif b.type=='tool_use':
      import subprocess
      out = subprocess.run(['bash','-c',b.input['cmd']],capture_output=True,text=True).stdout
      msgs += [{'role':'assistant','content':r.content},{'role':'user','content':[{'type':'tool_result','tool_use_id':b.id,'content':out}]}]
  if r.stop_reason!='tool_use': break
",
">#use(\"list files\",{\"sh\"::(c){^#sh(c)}})"],

  ["agent-driven summary of a URL",
"from anthropic import Anthropic; import urllib.request
page = urllib.request.urlopen('https://example.com').read().decode()
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'Summarize in 3 bullets:\\n'+page}]).content[0].text)
",
">@(\"Summarize in 3 bullets:\\n\"+#get(\"https://example.com\"))"]
]

agent_py=0
agent_sra=0
*t:agent{
  nm=t[0]
  py=t[1]
  sra=t[2]
  pyt=#tk(py)
  srat=#tk(sra)
  agent_py=agent_py+pyt
  agent_sra=agent_sra+srat
  pad=nm+"                                "
  >pad[0]+pad[1]+pad[2]+pad[3]+pad[4]+pad[5]+pad[6]+pad[7]+pad[8]+pad[9]+pad[10]+pad[11]+pad[12]+pad[13]+pad[14]+pad[15]+pad[16]+pad[17]+pad[18]+pad[19]+pad[20]+pad[21]+pad[22]+pad[23]+pad[24]+pad[25]+pad[26]+pad[27]+pad[28]+pad[29]+"  "+#str(pyt)+"     "+#str(srat)+"     "+#str(srat*100/pyt)+"%"
}
>""
>"agent python total : "+#str(agent_py)+" tokens"
>"agent sratch total : "+#str(agent_sra)+" tokens"
ag_saved=agent_py-agent_sra
>"agent sratch saved : "+#str(ag_saved)+" tokens ("+#str(ag_saved*100/agent_py)+"%)"
>""
>"=== combined ==="
all_py=py_tot+agent_py
all_sra=sra_tot+agent_sra
all_saved=all_py-all_sra
>"all python total   : "+#str(all_py)+" tokens"
>"all sratch total   : "+#str(all_sra)+" tokens"
>"all sratch saved   : "+#str(all_saved)+" tokens ("+#str(all_saved*100/all_py)+"%)"
?all_saved>cs_tok{
  >"net win (after cheatsheet): "+#str(all_saved-cs_tok)+" tokens"
}:{
  >"net loss (after cheatsheet): "+#str(cs_tok-all_saved)+" tokens"
}
