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
  ?k=="@"{^"_llm("+_py_e(e[1])+")"}
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
  ?name=="join"{^a1+".join("+a0+")"}
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
import sys, subprocess, urllib.request

def _sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).rstrip(\"\\n\")
def _get(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode()
def _llm(p, m=None):
    return f\"[stub:{m or 'claude-haiku-4-5'}] {p}\"
def _react(p):
    return f\"DONE:[react-stub] {p}\"
"

:py_emit(ast){
  ^_PY_PRELUDE+"\n"+_py_blk(ast,0)
}
