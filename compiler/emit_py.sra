' emit_py.sra — Sratch AST -> Python source. Bootstrap step 4b.
'
' Same traversal scaffold as emit.sra, different target. Lets an
' agent author in Sratch and ship plain Python. Coverage is the
' "everyday" subset: arithmetic, control flow, functions, lists,
' dicts, common builtins. LLM/agent primitives stub out.

' --- helpers ---
_PYBIN={"+":"+","-":"-","*":"*","/":"/","%":"%","==":"==","!=":"!=","<":"<",">":">","<=":"<=",">=":">=","&":"and","|":"or"}
_PYESC={"\"":"\\\"","\\":"\\\\","\n":"\\n","\t":"\\t","\r":"\\r"}

:_py_ind(d){
  r=""
  *d{r=r+"    "}
  ^r
}

:_py_esc(s){
  r=""
  *c:s{?#has(_PYESC,c){r=r+_PYESC[c]}:{r=r+c}}
  ^r
}

:_py_id(n){
  ?n=="T"{^"True"}
  ?n=="F"{^"False"}
  ?n=="N"{^"None"}
  ^n
}

' --- expression ---
:_py_e(e){
  k=e[0]
  ?k=="n"{^#str(e[1])}
  ?k=="s"{^"\""+_py_esc(e[1])+"\""}
  ?k=="i"{^_py_id(e[1])}
  ?k=="L"{
    P=[]
    *x:e[1]{#push(P,_py_e(x))}
    ^"["+#join(P,",")+"]"
  }
  ?k=="D"{
    P=[]
    *p:e[1]{#push(P,_py_e(p[0])+":"+_py_e(p[1]))}
    ^"{"+#join(P,",")+"}"
  }
  ?k=="B"{
    op=e[1]
    pop=op
    ?#has(_PYBIN,op){pop=_PYBIN[op]}
    ^"("+_py_e(e[2])+" "+pop+" "+_py_e(e[3])+")"
  }
  ?k=="U"{
    ?e[1]=="!"{^"(not "+_py_e(e[2])+")"}
    ^"(-"+_py_e(e[2])+")"
  }
  ?k=="X"{^_py_e(e[1])+"["+_py_e(e[2])+"]"}
  ?k=="F"{^_py_e(e[1])+"[\""+e[2]+"\"]"}
  ?k=="C"{
    P=[]
    *a:e[2]{#push(P,_py_e(a))}
    ^_py_e(e[1])+"("+#join(P,",")+")"
  }
  ?k=="T"{
    P=[]
    *a:e[2]{#push(P,_py_e(a))}
    ^_py_tool(e[1],P)
  }
  ?k=="@"{
    ?e[2]!=N{^"_llm("+_py_e(e[1])+","+_py_e(e[2])+")"}
    ^"_llm("+_py_e(e[1])+")"
  }
  ?k=="~"{^"_react("+_py_e(e[1])+")"}
  ^"None"
}

' --- tool dispatch: Sratch # -> Python expression ---
:_py_tool(name,av){
  a0="" a1=""
  ?#len(av)>0{a0=av[0]}
  ?#len(av)>1{a1=av[1]}
  cs=#join(av,",")
  ?name=="p"{^"print("+cs+")"}
  ?name=="in"{^"input()"}
  ?name=="len"{^"len("+a0+")"}
  ?name=="str"{^"str("+a0+")"}
  ?name=="num"{^"float("+a0+")"}
  ?name=="push"{^a0+".append("+a1+")"}
  ?name=="pop"{^a0+".pop()"}
  ?name=="has"{^"("+a1+" in "+a0+")"}
  ?name=="split"{^a0+".split("+a1+")"}
  ?name=="join"{^a1+".join(str(x) for x in "+a0+")"}
  ?name=="up"{^a0+".upper()"}
  ?name=="lo"{^a0+".lower()"}
  ?name=="trim"{^a0+".strip()"}
  ?name=="keys"{^"list("+a0+".keys())"}
  ?name=="vals"{^"list("+a0+".values())"}
  ?name=="j"{^"_json.dumps("+a0+")"}
  ?name=="uj"{^"_json.loads("+a0+")"}
  ?name=="tk"{^"max(1,len("+a0+")//4)"}
  ?name=="rng"{
    ?#len(av)==1{^"list(range("+a0+"))"}
    ^"list(range("+a0+","+a1+"))"
  }
  ?name=="sh"{^"_sh("+a0+")"}
  ?name=="get"{^"_get("+a0+")"}
  ^"# unknown_tool_"+name+"("+cs+")"
}

' --- statement ---
:_py_blk(stmts,d){
  ?#len(stmts)==0{^_py_ind(d)+"pass\n"}
  out=""
  *st:stmts{out=out+_py_s(st,d)+"\n"}
  ^out
}

:_py_s(s,d){
  k=s[0]
  i=_py_ind(d)
  ?k=="="{^i+s[1]+" = "+_py_e(s[2])}
  ?k=="["{^i+_py_e(s[1])+"["+_py_e(s[2])+"] = "+_py_e(s[3])}
  ?k==">"{^i+"print("+_py_e(s[1])+")"}
  ?k=="^"{^i+"return "+_py_e(s[1])}
  ?k=="?"{
    r=i+"if "+_py_e(s[1])+":\n"+_py_blk(s[2],d+1)
    ?s[3]!=N{r=r+i+"else:\n"+_py_blk(s[3],d+1)}
    ^r
  }
  ?k=="*"{^i+"for i in range(int("+_py_e(s[1])+")):\n"+_py_blk(s[2],d+1)}
  ?k=="r"{^i+"for "+s[1]+" in ("+_py_e(s[2])+" if not isinstance("+_py_e(s[2])+",(int,float)) else range(int("+_py_e(s[2])+"))):\n"+_py_blk(s[3],d+1)}
  ?k=="w"{^i+"while "+_py_e(s[1])+":\n"+_py_blk(s[2],d+1)}
  ?k==":"{
    ps=#join(s[2],",")
    ^i+"def "+s[1]+"("+ps+"):\n"+_py_blk(s[3],d+1)
  }
  ?k=="K"{^i+"break"}
  ?k=="c"{^i+"continue"}
  ?k=="E"{^i+_py_e(s[1])}
  ^i+"# unknown_stmt_"+k
}

' --- prelude: bring in Python deps used by emitted code ---
_PY_PRELUDE="import json as _json
import os, sys, subprocess, urllib.request

_MI=[0]
def _sh(cmd):
    return subprocess.run([\"bash\",\"-c\",cmd], capture_output=True, text=True).stdout.rstrip(\"\\n\")
def _get(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode()
def _llm(p, m=None):
    m = m or os.environ.get(\"SRATCH_MODEL\") or \"claude-haiku-4-5\"
    mk = os.environ.get(\"SRATCH_MOCK\")
    if mk is not None:
        parts = mk.split(\"\\n---\\n\"); r = parts[_MI[0] % len(parts)]; _MI[0]+=1; return r
    isO = m[:4]==\"gpt-\" or m[:2] in (\"o1\",\"o3\",\"o4\") or m[:7]==\"chatgpt\"
    key = os.environ.get(\"OPENAI_API_KEY\" if isO else \"ANTHROPIC_API_KEY\")
    if not key:
        return f\"[stub:{m}] {p}\"
    if isO:
        url=(os.environ.get(\"OPENAI_BASE_URL\") or \"https://api.openai.com\")+\"/v1/chat/completions\"
        hdr=[\"-H\",\"authorization: Bearer \"+key]
        body=_json.dumps({\"model\":m,\"messages\":[{\"role\":\"user\",\"content\":p}]})
    else:
        url=(os.environ.get(\"ANTHROPIC_BASE_URL\") or \"https://api.anthropic.com\")+\"/v1/messages\"
        hdr=[\"-H\",\"x-api-key: \"+key,\"-H\",\"anthropic-version: 2023-06-01\"]
        body=_json.dumps({\"model\":m,\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":p}]})
    out=subprocess.run([\"curl\",\"-sS\",\"-X\",\"POST\",url,\"-H\",\"content-type: application/json\"]+hdr+[\"-d\",\"@-\"], input=body, capture_output=True, text=True).stdout
    try:
        j=_json.loads(out); return j[\"choices\"][0][\"message\"][\"content\"] if isO else j[\"content\"][0][\"text\"]
    except Exception:
        return out
def _react(h):
    mx=int(os.environ.get(\"SRATCH_AGENT_MAX\") or \"20\"); o=\"\"
    for _ in range(mx):
        r=_llm(str(h))
        if \"DONE:\" in r: return r
        j=r.find(\"SH:\")
        if j>=0: h=str(h)+\"\\nO:\"+_sh(r[j+3:].strip())
        else: h=str(h)+\"\\nE\"
        o=r
    return o
"

:py_emit(ast){
  ^_PY_PRELUDE+"\n"+_py_blk(ast,0)
}
