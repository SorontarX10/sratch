' eval.sra — tree-walking interpreter in Sratch. Bootstrap step 4.
' Closes the loop: eval_ast(parse(lex(src))) matches native semantics.
'
' ENV is a module-global. When loaded via #inc(path,"E") it is
' mangled to E_ENV and helper-internal references rewrite to match.
'
' Flow is a tagged list:
'   ["N"]       normal completion
'   ["R", v]    return v from the current function
'   ["K"]       break
'   ["C"]       continue

ENV={"scopes":[{}],"barriers":[]}

' --- env management ---
:env_push(){#push(ENV.scopes,{})}
:env_pop(){#pop(ENV.scopes)}
:env_enter_fn(){
  #push(ENV.barriers,#len(ENV.scopes))
  #push(ENV.scopes,{})
}
:env_leave_fn(){
  #pop(ENV.scopes)
  #pop(ENV.barriers)
}

:env_get(n){
  i=#len(ENV.scopes)-1
  *?i>=0{
    s=ENV.scopes[i]
    ?#has(s,n){^s[n]}
    i=i-1
  }
  ^N
}

:env_set(n,v){
  b=0
  ?#len(ENV.barriers)>0{b=ENV.barriers[#len(ENV.barriers)-1]}
  i=#len(ENV.scopes)-1
  *?i>=b{
    s=ENV.scopes[i]
    ?#has(s,n){s[n]=v ^N}
    i=i-1
  }
  ?b>0 & #has(ENV.scopes[0],n){ENV.scopes[0][n]=v ^N}
  ENV.scopes[#len(ENV.scopes)-1][n]=v
}

:env_set_local(n,v){
  ENV.scopes[#len(ENV.scopes)-1][n]=v
}

' --- binary operator dispatch ---
:e_bin(op,a,b){
  ?op=="+"{^a+b}
  ?op=="-"{^a-b}
  ?op=="*"{^a*b}
  ?op=="/"{^a/b}
  ?op=="%"{^a%b}
  ?op=="=="{^a==b}
  ?op=="!="{^a!=b}
  ?op=="<"{^a<b}
  ?op==">"{^a>b}
  ?op=="<="{^a<=b}
  ?op==">="{^a>=b}
  ?op=="&"{^a&b}
  ?op=="|"{^a|b}
  ?op=="=~"{^a=~b}
  ^N
}

' --- expression eval ---
:e_e(e){
  k=e[0]
  ?k=="n"{^e[1]}
  ?k=="s"{^e[1]}
  ?k=="i"{
    nm=e[1]
    ?nm=="T"{^T}
    ?nm=="F"{^F}
    ?nm=="N"{^N}
    ^env_get(nm)
  }
  ?k=="L"{
    out=[]
    *x:e[1]{#push(out,e_e(x))}
    ^out
  }
  ?k=="D"{
    out={}
    *p:e[1]{out[e_e(p[0])]=e_e(p[1])}
    ^out
  }
  ?k=="B"{^e_bin(e[1],e_e(e[2]),e_e(e[3]))}
  ?k=="U"{
    v=e_e(e[2])
    ?e[1]=="-"{^0-v}
    ?e[1]=="!"{^!v}
    ^N
  }
  ?k=="X"{^e_e(e[1])[e_e(e[2])]}
  ?k=="F"{^e_e(e[1])[e[2]]}
  ?k=="C"{
    f=e_e(e[1])
    args=[]
    *a:e[2]{#push(args,e_e(a))}
    ^call_fn(f,args)
  }
  ?k=="T"{
    args=[]
    *a:e[2]{#push(args,e_e(a))}
    ^exec_tool(e[1],args)
  }
  ^N
}

' --- user function call ---
:call_fn(f,args){
  ?f[0]!="fn"{>"eval: not a function" ^N}
  env_enter_fn()
  i=0
  *p:f[1]{
    v=N
    ?i<#len(args){v=args[i]}
    env_set_local(p,v)
    i=i+1
  }
  r=exec_blk(f[2])
  env_leave_fn()
  ?r[0]=="R"{^r[1]}
  ^N
}

' --- native-tool forwarder. Limited but covers common ops. ---
:exec_tool(name,args){
  ?name=="p"{
    out=""
    i=0
    *a:args{
      ?i>0{out=out+" "}
      out=out+#str(a)
      i=i+1
    }
    >out
    ^N
  }
  ?name=="len"{^#len(args[0])}
  ?name=="str"{^#str(args[0])}
  ?name=="num"{^#num(args[0])}
  ?name=="has"{^#has(args[0],args[1])}
  ?name=="push"{
    L=args[0]
    i=1
    *?i<#len(args){#push(L,args[i]) i=i+1}
    ^L
  }
  ?name=="pop"{^#pop(args[0])}
  ?name=="split"{^#split(args[0],args[1])}
  ?name=="join"{^#join(args[0],args[1])}
  ?name=="up"{^#up(args[0])}
  ?name=="lo"{^#lo(args[0])}
  ?name=="trim"{^#trim(args[0])}
  ?name=="tk"{^#tk(args[0])}
  ?name=="j"{^#j(args[0])}
  ?name=="uj"{^#uj(args[0])}
  ?name=="keys"{^#keys(args[0])}
  ?name=="vals"{^#vals(args[0])}
  ?name=="rng"{
    ?#len(args)==1{^#rng(args[0])}
    ^#rng(args[0],args[1])
  }
  >"eval: unknown tool #"+name
  ^N
}

' --- statement exec, returns Flow ---
:exec(s){
  k=s[0]
  ?k=="="{env_set(s[1],e_e(s[2])) ^["N"]}
  ?k=="["{
    a=e_e(s[1])
    a[e_e(s[2])]=e_e(s[3])
    ^["N"]
  }
  ?k==">"{>e_e(s[1]) ^["N"]}
  ?k=="^"{^["R",e_e(s[1])]}
  ?k=="?"{
    ?e_e(s[1]){^exec_blk(s[2])}
    ?s[3]!=N{^exec_blk(s[3])}
    ^["N"]
  }
  ?k=="*"{
    n=e_e(s[1])
    env_push()
    i=0
    *?i<n{
      env_set_local("i",i)
      r=exec_blk(s[2])
      ?r[0]=="R"{env_pop() ^r}
      ?r[0]=="K"{brk}
      i=i+1
    }
    env_pop()
    ^["N"]
  }
  ?k=="r"{
    it=e_e(s[2])
    env_push()
    *x:it{
      env_set_local(s[1],x)
      r=exec_blk(s[3])
      ?r[0]=="R"{env_pop() ^r}
      ?r[0]=="K"{brk}
    }
    env_pop()
    ^["N"]
  }
  ?k=="w"{
    *?T{
      ?!e_e(s[1]){brk}
      r=exec_blk(s[2])
      ?r[0]=="R"{^r}
      ?r[0]=="K"{brk}
    }
    ^["N"]
  }
  ?k==":"{env_set(s[1],["fn",s[2],s[3]]) ^["N"]}
  ?k=="K"{^["K"]}
  ?k=="c"{^["C"]}
  ?k=="E"{e_e(s[1]) ^["N"]}
  ^["N"]
}

:exec_blk(stmts){
  *st:stmts{
    r=exec(st)
    ?r[0]!="N"{^r}
  }
  ^["N"]
}

:eval_ast(ast){
  r=exec_blk(ast)
  ?r[0]=="R"{^r[1]}
  ^N
}
