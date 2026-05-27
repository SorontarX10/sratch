' parse.sra — Sratch parser in Sratch. Bootstrap step 2.
'
' Input : token list from lex.sra (each token is ["t",val])
' Output: AST as nested lists.
'
' AST tag legend (single-char where possible):
'   atoms       [n,v] [s,v] [i,name]
'   collections [L,items] [D,pairs]
'   exprs       [B,op,l,r] [U,op,e] [X,l,i] [F,l,k] [C,f,args]
'               [T,name,args] [@,p,m] [~,p]
'   stmts       [=,name,e]  [[,arr,i,v]  [>,e]  [^,e]
'               [?,c,th,el] [*,n,b]  [r,x,it,b]  [w,c,b]
'               [:,name,params,b]  [K]  [c]  [E,e]

' --- token-stream cursor ---
' State is declared at the module top so that helper functions
' (peek, bump, ...) can mutate it across the function-barrier scope.
' When loaded via #inc(path,"P"), these names get mangled to P_toks /
' P_pi and live as module-globals — peek/bump references rewrite to
' match. When loaded without a prefix they remain plain globals,
' overwriting any prior toks/pi the caller may have set.
toks=[]
pi=0

:peek(){?pi>=#len(toks){^["e",""]} ^toks[pi]}
:peek2(){?pi+1>=#len(toks){^["e",""]} ^toks[pi+1]}
:bump(){t=toks[pi] pi=pi+1 ^t}
:atL(typ,val){p=peek() ^p[0]==typ & p[1]==val}
:atT(typ){^peek()[0]==typ}
:eat(typ,val){?atL(typ,val){bump() ^T} ^F}
:expect(typ,val){?!eat(typ,val){>"parse error: expected "+typ+":"+val+" at "+#str(pi)+" got "+#j(peek()) ^F} ^T}
:skip_nl(){*?atL("o","\n")|atL("o",";"){bump()}}

' --- entry point ---
:parse(t){
  toks=t
  pi=0
  ^_prog()
}

:_prog(){
  _S=[]
  skip_nl()
  *?pi<#len(toks){
    #push(_S,_stmt())
    skip_nl()
  }
  ^_S
}

' --- statements ---
:_stmt(){
  ?atL("o",">"){bump() ^[">",_expr()]}
  ?atL("o","^"){bump() ^["^",_expr()]}
  ?atL("o","?"){^p_if()}
  ?atL("o","*"){^p_loop(F)}
  ?atL("o","*?"){^p_loop(T)}
  ?atL("o",":"){^p_def()}
  ?atT("i") & peek2()[0]=="o" & peek2()[1]=="="{
    n=bump()[1] bump()
    ^["=",n,_expr()]
  }
  ?atT("i") & peek()[1]=="brk"{bump() ^["K"]}
  ?atT("i") & peek()[1]=="cnt"{bump() ^["c"]}
  e=_expr()
  ?atL("o","="){
    ?e[0]=="X"{bump() v=_expr() ^["[",e[1],e[2],v]}
  }
  ^["E",e]
}

:p_if(){
  bump()
  c=_expr()
  th=p_blk()
  skip_nl()
  el=N
  ?atL("o",":") & peek2()[0]=="o" & peek2()[1]=="{"{
    bump()
    el=p_blk()
  }
  ^["?",c,th,el]
}

:p_loop(isw){
  bump()
  ?isw{c=_expr() ^["w",c,p_blk()]}
  ?atT("i") & peek2()[0]=="o" & peek2()[1]==":"{
    n=bump()[1] bump()
    it=_expr()
    ^["r",n,it,p_blk()]
  }
  n=_expr()
  ^["*",n,p_blk()]
}

:p_def(){
  bump()
  name=bump()[1]
  expect("o","(")
  params=[]
  ?!atL("o",")"){
    #push(params,bump()[1])
    *?eat("o",","){#push(params,bump()[1])}
  }
  expect("o",")")
  ^[":",name,params,p_blk()]
}

:p_blk(){
  expect("o","{")
  _S=[]
  skip_nl()
  *?!atL("o","}"){
    #push(_S,_stmt())
    skip_nl()
  }
  expect("o","}")
  ^_S
}

' --- expressions: Pratt-style precedence climb ---
:_expr(){^p_or()}

:p_or(){
  l=p_and()
  *?eat("o","|"){r=p_and() l=["B","|",l,r]}
  ^l
}

:p_and(){
  l=p_cmp()
  *?eat("o","&"){r=p_cmp() l=["B","&",l,r]}
  ^l
}

:p_cmp(){
  l=p_add()
  CO=["==","!=","<",">","<=",">=","=~"]
  ?atT("o") & #has(CO,peek()[1]){
    op=bump()[1]
    r=p_add()
    ^["B",op,l,r]
  }
  ^l
}

:p_add(){
  l=p_mul()
  *?atT("o") & (peek()[1]=="+"|peek()[1]=="-"){
    op=bump()[1] r=p_mul() l=["B",op,l,r]
  }
  ^l
}

:p_mul(){
  l=p_un()
  *?atT("o") & (peek()[1]=="*"|peek()[1]=="/"|peek()[1]=="%"){
    op=bump()[1] r=p_un() l=["B",op,l,r]
  }
  ^l
}

:p_un(){
  ?atL("o","-"){bump() ^["U","-",p_un()]}
  ?atL("o","!"){bump() ^["U","!",p_un()]}
  ^p_post()
}

:p_post(){
  e=_atom()
  *?T{
    ?atL("o","["){bump() i=_expr() expect("o","]") e=["X",e,i] cnt}
    ?atL("o","("){
      bump()
      args=[]
      ?!atL("o",")"){
        #push(args,_expr())
        *?eat("o",","){#push(args,_expr())}
      }
      expect("o",")")
      e=["C",e,args]
      cnt
    }
    ?atL("o","."){
      bump()
      n=bump()[1]
      e=["F",e,n]
      cnt
    }
    brk
  }
  ^e
}

:_atom(){
  t=bump()
  ?t[0]=="n"{^["n",#num(t[1])]}
  ?t[0]=="s"{^["s",t[1]]}
  ?t[0]=="i"{^["i",t[1]]}
  ?t[0]=="o" & t[1]=="("{e=_expr() expect("o",")") ^e}
  ?t[0]=="o" & t[1]=="["{
    items=[] skip_nl()
    ?!atL("o","]"){
      #push(items,_expr()) skip_nl()
      *?eat("o",","){skip_nl() #push(items,_expr()) skip_nl()}
    }
    expect("o","]")
    ^["L",items]
  }
  ?t[0]=="o" & t[1]=="{"{
    pairs=[] skip_nl()
    ?!atL("o","}"){
      k=_expr() expect("o",":") v=_expr()
      #push(pairs,[k,v]) skip_nl()
      *?eat("o",","){
        skip_nl() k=_expr() expect("o",":") v=_expr()
        #push(pairs,[k,v]) skip_nl()
      }
    }
    expect("o","}")
    ^["D",pairs]
  }
  ?t[0]=="o" & t[1]=="@"{
    p=p_un()
    m=N
    ?eat("o","%"){m=p_un()}
    ^["@",p,m]
  }
  ?t[0]=="o" & t[1]=="#"{
    n=bump()[1]
    args=[]
    ?eat("o","("){
      ?!atL("o",")"){
        #push(args,_expr())
        *?eat("o",","){#push(args,_expr())}
      }
      expect("o",")")
    }
    ^["T",n,args]
  }
  ?t[0]=="o" & t[1]=="~"{^["~",p_un()]}
  ^["err",t]
}
