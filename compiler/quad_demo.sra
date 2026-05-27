' quad_demo.sra — one Sratch source, four targets.
' Compile to JS / Python / Bash / HTML, run the three runnables,
' confirm identical output. Show token economy across all four.

#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
#inc("compiler/emit_py.sra","Y")
#inc("compiler/emit_sh.sra","Sh")
#inc("compiler/emit_html.sra","H")

src=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)
*x:[1,2,3,4]{>x*x}
M=[10,20,30]
>#join(M,\",\")"

ast=P.parse(L.lex(src))

>"=== Sratch source ==="
>src
>""

js=J.emit_js(ast)
py=Y.py_emit(ast)
sh=Sh.emit_sh(ast)
html=H.wrap_html(js)

#wr("/tmp/q.js",js)
#wr("/tmp/q.py",py)
#wr("/tmp/q.sh",sh)
#wr("/tmp/q.html",html)

>"=== JS (node) ==="
>#sh("node /tmp/q.js")
>""
>"=== Python (python3) ==="
>#sh("python3 /tmp/q.py")
>""
>"=== Bash (bash) ==="
>#sh("bash /tmp/q.sh")
>""
>"=== HTML wrap (size, open /tmp/q.html in browser) ==="
>#str(#len(html))+" chars, "+#str(#tk(html))+" tokens"
>""

>"=== token economy ==="
>"sratch:  "+#str(#tk(src))+" tok / "+#str(#len(src))+" chars"
>"js:     "+#str(#tk(js))+" tok / "+#str(#len(js))+" chars"
>"python: "+#str(#tk(py))+" tok / "+#str(#len(py))+" chars"
>"bash:   "+#str(#tk(sh))+" tok / "+#str(#len(sh))+" chars"
>"html:   "+#str(#tk(html))+" tok / "+#str(#len(html))+" chars"
