' emit_py_demo.sra — Sratch source -> Python source -> run.
' Validates the transpiler by executing the generated code and
' comparing output to the native Sratch interpreter.

#inc("compiler/lex.sra")
#inc("compiler/parse.sra")
#inc("compiler/emit_py.sra")

toks=[]
pi=0

src=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)
*i:#rng(3){>i*i}"

>"=== Sratch source ==="
>src
>""
ast=parse(lex(src))
py=py_emit(ast)
>"=== generated Python ==="
>py
>""

' write to tmp, run with python3, capture output
#wr("/tmp/sratch_out.py",py)
>"=== Python output ==="
>#sh("python3 /tmp/sratch_out.py")
