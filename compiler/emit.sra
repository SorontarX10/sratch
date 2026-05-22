' emit.sra — AST -> Sratch source. Bootstrap step 3.
'
' Walks the AST produced by parse.sra and emits an equivalent
' source string. Binary expressions are wrapped in parens for
' precedence safety; the output round-trips through lex+parse.

' --- escape table for re-emitting string literals ---
EMM={"\"":"\\\"","\\":"\\\\","\n":"\\n","\t":"\\t","\r":"\\r"}

:esc(s){
  r=""
  *c:s{
    ?#has(EMM,c){r=r+EMM[c]}:{r=r+c}
  }
  ^r
}

:indent(d){
  r=""
  *d{r=r+"  "}
  ^r
}

:join_es(L){
  P=[]
  *e:L{#push(P,e_e(e))}
  ^#join(P,",")
}

:join_pairs(L){
  P=[]
  *p:L{#push(P,e_e(p[0])+":"+e_e(p[1]))}
  ^#join(P,",")
}

' --- expression emitter ---
:e_e(e){
  k=e[0]
  ?k=="n"{^#str(e[1])}
  ?k=="s"{^"\""+esc(e[1])+"\""}
  ?k=="i"{^e[1]}
  ?k=="L"{^"["+join_es(e[1])+"]"}
  ?k=="D"{^"{"+join_pairs(e[1])+"}"}
  ?k=="B"{^"("+e_e(e[2])+e[1]+e_e(e[3])+")"}
  ?k=="U"{^e[1]+e_e(e[2])}
  ?k=="X"{^e_e(e[1])+"["+e_e(e[2])+"]"}
  ?k=="F"{^e_e(e[1])+"."+e[2]}
  ?k=="C"{^e_e(e[1])+"("+join_es(e[2])+")"}
  ?k=="T"{^"#"+e[1]+"("+join_es(e[2])+")"}
  ?k=="@"{r="@"+e_e(e[1]) ?e[2]!=N{r=r+" %"+e_e(e[2])} ^r}
  ?k=="~"{^"~"+e_e(e[1])}
  ^"<?expr:"+k+"?>"
}

' --- statement emitter (d = indent depth) ---
:e_s(s,d){
  k=s[0]
  i=indent(d)
  ?k=="="{^i+s[1]+"="+e_e(s[2])}
  ?k=="["{^i+e_e(s[1])+"["+e_e(s[2])+"]="+e_e(s[3])}
  ?k==">"{^i+">"+e_e(s[1])}
  ?k=="^"{^i+"^"+e_e(s[1])}
  ?k=="?"{
    r=i+"?"+e_e(s[1])+"{\n"+e_blk(s[2],d+1)+i+"}"
    ?s[3]!=N{r=r+":{\n"+e_blk(s[3],d+1)+i+"}"}
    ^r
  }
  ?k=="*"{^i+"*"+e_e(s[1])+"{\n"+e_blk(s[2],d+1)+i+"}"}
  ?k=="r"{^i+"*"+s[1]+":"+e_e(s[2])+"{\n"+e_blk(s[3],d+1)+i+"}"}
  ?k=="w"{^i+"*?"+e_e(s[1])+"{\n"+e_blk(s[2],d+1)+i+"}"}
  ?k==":"{^i+":"+s[1]+"("+#join(s[2],",")+"){\n"+e_blk(s[3],d+1)+i+"}"}
  ?k=="K"{^i+"brk"}
  ?k=="c"{^i+"cnt"}
  ?k=="E"{^i+e_e(s[1])}
  ^i+"<?stmt:"+k+"?>"
}

:e_blk(stmts,d){
  out=""
  *s:stmts{out=out+e_s(s,d)+"\n"}
  ^out
}

:emit(ast){^e_blk(ast,0)}
