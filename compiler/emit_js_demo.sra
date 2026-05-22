' emit_js_demo.sra — Sratch -> JS round trip.
' Transpiles a program, writes out.js, runs it with `node`,
' and prints the JS output. Requires node in PATH.

#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")

src=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)
*x:[1,2,3,4]{>x*x}
L=[10,20,30]
#push(L,40)
>#join(L,\",\")
>\"DONE:hello\" =~ \"DONE:*\""

ast=P.parse(L.lex(src))
js=J.emit_js(ast)

>"=== generated JS ==="
>js
>"=== node output ==="
#wr("/tmp/sratch_out.js",js)
>#sh("node /tmp/sratch_out.js")
