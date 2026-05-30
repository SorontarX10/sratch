' lex.sra — Sratch lexer in Sratch. Bootstrap step 1 toward self-hosting.
'
' Input : source string.
' Output: list of [t,v] pairs:
'   t = "n" number, "s" string, "i" ident, "o" op/punct
' Two-char ops recognized: == != <= >= *? =~
' Inline string escapes (incl. agent-vocab \R\D\S\G\O\E) are expanded
' at lex time, matching the Rust reference implementation.

DG="0123456789"
AL="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
ES={"n":"\n","t":"\t","r":"\r","\\":"\\","\"":"\"","R":"\R","D":"\D","S":"\S","G":"\G","O":"\O","E":"\E"}
M2=["==","!=","<=",">=","*?","=~"]

:dg(c){^#has(DG,c)}
:al(c){^#has(AL,c)}
:an(c){^dg(c)|al(c)}

:lex(s){
  T=[]
  _L=#len(s)
  p=0
  *?p<_L{
    c=s[p]
    ?c==" "|c=="\t"|c=="\r"{p=p+1 cnt}
    ?c=="'"{*?p<_L & s[p]!="\n"{p=p+1} cnt}
    ?c=="\n"{#push(T,["o","\n"]) p=p+1 cnt}
    ?c=="\""{
      p=p+1
      b=""
      *?p<_L & s[p]!="\""{
        ch=s[p]
        ?ch=="\\"{
          p=p+1
          e=s[p]
          ?#has(ES,e){b=b+ES[e]}:{b=b+e}
          p=p+1
        }:{b=b+ch p=p+1}
      }
      p=p+1
      #push(T,["s",b])
      cnt
    }
    ?dg(c){
      b=""
      *?p<_L & (dg(s[p])|s[p]=="."){b=b+s[p] p=p+1}
      #push(T,["n",b])
      cnt
    }
    ?al(c){
      b=""
      *?p<_L & an(s[p]){b=b+s[p] p=p+1}
      #push(T,["i",b])
      cnt
    }
    ?p+1<_L{
      d=c+s[p+1]
      ?#has(M2,d){#push(T,["o",d]) p=p+2 cnt}
    }
    #push(T,["o",c])
    p=p+1
  }
  ^T
}
