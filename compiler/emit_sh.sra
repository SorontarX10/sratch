' emit_sh.sra — Sratch -> Bash transpiler.
'
' Restricted subset (shell agents, not general computing):
'   - scalars (strings, integers as bash strings)
'   - lists as space-separated strings (no nesting)
'   - arithmetic (+ - * / %), comparison, control flow
'   - functions: single return value via stdout, captured by caller
'   - tools: p in sh len str num push join split has rng
'
' Not supported: dicts, nested lists, @, ~, =~ (regex match).

:_sh_runtime(){
  ^"#!/usr/bin/env bash
set -u
sr_add(){ if [[ \"$1\" =~ ^-?[0-9]+$ && \"$2\" =~ ^-?[0-9]+$ ]]; then printf %s $(( $1 + $2 )); else printf '%s%s' \"$1\" \"$2\"; fi; }
sr_sub(){ printf %s $(( $1 - $2 )); }
sr_mul(){ if [[ \"$1\" =~ ^-?[0-9]+$ && \"$2\" =~ ^-?[0-9]+$ ]]; then printf %s $(( $1 * $2 )); else local r=; local n=$2; while ((n-- > 0)); do r+=\"$1\"; done; printf '%s' \"$r\"; fi; }
sr_div(){ printf %s $(( $1 / $2 )); }
sr_mod(){ printf %s $(( $1 % $2 )); }
sr_neg(){ printf %s $(( 0 - $1 )); }
sr_eq(){ [[ \"$1\" == \"$2\" ]] && printf t; }
sr_ne(){ [[ \"$1\" != \"$2\" ]] && printf t; }
sr_lt(){ (( $1 < $2 )) 2>/dev/null && printf t; }
sr_gt(){ (( $1 > $2 )) 2>/dev/null && printf t; }
sr_le(){ (( $1 <= $2 )) 2>/dev/null && printf t; }
sr_ge(){ (( $1 >= $2 )) 2>/dev/null && printf t; }
sr_truthy(){ [[ -n \"${1:-}\" && \"$1\" != 0 && \"$1\" != f ]]; }
sr_not(){ if sr_truthy \"$1\"; then :; else printf t; fi; }
sr_and(){ if sr_truthy \"$1\"; then printf '%s' \"$2\"; else printf '%s' \"$1\"; fi; }
sr_or(){ if sr_truthy \"$1\"; then printf '%s' \"$1\"; else printf '%s' \"$2\"; fi; }
sr_p(){ echo \"$@\"; }
sr_len(){ if [[ \"$1\" == *\" \"* ]]; then local a; read -ra a <<< \"$1\"; echo ${#a[@]}; else echo ${#1}; fi; }
sr_idx(){ local a; read -ra a <<< \"$1\"; printf '%s' \"${a[$2]:-}\"; }
sr_str(){ printf '%s' \"$1\"; }
sr_num(){ if [[ \"$1\" =~ ^-?[0-9]+$ ]]; then printf '%s' \"$1\"; else printf 0; fi; }
sr_in(){ local r; IFS= read -r r; printf '%s' \"$r\"; }
sr_sh(){ bash -c \"$1\"; }
sr_join(){ local a; read -ra a <<< \"$1\"; local IFS=\"$2\"; printf '%s' \"${a[*]}\"; }
sr_split(){ printf '%s' \"$1\" | tr \"$2\" ' '; }
sr_has(){ case \" $1 \" in *\" $2 \"*) printf t;; esac; }
sr_push(){ if [[ -z \"$1\" ]]; then printf '%s' \"$2\"; else printf '%s %s' \"$1\" \"$2\"; fi; }
sr_rng(){ if [[ -z \"${2:-}\" ]]; then seq 0 $(( $1 - 1 )) | tr '\\n' ' '; else seq $1 $(( $2 - 1 )) | tr '\\n' ' '; fi; }

"
}

' --- helpers ---
_SHESC={"\"":"\\\"","\\":"\\\\","$":"\\$","`":"\\`"}

:_sh_esc(s){
  r=""
  *c:s{?#has(_SHESC,c){r=r+_SHESC[c]}:{r=r+c}}
  ^r
}
:_sh_ind(d){
  r=""
  *d{r=r+"  "}
  ^r
}

' Unquoted variant for use in for-in iteration (forces word splitting).
:_sh_e_unq(e){
  ?e[0]=="i"{^"${"+e[1]+":-}"}
  ?e[0]=="T"{^"$(sr_"+e[1]+" "+_sh_args(e[2])+")"}
  ?e[0]=="C"{^"$("+_sh_call_name(e[1])+" "+_sh_args(e[2])+")"}
  ^_sh_e(e)
}

:_sh_args(args){
  P=[]
  *a:args{#push(P,_sh_e(a))}
  ^#join(P," ")
}

' --- expressions: every expression becomes a bash string-producing form ---
:_sh_e(e){
  k=e[0]
  ?k=="n"{^#str(e[1])}
  ?k=="s"{^"\""+_sh_esc(e[1])+"\""}
  ?k=="i"{
    nm=e[1]
    ?nm=="T"{^"t"}
    ?nm=="F"{^"\"\""}
    ?nm=="N"{^"\"\""}
    ^"\"${"+nm+":-}\""
  }
  ?k=="L"{
    P=[]
    *x:e[1]{#push(P,_sh_e(x))}
    ^"\""+#join(P," ")+"\""
  }
  ?k=="B"{^_sh_bin(e[1],e[2],e[3])}
  ?k=="U"{
    inner=_sh_e(e[2])
    ?e[1]=="-"{^"\"$(sr_neg "+inner+")\""}
    ?e[1]=="!"{^"\"$(sr_not "+inner+")\""}
    ^inner
  }
  ?k=="X"{^"\"$(sr_idx "+_sh_e(e[1])+" "+_sh_e(e[2])+")\""}
  ?k=="F"{
    ' Dict field read: base must be a bare assoc-array variable.
    ?e[1][0]=="i"{^"\"${"+e[1][1]+"["+e[2]+"]}\""}
    ^"\"\""
  }
  ?k=="C"{
    P=[]
    *a:e[2]{#push(P,_sh_e(a))}
    ^"\"$("+_sh_call_name(e[1])+" "+#join(P," ")+")\""
  }
  ?k=="T"{
    P=[]
    *a:e[2]{#push(P,_sh_e(a))}
    ^"\"$(sr_"+e[1]+" "+#join(P," ")+")\""
  }
  ?k=="@"|k=="~"|k=="D"{^"\"# unsupported "+k+"\""}
  ^"\"\""
}

' Callee name: for direct Ident, drop quoting; otherwise eval expression.
:_sh_call_name(callee){
  ?callee[0]=="i"{^callee[1]}
  ^_sh_e(callee)
}

:_sh_bin(op,le,re){
  l=_sh_e(le)
  r=_sh_e(re)
  ?op=="+"{^"\"$(sr_add "+l+" "+r+")\""}
  ?op=="-"{^"\"$(sr_sub "+l+" "+r+")\""}
  ?op=="*"{^"\"$(sr_mul "+l+" "+r+")\""}
  ?op=="/"{^"\"$(sr_div "+l+" "+r+")\""}
  ?op=="%"{^"\"$(sr_mod "+l+" "+r+")\""}
  ?op=="=="{^"\"$(sr_eq "+l+" "+r+")\""}
  ?op=="!="{^"\"$(sr_ne "+l+" "+r+")\""}
  ?op=="<"{^"\"$(sr_lt "+l+" "+r+")\""}
  ?op==">"{^"\"$(sr_gt "+l+" "+r+")\""}
  ?op=="<="{^"\"$(sr_le "+l+" "+r+")\""}
  ?op==">="{^"\"$(sr_ge "+l+" "+r+")\""}
  ?op=="&"{^"\"$(sr_and "+l+" "+r+")\""}
  ?op=="|"{^"\"$(sr_or "+l+" "+r+")\""}
  ^"\"\""
}

' --- statements ---
:_sh_s(s,d){
  k=s[0]
  i=_sh_ind(d)
  ?k=="="{
    ' Dict literal -> bash associative array (declare -A). Limited:
    ' string keys only, no nesting, accessed via .field (the F node).
    ?s[2][0]=="D"{
      P=[]
      *pr:s[2][1]{#push(P,"["+_sh_e(pr[0])+"]="+_sh_e(pr[1]))}
      ^i+"declare -A "+s[1]+"=("+#join(P," ")+")"
    }
    ^i+s[1]+"="+_sh_e(s[2])
  }
  ?k==">"{^i+"echo "+_sh_e(s[1])}
  ?k=="^"{^i+"printf '%s' "+_sh_e(s[1])+"; return 0"}
  ?k=="?"{
    out=i+"if sr_truthy "+_sh_e(s[1])+"; then\n"+_sh_blk(s[2],d+1)
    ?s[3]!=N{out=out+i+"else\n"+_sh_blk(s[3],d+1)}
    out=out+i+"fi"
    ^out
  }
  ?k=="*"{
    body=_sh_blk(s[2],d+1)
    ^i+"for i in $(seq 0 $(("+_sh_e(s[1])+" - 1))); do\n"+body+i+"done"
  }
  ?k=="r"{
    body=_sh_blk(s[3],d+1)
    it=s[2]
    ' Number literal -> seq range
    ?it[0]=="n"{^i+"for "+s[1]+" in $(seq 0 $(("+_sh_e(it)+" - 1))); do\n"+body+i+"done"}
    ' List literal -> splat items inline, no quoting
    ?it[0]=="L"{
      P=[]
      *x:it[1]{#push(P,_sh_e(x))}
      ^i+"for "+s[1]+" in "+#join(P," ")+"; do\n"+body+i+"done"
    }
    ' Variable / expression -> rely on word-splitting (drop quotes)
    raw=_sh_e_unq(it)
    ^i+"for "+s[1]+" in "+raw+"; do\n"+body+i+"done"
  }
  ?k=="w"{
    body=_sh_blk(s[2],d+1)
    ^i+"while sr_truthy "+_sh_e(s[1])+"; do\n"+body+i+"done"
  }
  ?k==":"{
    head=i+s[1]+"(){\n"
    bd=""
    j=0
    *p:s[2]{
      bd=bd+_sh_ind(d+1)+"local "+p+"=\"${"+#str(j+1)+":-}\"\n"
      j=j+1
    }
    bd=bd+_sh_blk(s[3],d+1)
    ^head+bd+i+"}"
  }
  ?k=="K"{^i+"break"}
  ?k=="c"{^i+"continue"}
  ?k=="E"{
    ' Bare-call statement: drop the outer $() wrapping if it's a call.
    e=s[1]
    ?e[0]=="C"{
      P=[]
      *a:e[2]{#push(P,_sh_e(a))}
      ^i+_sh_call_name(e[1])+" "+#join(P," ")
    }
    ?e[0]=="T"{
      P=[]
      *a:e[2]{#push(P,_sh_e(a))}
      ^i+"sr_"+e[1]+" "+#join(P," ")
    }
    ^i+":  # expr: "+_sh_e(e)
  }
  ^i+"# unknown: "+k
}

:_sh_blk(stmts,d){
  out=""
  *s:stmts{out=out+_sh_s(s,d)+"\n"}
  ^out
}

' --- entry ---
:emit_sh(ast){
  ^_sh_runtime()+_sh_blk(ast,0)
}
