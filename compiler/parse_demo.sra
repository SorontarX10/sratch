' parse_demo.sra — full pipeline: source -> tokens -> AST.
' Inlines lex.sra and parse.sra (no module system in Sratch yet).

' === lexer ===
DG="0123456789"
AL="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
ES={"n":"\n","t":"\t","r":"\r","\\":"\\","\"":"\"","R":"\R","D":"\D","S":"\S","G":"\G","O":"\O","E":"\E"}
M2=["==","!=","<=",">=","*?","=~"]
:dg(c){^#has(DG,c)}
:al(c){^#has(AL,c)}
:an(c){^dg(c)|al(c)}
:lex(s){
  T=[] _L=#len(s) p=0
  *?p<_L{
    c=s[p]
    ?c==" "|c=="\t"|c=="\r"{p=p+1 cnt}
    ?c=="'"{*?p<_L & s[p]!="\n"{p=p+1} cnt}
    ?c=="\n"{#push(T,["o","\n"]) p=p+1 cnt}
    ?c=="\""{
      p=p+1 b=""
      *?p<_L & s[p]!="\""{
        ch=s[p]
        ?ch=="\\"{
          p=p+1 e=s[p]
          ?#has(ES,e){b=b+ES[e]}:{b=b+e}
          p=p+1
        }:{b=b+ch p=p+1}
      }
      p=p+1 #push(T,["s",b]) cnt
    }
    ?dg(c){b="" *?p<_L & (dg(s[p])|s[p]=="."){b=b+s[p] p=p+1} #push(T,["n",b]) cnt}
    ?al(c){b="" *?p<_L & an(s[p]){b=b+s[p] p=p+1} #push(T,["i",b]) cnt}
    ?p+1<_L{d=c+s[p+1] ?#has(M2,d){#push(T,["o",d]) p=p+2 cnt}}
    #push(T,["o",c]) p=p+1
  }
  ^T
}

' === parser ===
:peek(){?pi>=#len(toks){^["e",""]} ^toks[pi]}
:peek2(){?pi+1>=#len(toks){^["e",""]} ^toks[pi+1]}
:bump(){t=toks[pi] pi=pi+1 ^t}
:atL(typ,val){p=peek() ^p[0]==typ & p[1]==val}
:atT(typ){^peek()[0]==typ}
:eat(typ,val){?atL(typ,val){bump() ^T} ^F}
:expect(typ,val){?!eat(typ,val){>"parse error: expected "+typ+":"+val+" at "+#str(pi)+" got "+#j(peek()) ^F} ^T}
:skip_nl(){*?atL("o","\n")|atL("o",";"){bump()}}

:parse(t){toks=t pi=0 ^_prog()}

:_prog(){_S=[] skip_nl() *?pi<#len(toks){#push(_S,_stmt()) skip_nl()} ^_S}

:_stmt(){
  ?atL("o",">"){bump() ^[">",_expr()]}
  ?atL("o","^"){bump() ^["^",_expr()]}
  ?atL("o","?"){^p_if()}
  ?atL("o","*"){^p_loop(F)}
  ?atL("o","*?"){^p_loop(T)}
  ?atL("o",":"){^p_def()}
  ?atT("i") & peek2()[0]=="o" & peek2()[1]=="="{n=bump()[1] bump() ^["=",n,_expr()]}
  ?atT("i") & peek()[1]=="brk"{bump() ^["K"]}
  ?atT("i") & peek()[1]=="cnt"{bump() ^["c"]}
  e=_expr()
  ?atL("o","="){?e[0]=="X"{bump() v=_expr() ^["[",e[1],e[2],v]}}
  ^["E",e]
}

:p_if(){bump() c=_expr() th=p_blk() skip_nl() el=N
  ?atL("o",":") & peek2()[0]=="o" & peek2()[1]=="{"{bump() el=p_blk()}
  ^["?",c,th,el]
}
:p_loop(isw){bump()
  ?isw{c=_expr() ^["w",c,p_blk()]}
  ?atT("i") & peek2()[0]=="o" & peek2()[1]==":"{
    n=bump()[1] bump() it=_expr() ^["r",n,it,p_blk()]
  }
  n=_expr() ^["*",n,p_blk()]
}
:p_def(){bump() name=bump()[1] expect("o","(")
  params=[]
  ?!atL("o",")"){
    #push(params,bump()[1])
    *?eat("o",","){#push(params,bump()[1])}
  }
  expect("o",")")
  ^[":",name,params,p_blk()]
}
:p_blk(){expect("o","{") _S=[] skip_nl()
  *?!atL("o","}"){#push(_S,_stmt()) skip_nl()}
  expect("o","}") ^_S
}

:_expr(){^p_or()}
:p_or(){l=p_and() *?eat("o","|"){r=p_and() l=["B","|",l,r]} ^l}
:p_and(){l=p_cmp() *?eat("o","&"){r=p_cmp() l=["B","&",l,r]} ^l}
:p_cmp(){l=p_add() CO=["==","!=","<",">","<=",">=","=~"]
  ?atT("o") & #has(CO,peek()[1]){op=bump()[1] r=p_add() ^["B",op,l,r]}
  ^l
}
:p_add(){l=p_mul() *?atT("o") & (peek()[1]=="+"|peek()[1]=="-"){op=bump()[1] r=p_mul() l=["B",op,l,r]} ^l}
:p_mul(){l=p_un() *?atT("o") & (peek()[1]=="*"|peek()[1]=="/"|peek()[1]=="%"){op=bump()[1] r=p_un() l=["B",op,l,r]} ^l}
:p_un(){
  ?atL("o","-"){bump() ^["U","-",p_un()]}
  ?atL("o","!"){bump() ^["U","!",p_un()]}
  ^p_post()
}
:p_post(){e=_atom()
  *?T{
    ?atL("o","["){bump() i=_expr() expect("o","]") e=["X",e,i] cnt}
    ?atL("o","("){
      bump() args=[]
      ?!atL("o",")"){
        #push(args,_expr())
        *?eat("o",","){#push(args,_expr())}
      }
      expect("o",")") e=["C",e,args] cnt
    }
    ?atL("o","."){bump() n=bump()[1] e=["F",e,n] cnt}
    brk
  }
  ^e
}
:_atom(){t=bump()
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
    expect("o","]") ^["L",items]
  }
  ?t[0]=="o" & t[1]=="{"{
    pairs=[] skip_nl()
    ?!atL("o","}"){
      k=_expr() expect("o",":") v=_expr() #push(pairs,[k,v]) skip_nl()
      *?eat("o",","){skip_nl() k=_expr() expect("o",":") v=_expr() #push(pairs,[k,v]) skip_nl()}
    }
    expect("o","}") ^["D",pairs]
  }
  ?t[0]=="o" & t[1]=="@"{p=p_un() m=N ?eat("o","%"){m=p_un()} ^["@",p,m]}
  ?t[0]=="o" & t[1]=="#"{n=bump()[1] args=[]
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

' === driver ===
' Parser state lives at top level so it survives across helper calls
' under the new function-barrier semantics.
toks=[]
pi=0

src=":sq(n){^n*n}
?sq(3)>5{>\"big\"}:{>\"small\"}"

>"--- source ---"
>src
>""
>"--- tokens ---"
tks=lex(src)
*t:tks{
  v=t[1]
  ?v=="\n"{v="\\n"}
  >"["+t[0]+"] "+v
}
>""
>"--- AST (JSON) ---"
ast=parse(tks)
>#j(ast)
