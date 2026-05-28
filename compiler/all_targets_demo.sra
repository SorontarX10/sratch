' all_targets_demo.sra — one Sratch program -> 7 targets.
' Transpiles to js/py/sh/rb/go/c, runs each, plus writes html.
' Confirms every runnable backend prints the same output.

#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
#inc("compiler/emit_py.sra","Y")
#inc("compiler/emit_sh.sra","S")
#inc("compiler/emit_rb.sra","R")
#inc("compiler/emit_go.sra","G")
#inc("compiler/emit_c.sra","C")
#inc("compiler/emit_html.sra","H")

src=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)
M=[1,2,3]
#push(M,4)
>#join(M,\",\")"

ast=P.parse(L.lex(src))

>"=== Sratch source ("+#str(#tk(src))+" tokens) ==="
>src
>""

#wr("/tmp/a.js",J.emit_js(ast))
#wr("/tmp/a.py",Y.py_emit(ast))
#wr("/tmp/a.sh",S.emit_sh(ast))
#wr("/tmp/a.rb",R.rb_emit(ast))
#wr("/tmp/a.go",G.go_emit(ast))
#wr("/tmp/a.c",C.c_emit(ast))
#wr("/tmp/a.html",H.wrap_html(J.emit_js(ast)))

>"js    : "+#sh("node /tmp/a.js | tr '\\n' ' '")
>"python: "+#sh("python3 /tmp/a.py | tr '\\n' ' '")
>"bash  : "+#sh("bash /tmp/a.sh | tr '\\n' ' '")
>"ruby  : "+#sh("ruby /tmp/a.rb | tr '\\n' ' '")
>"go    : "+#sh("cd /tmp && go run a.go | tr '\\n' ' '")
>"c     : "+#sh("cd /tmp && gcc -w a.c -o a_c && ./a_c | tr '\\n' ' '")
>"html  : "+#str(#len(#sh("cat /tmp/a.html")))+" bytes (open in browser)"
