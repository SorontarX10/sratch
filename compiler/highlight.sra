' highlight.sra — Sratch source -> syntax-highlighted HTML.
' Character scanner (preserves whitespace/formatting, unlike a
' token stream). Wraps each lexical run in a <span class=...>:
'   cm comment   st string   nu number   kw keyword   op sigil/punct
' hl(src) returns the highlighted <pre> body; page(src) a full doc.

DIG="0123456789"
ALP="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
KW=["brk","cnt","T","F","N"]

:_hdg(c){^#has(DIG,c)}
:_halp(c){^#has(ALP,c)}
:_hesc(c){
  ?c=="<"{^"&lt;"}
  ?c==">"{^"&gt;"}
  ?c=="&"{^"&amp;"}
  ^c
}
:_hspan(cls,txt){^"<span class=\""+cls+"\">"+txt+"</span>"}

:hl(src){
  o=""
  p=0
  _L=#len(src)
  *?p<_L{
    c=src[p]
    ' line comment
    ?c=="'"{
      b=""
      *?p<_L & src[p]!="\n"{b=b+_hesc(src[p]) p=p+1}
      o=o+_hspan("cm",b)
      cnt
    }
    ' string literal (with escapes)
    ?c=="\""{
      b="\""
      p=p+1
      *?p<_L & src[p]!="\""{
        ?src[p]=="\\"{b=b+"\\"+_hesc(src[p+1]) p=p+2}:{b=b+_hesc(src[p]) p=p+1}
      }
      b=b+"\""
      p=p+1
      o=o+_hspan("st",b)
      cnt
    }
    ' number
    ?_hdg(c){
      b=""
      *?p<_L & (_hdg(src[p])|src[p]=="."){b=b+src[p] p=p+1}
      o=o+_hspan("nu",b)
      cnt
    }
    ' identifier / keyword
    ?_halp(c){
      b=""
      *?p<_L & (_halp(src[p])|_hdg(src[p])){b=b+src[p] p=p+1}
      ?#has(KW,b){o=o+_hspan("kw",b)}:{o=o+b}
      cnt
    }
    ' whitespace passes through verbatim
    ?c==" "|c=="\n"|c=="\t"{o=o+c p=p+1 cnt}
    ' sigils / operators / punctuation
    o=o+_hspan("op",_hesc(c))
    p=p+1
  }
  ^"<pre class=\"sratch\">"+o+"</pre>"
}

:page(src){
  ^"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>
.sratch{background:#0c0c10;color:#d8d8e0;padding:1em;border-radius:6px;font-family:ui-monospace,monospace;line-height:1.45;font-size:13px}
.sratch .cm{color:#5c6370;font-style:italic}
.sratch .st{color:#98c379}
.sratch .nu{color:#d19a66}
.sratch .kw{color:#c678dd;font-weight:bold}
.sratch .op{color:#56b6c2}
</style></head><body>"+hl(src)+"</body></html>"
}
