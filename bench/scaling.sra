' bench/scaling.sra — does the Python/Sratch ratio change with size?
'
' For each N in [1,3,10,30,100] we generate three program shapes:
'   data  : N independent list-sum tasks (where Python's idioms win)
'   agent : N sequential LLM calls (where Sratch's @ wins)
'   mixed : N pairs of (data, agent) interleaved
' We measure source #tk for both Py and Sratch and print the ratio.
'
' Source-only (no run). Generators concatenate the same template N
' times around a one-time prelude (Python imports / Sratch nothing),
' which is exactly the "fixed setup vs per-op cost" trade-off.

:rep_py_data(n){
  out=""
  i=0
  *?i<n{
    out=out+"print(sum([1,2,3,4,5,6,7,8,9,10]))\n"
    i=i+1
  }
  ^out
}
:rep_sra_data(n){
  out=""
  i=0
  *?i<n{
    out=out+"s=0 *x:[1,2,3,4,5,6,7,8,9,10]{s=s+x}\n>s\n"
    i=i+1
  }
  ^out
}

:rep_py_agent(n){
  out="from anthropic import Anthropic\nc=Anthropic()\n"
  i=0
  *?i<n{
    out=out+"print(c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'q"+#str(i)+"'}]).content[0].text)\n"
    i=i+1
  }
  ^out
}
:rep_sra_agent(n){
  out=""
  i=0
  *?i<n{
    out=out+">@\"q"+#str(i)+"\"\n"
    i=i+1
  }
  ^out
}

:rep_py_mixed(n){
  out="from anthropic import Anthropic\nc=Anthropic()\n"
  i=0
  *?i<n{
    out=out+"print(sum([1,2,3,4,5,6,7,8,9,10]))\nprint(c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':'q"+#str(i)+"'}]).content[0].text)\n"
    i=i+1
  }
  ^out
}
:rep_sra_mixed(n){
  out=""
  i=0
  *?i<n{
    out=out+"s=0 *x:[1,2,3,4,5,6,7,8,9,10]{s=s+x}\n>s\n>@\"q"+#str(i)+"\"\n"
    i=i+1
  }
  ^out
}

:row(label,n,py,sra){
  pyt=#tk(py)
  srat=#tk(sra)
  ratio=srat*100/pyt
  saved=pyt-srat
  ' simple padding
  pad=label+"      "
  pn=#str(n)+"   "
  >pad[0]+pad[1]+pad[2]+pad[3]+pad[4]+pad[5]+"  N="+pn[0]+pn[1]+pn[2]+"  py="+#str(pyt)+"\tsra="+#str(srat)+"\tsra/py="+#str(ratio)+"%\tsaved="+#str(saved)
}

>"=== scaling: ratio as a function of program size ==="
>""
Ns=[1,3,10,30,100]

*n:Ns{row("data ",n,rep_py_data(n),rep_sra_data(n))}
>""
*n:Ns{row("agent",n,rep_py_agent(n),rep_sra_agent(n))}
>""
*n:Ns{row("mixed",n,rep_py_mixed(n),rep_sra_mixed(n))}

>""
>"=== realistic mid-size: ~7-function agent workflow ==="
' Hand-crafted: web fetch + summarize + branch on result + persist
py_real="import os, json, subprocess
from anthropic import Anthropic
import urllib.request
c = Anthropic()

def llm(p):
  return c.messages.create(model='claude-haiku-4-5',max_tokens=1024,messages=[{'role':'user','content':p}]).content[0].text

def fetch(url):
  return urllib.request.urlopen(url).read().decode()

def sh(cmd):
  return subprocess.run(['bash','-c',cmd],capture_output=True,text=True).stdout.strip()

def summarize(text):
  return llm('Summarize in 3 bullets:\\n'+text)

def classify(text):
  return llm('Reply just URGENT or NORMAL: '+text)

def save(path, content):
  with open(path,'w') as f: f.write(content)

def main():
  page = fetch('https://example.com')
  summary = summarize(page)
  print(summary)
  tag = classify(summary).strip()
  if 'URGENT' in tag:
    save('/tmp/urgent.txt', summary)
    sh('echo notified')
  else:
    save('/tmp/normal.txt', summary)

main()
"

sra_real=":summarize(t){^@(\"Summarize in 3 bullets:\\n\"+t)}
:classify(t){^@(\"Reply just URGENT or NORMAL: \"+t)}

page=#get(\"https://example.com\")
summary=summarize(page)
>summary
tag=#trim(classify(summary))
?#has(tag,\"URGENT\"){
  #wr(\"/tmp/urgent.txt\",summary)
  #sh(\"echo notified\")
}:{
  #wr(\"/tmp/normal.txt\",summary)
}
"

pyrt=#tk(py_real)
srart=#tk(sra_real)
>"python real-world : "+#str(pyrt)+" tokens, "+#str(#len(py_real))+" chars"
>"sratch real-world : "+#str(srart)+" tokens, "+#str(#len(sra_real))+" chars"
>"ratio             : "+#str(srart*100/pyrt)+"%"
>"saved             : "+#str(pyrt-srart)+" tokens"
