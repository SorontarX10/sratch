' polyglot_demo.sra — one Sratch program, two targets.
' Compiles the same source to JS and Python, runs both,
' confirms they produce identical output.

#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
#inc("compiler/emit_py.sra","Y")

src=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)
*x:[1,2,3,4]{>x*x}
L=[10,20,30]
#push(L,40)
>#join(L,\",\")"

ast=P.parse(L.lex(src))

>"=== Sratch source ==="
>src
>""

js=J.emit_js(ast)
#wr("/tmp/poly.js",js)
>"=== JS output ==="
>#sh("node /tmp/poly.js")
>""

py=Y.py_emit(ast)
#wr("/tmp/poly.py",py)
>"=== Python output ==="
>#sh("python3 /tmp/poly.py")
>""

>"=== token economy ==="
>"Sratch source: "+#str(#tk(src))+" tokens, "+#str(#len(src))+" chars"
>"JS output    : "+#str(#tk(js))+" tokens, "+#str(#len(js))+" chars"
>"Py output    : "+#str(#tk(py))+" tokens, "+#str(#len(py))+" chars"
