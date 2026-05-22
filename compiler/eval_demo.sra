' eval_demo.sra — closes the self-hosting loop.
' Source -> lex -> parse -> eval, all in Sratch.

#inc("compiler/lex.sra")
#inc("compiler/parse.sra")
#inc("compiler/eval.sra")

' globals required by parser / evaluator
toks=[]
pi=0
ENV={"scopes":[{}],"barriers":[]}

' Test 1: simple arithmetic + function call
src1=":add(a,b){^a+b}
>add(3,4)"

>"--- test 1: add(3,4) ---"
ast1=parse(lex(src1))
eval_ast(ast1)

' Test 2: recursion (factorial)
src2=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(6)"

>"--- test 2: fact(6) ---"
ENV={"scopes":[{}],"barriers":[]}
ast2=parse(lex(src2))
eval_ast(ast2)

' Test 3: control flow (FizzBuzz, first 6)
src3="*i:6{
  n=i+1
  ?n%15==0{>\"FB\"}:{?n%3==0{>\"F\"}:{?n%5==0{>\"B\"}:{>n}}}
}"

>"--- test 3: FizzBuzz 1..6 ---"
ENV={"scopes":[{}],"barriers":[]}
ast3=parse(lex(src3))
eval_ast(ast3)

' Test 4: list mutation across while
src4="L=[]
i=0
*?i<5{#push(L,i*i) i=i+1}
>#join(L,\",\")"

>"--- test 4: squares 0..4 ---"
ENV={"scopes":[{}],"barriers":[]}
ast4=parse(lex(src4))
eval_ast(ast4)
