' bench/p2s_compression.sra — measure py2sra real-world compression.
'
' Takes the agent-domain Python samples (same as lang_tokens.sra),
' runs them through tools/py2sra.py, and reports token reduction.
' Also runs the transpiled Sratch through the interpreter to confirm
' it parses cleanly (we can't run the LLM calls without a key, but
' parse-success is a strong correctness signal).

samples=[
  ["single LLM call",
"from anthropic import Anthropic
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'hi'}]).content[0].text)
"],
  ["multi-turn (3 msgs)",
"from anthropic import Anthropic
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'q1'},{'role':'assistant','content':'a1'},{'role':'user','content':'q2'}]).content[0].text)
"],
  ["LLM-summarize-a-URL",
"from anthropic import Anthropic
import urllib.request
page = urllib.request.urlopen('https://example.com').read().decode()
print(Anthropic().messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'Summarize in 3 bullets:\\n'+page}]).content[0].text)
"],
  ["real-world mid-size",
"import os, json, subprocess
from anthropic import Anthropic
import urllib.request
c = Anthropic()

def summarize(text):
  return c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'Summarize in 3 bullets:\\n'+text}]).content[0].text

def classify(text):
  return c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'Reply just URGENT or NORMAL: '+text}]).content[0].text

page = urllib.request.urlopen('https://example.com').read().decode()
summary = summarize(page)
print(summary)
tag = classify(summary).strip()
if 'URGENT' in tag:
  subprocess.run(['bash','-c','echo notified'],capture_output=True,text=True).stdout
else:
  print('ok')
"]
]

py_total=0
sra_total=0

>"task                       py_tok  sra_tok  ratio  saved  parse"
>"---                        ------  -------  -----  -----  -----"

*t:samples{
  nm=t[0]
  py=t[1]
  #wr("/tmp/p2s_in.py",py)
  sra=#sh("python3 tools/py2sra.py /tmp/p2s_in.py 2>&1")
  #wr("/tmp/p2s_out.sra",sra)
  ' parse-check: run the transpiled file with stdin closed; if parse
  ' fails the interpreter complains loudly. Stub-mode @ won't crash.
  parse_check=#sh("./target/release/sratch -e '#inc(\"/tmp/p2s_out.sra\")
>\"OK\"' 2>&1 | tail -1")
  pyt=#tk(py)
  srat=#tk(sra)
  py_total=py_total+pyt
  sra_total=sra_total+srat
  ratio=srat*100/pyt
  saved=pyt-srat
  ok="?"
  ?#has(parse_check,"OK"){ok="ok"}:{ok="FAIL"}
  pad=nm+"                              "
  >pad[0]+pad[1]+pad[2]+pad[3]+pad[4]+pad[5]+pad[6]+pad[7]+pad[8]+pad[9]+pad[10]+pad[11]+pad[12]+pad[13]+pad[14]+pad[15]+pad[16]+pad[17]+pad[18]+pad[19]+pad[20]+pad[21]+pad[22]+pad[23]+pad[24]+pad[25]+pad[26]+"  "+#str(pyt)+"     "+#str(srat)+"     "+#str(ratio)+"%   "+#str(saved)+"    "+ok
}

>""
>"=== aggregate ==="
>"python total : "+#str(py_total)+" tokens"
>"sratch total : "+#str(sra_total)+" tokens"
>"saved        : "+#str(py_total-sra_total)+" tokens ("+#str((py_total-sra_total)*100/py_total)+"%)"
>""
>"=== one transpiled file (real-world mid-size) ==="
>#sh("python3 tools/py2sra.py /tmp/p2s_in.py")
