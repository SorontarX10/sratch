' emit_demo.sra — full source -> AST -> source pipeline.
' Uses #inc to assemble the compiler from its modules.

#inc("compiler/lex.sra")
#inc("compiler/parse.sra")
#inc("compiler/emit.sra")

' Parser state must live at top level (function-barrier scoping).
toks=[]
pi=0

src=":sq(n){^n*n}
?sq(3)>5{>\"big\"}:{>\"small\"}"

>"=== source 1 ==="
>src
>""
ast1=parse(lex(src))
>"=== AST 1 ==="
>#j(ast1)
>""
src2=emit(ast1)
>"=== emitted source ==="
>src2
ast2=parse(lex(src2))
>"=== AST 2 ==="
>#j(ast2)
>""
?#j(ast1)==#j(ast2){
  >"=== ROUND-TRIP OK ==="
}:{
  >"=== ROUND-TRIP DIFF ==="
}
