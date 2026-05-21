' demo.sra — runs lex.sra on a small input and prints tokens.
' Sratch has no module system yet, so we read+exec the lexer file
' via #sh -- self-hosting is just a script in the same env.
'
' Once parse.sra lands this will become: demo = parse(lex(src)).

' --- inline lex.sra contents below ---
DG="0123456789"
AL="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
ES={"n":"\n","t":"\t","r":"\r","\\":"\\","\"":"\"","R":"\R","D":"\D","S":"\S","G":"\G","O":"\O","E":"\E"}
M2=["==","!=","<=",">=","*?","=~"]
:dg(c){^#has(DG,c)}
:al(c){^#has(AL,c)}
:an(c){^dg(c)|al(c)}
:lex(s){
  T=[] L=#len(s) p=0
  *?p<L{
    c=s[p]
    ?c==" "|c=="\t"|c=="\r"{p=p+1 cnt}
    ?c=="'"{*?p<L & s[p]!="\n"{p=p+1} cnt}
    ?c=="\n"{#push(T,["o","\n"]) p=p+1 cnt}
    ?c=="\""{
      p=p+1 b=""
      *?p<L & s[p]!="\""{
        ch=s[p]
        ?ch=="\\"{
          p=p+1 e=s[p]
          ?#has(ES,e){b=b+ES[e]}:{b=b+e}
          p=p+1
        }:{b=b+ch p=p+1}
      }
      p=p+1 #push(T,["s",b]) cnt
    }
    ?dg(c){b="" *?p<L & (dg(s[p])|s[p]=="."){b=b+s[p] p=p+1} #push(T,["n",b]) cnt}
    ?al(c){b="" *?p<L & an(s[p]){b=b+s[p] p=p+1} #push(T,["i",b]) cnt}
    ?p+1<L{d=c+s[p+1] ?#has(M2,d){#push(T,["o",d]) p=p+2 cnt}}
    #push(T,["o",c]) p=p+1
  }
  ^T
}

' --- demo ---
src="a=5+1\n?a==6{>\"hi\"}"
toks=lex(src)
>"--- source ---"
>src
>"--- tokens ---"
*t:toks{
  v=t[1]
  ?v=="\n"{v="\\n"}
  >"["+t[0]+"] "+v
}
