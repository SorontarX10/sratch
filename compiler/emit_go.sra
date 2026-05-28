' emit_go.sra — Sratch -> Go transpiler.
' Dynamic values are interface{}. Numbers float64, lists *[]interface{}
' (pointer => reference semantics for #push), dicts map[string]interface{}.
' Functions are package-level closures func(...interface{}) interface{}.
' Program body runs in main(); names hoisted as package-level vars
' (exempt from Go's unused-variable check).
'
' Subset: scalars, lists, dicts, arithmetic, control flow, functions,
' tools p/len/str/num/push/pop/has/split/join/keys/vals/rng/j/tk.
' @/~ unsupported (panic).

:_go_runtime(){
  ^"package main
import (\"fmt\";\"os\";\"strings\";\"strconv\")
var _ = os.Args
func srStr(v interface{}) string {
  switch x := v.(type) {
  case nil: return \"n\"
  case bool: if x { return \"t\" }; return \"f\"
  case float64: if x==float64(int64(x)) { return strconv.FormatInt(int64(x),10) }; return strconv.FormatFloat(x,'g',-1,64)
  case string: return x
  case *[]interface{}: ps:=[]string{}; for _,e:=range *x { ps=append(ps,srStr(e)) }; return \"[\"+strings.Join(ps,\",\")+\"]\"
  case map[string]interface{}: ps:=[]string{}; for k,e:=range x { ps=append(ps,k+\":\"+srStr(e)) }; return \"{\"+strings.Join(ps,\",\")+\"}\"
  }
  return fmt.Sprint(v)
}
func srNum(v interface{}) float64 {
  switch x := v.(type) {
  case float64: return x
  case bool: if x { return 1 }; return 0
  case nil: return 0
  case string: f,_:=strconv.ParseFloat(x,64); return f
  }
  return 0
}
func srTruthy(v interface{}) bool {
  switch x := v.(type) {
  case nil: return false
  case bool: return x
  case float64: return x!=0
  case string: return x!=\"\"
  case *[]interface{}: return len(*x)>0
  case map[string]interface{}: return len(x)>0
  }
  return true
}
func srEq(a,b interface{}) bool { return srStr(a)==srStr(b) }
func srAdd(a,b interface{}) interface{} {
  _,sa:=a.(string); _,sb:=b.(string)
  if sa||sb { return srStr(a)+srStr(b) }
  la,oa:=a.(*[]interface{}); lb,ob:=b.(*[]interface{})
  if oa&&ob { r:=append(append([]interface{}{},(*la)...),(*lb)...); return &r }
  return srNum(a)+srNum(b)
}
func srMul(a,b interface{}) interface{} {
  if s,ok:=a.(string); ok { n:=int(srNum(b)); if n<0 { n=0 }; return strings.Repeat(s,n) }
  return srNum(a)*srNum(b)
}
func srIdx(v,i interface{}) interface{} {
  switch x := v.(type) {
  case *[]interface{}: n:=len(*x); k:=int(srNum(i)); if k<0 { k+=n }; if k<0||k>=n { return nil }; return (*x)[k]
  case string: r:=[]rune(x); n:=len(r); k:=int(srNum(i)); if k<0 { k+=n }; if k<0||k>=n { return nil }; return string(r[k])
  case map[string]interface{}: return x[srStr(i)]
  }
  return nil
}
func srAset(v,i,val interface{}) interface{} {
  switch x := v.(type) {
  case *[]interface{}: n:=len(*x); k:=int(srNum(i)); if k<0 { k+=n }; if k>=0&&k<n { (*x)[k]=val }
  case map[string]interface{}: x[srStr(i)]=val
  }
  return v
}
func srIter(v interface{}) []interface{} {
  switch x := v.(type) {
  case float64: r:=[]interface{}{}; for i:=0;i<int(x);i++ { r=append(r,float64(i)) }; return r
  case *[]interface{}: return *x
  case string: r:=[]interface{}{}; for _,c:=range x { r=append(r,string(c)) }; return r
  case map[string]interface{}: r:=[]interface{}{}; for k:=range x { r=append(r,k) }; return r
  }
  return []interface{}{}
}
func srArg(a []interface{}, i int) interface{} { if i<len(a) { return a[i] }; return nil }
func srLst(xs ...interface{}) interface{} { s:=append([]interface{}{},xs...); return &s }
func srP(a ...interface{}) { ps:=[]string{}; for _,e:=range a { ps=append(ps,srStr(e)) }; fmt.Println(strings.Join(ps,\" \")) }
func srTool(name string, a ...interface{}) interface{} {
  switch name {
  case \"p\": srP(a...); return nil
  case \"len\": switch x:=a[0].(type) { case *[]interface{}: return float64(len(*x)); case string: return float64(len([]rune(x))); case map[string]interface{}: return float64(len(x)) }; return float64(0)
  case \"str\": return srStr(a[0])
  case \"num\": return srNum(a[0])
  case \"push\": l:=a[0].(*[]interface{}); for _,x:=range a[1:] { *l=append(*l,x) }; return l
  case \"pop\": l:=a[0].(*[]interface{}); if len(*l)==0 { return nil }; v:=(*l)[len(*l)-1]; *l=(*l)[:len(*l)-1]; return v
  case \"has\": switch c:=a[0].(type) { case *[]interface{}: for _,e:=range *c { if srEq(e,a[1]) { return true } }; return false; case string: return strings.Contains(c,srStr(a[1])); case map[string]interface{}: _,ok:=c[srStr(a[1])]; return ok }; return false
  case \"split\": sep:=srStr(a[1]); var parts []string; if sep==\"\" { for _,c:=range srStr(a[0]) { parts=append(parts,string(c)) } } else { parts=strings.Split(srStr(a[0]),sep) }; r:=[]interface{}{}; for _,p:=range parts { r=append(r,p) }; return &r
  case \"join\": l:=a[0].(*[]interface{}); ps:=[]string{}; for _,e:=range *l { ps=append(ps,srStr(e)) }; return strings.Join(ps,srStr(a[1]))
  case \"up\": return strings.ToUpper(srStr(a[0]))
  case \"lo\": return strings.ToLower(srStr(a[0]))
  case \"trim\": return strings.TrimSpace(srStr(a[0]))
  case \"keys\": m:=a[0].(map[string]interface{}); r:=[]interface{}{}; for k:=range m { r=append(r,k) }; return &r
  case \"vals\": m:=a[0].(map[string]interface{}); r:=[]interface{}{}; for _,v:=range m { r=append(r,v) }; return &r
  case \"rng\": lo:=0; hi:=int(srNum(a[0])); if len(a)>1 { lo=int(srNum(a[0])); hi=int(srNum(a[1])) }; r:=[]interface{}{}; for i:=lo;i<hi;i++ { r=append(r,float64(i)) }; return &r
  case \"tk\": s:=srStr(a[0]); n:=0; i:=0; for i<len(s) { c:=s[i]; if c==' '||c=='\\n'||c=='\\t'||c=='\\r' { i++; continue }; if (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_' { st:=i; for i<len(s)&&((s[i]>='a'&&s[i]<='z')||(s[i]>='A'&&s[i]<='Z')||(s[i]>='0'&&s[i]<='9')||s[i]=='_') { i++ }; n+=((i-st)+3)/4 } else { n++; i++ } }; if n<1 { n=1 }; return float64(n)
  }
  panic(\"unknown tool \"+name)
}
"
}

_GOESC={"\"":"\\\"","\\":"\\\\","\n":"\\n","\t":"\\t","\r":"\\r"}

:_go_esc(s){
  r=""
  *c:s{?#has(_GOESC,c){r=r+_GOESC[c]}:{r=r+c}}
  ^r
}
:_go_ind(d){
  r=""
  *d{r=r+"\t"}
  ^r
}

' collect assigned + def names at module top (for package-level var/closure decls)
:_go_top(ast){
  vs=[]
  fs=[]
  *s:ast{
    k=s[0]
    ?k=="="{?!#has(vs,s[1]){#push(vs,s[1])}}
    ?k==":"{?!#has(fs,s[1]){#push(fs,s[1])}}
  }
  ^[vs,fs]
}

:_go_e(e){
  k=e[0]
  ?k=="n"{^"float64("+#str(e[1])+")"}
  ?k=="s"{^"\""+_go_esc(e[1])+"\""}
  ?k=="i"{
    nm=e[1]
    ?nm=="T"{^"true"}
    ?nm=="F"{^"false"}
    ?nm=="N"{^"nil"}
    ^nm
  }
  ?k=="L"{
    P=[]
    *x:e[1]{#push(P,_go_e(x))}
    ^"srLst("+#join(P,",")+")"
  }
  ?k=="D"{
    P=[]
    *p:e[1]{#push(P,"\""+_go_esc(p[0][1])+"\":"+_go_e(p[1]))}
    ^"map[string]interface{}{"+#join(P,",")+"}"
  }
  ?k=="B"{^_go_bin(e[1],e[2],e[3])}
  ?k=="U"{
    ?e[1]=="!"{^"(!srTruthy("+_go_e(e[2])+"))"}
    ^"(-srNum("+_go_e(e[2])+"))"
  }
  ?k=="X"{^"srIdx("+_go_e(e[1])+","+_go_e(e[2])+")"}
  ?k=="F"{^"srIdx("+_go_e(e[1])+",\""+_go_esc(e[2])+"\")"}
  ?k=="C"{
    P=[]
    *a:e[2]{#push(P,_go_e(a))}
    ^_go_e(e[1])+".(func(...interface{})interface{})("+#join(P,",")+")"
  }
  ?k=="T"{
    P=[]
    *a:e[2]{#push(P,_go_e(a))}
    cs="" ?#len(P)>0{cs=","+#join(P,",")}
    ^"srTool(\""+e[1]+"\""+cs+")"
  }
  ?k=="@"|k=="~"{^"func()interface{}{panic(\"no "+k+" in go\")}()"}
  ^"nil"
}

:_go_bin(op,le,re){
  l=_go_e(le)
  r=_go_e(re)
  ?op=="+"{^"srAdd("+l+","+r+")"}
  ?op=="*"{^"srMul("+l+","+r+")"}
  ?op=="=="{^"srEq("+l+","+r+")"}
  ?op=="!="{^"(!srEq("+l+","+r+"))"}
  ?op=="&"{^"func()interface{}{if srTruthy("+l+"){return "+r+"};return "+l+"}()"}
  ?op=="|"{^"func()interface{}{if srTruthy("+l+"){return "+l+"};return "+r+"}()"}
  ?op=="-"|op=="/"|op=="%"{
    ?op=="%"{^"float64(int64(srNum("+l+"))%int64(srNum("+r+")))"}
    ^"(srNum("+l+")"+op+"srNum("+r+"))"
  }
  ?op=="<"|op==">"|op=="<="|op==">="{^"(srNum("+l+")"+op+"srNum("+r+"))"}
  ^"nil"
}

:_go_s(s,d){
  k=s[0]
  i=_go_ind(d)
  ?k=="="{^i+s[1]+" = "+_go_e(s[2])}
  ?k=="["{^i+"srAset("+_go_e(s[1])+","+_go_e(s[2])+","+_go_e(s[3])+")"}
  ?k==">"{^i+"srP("+_go_e(s[1])+")"}
  ?k=="^"{^i+"return "+_go_e(s[1])}
  ?k=="?"{
    r=i+"if srTruthy("+_go_e(s[1])+") {\n"+_go_blk(s[2],d+1)+i+"}"
    ?s[3]!=N{r=r+" else {\n"+_go_blk(s[3],d+1)+i+"}"}
    ^r
  }
  ?k=="*"{^i+"for i:=0;i<int(srNum("+_go_e(s[1])+"));i++ {\n"+_go_ind(d+1)+"var i interface{} = float64(i); _=i\n"+_go_blk(s[2],d+1)+i+"}"}
  ?k=="r"{^i+"for _,"+s[1]+" := range srIter("+_go_e(s[2])+") {\n"+_go_ind(d+1)+"_="+s[1]+"\n"+_go_blk(s[3],d+1)+i+"}"}
  ?k=="w"{^i+"for srTruthy("+_go_e(s[1])+") {\n"+_go_blk(s[2],d+1)+i+"}"}
  ?k=="K"{^i+"break"}
  ?k=="c"{^i+"continue"}
  ?k=="E"{^i+"_ = "+_go_e(s[1])}
  ^i+"// unknown_stmt_"+k
}

:_go_blk(stmts,d){
  out=""
  *st:stmts{out=out+_go_s(st,d)+"\n"}
  ^out
}

' Function definition becomes assignment of a closure inside main().
:_go_def(s,d){
  i=_go_ind(d)
  nm=s[1]
  bind=""
  j=0
  *p:s[2]{
    bind=bind+_go_ind(d+1)+"var "+p+" interface{} = srArg(_a,"+#str(j)+"); _="+p+"\n"
    j=j+1
  }
  ^i+nm+" = func(_a ...interface{}) interface{} {\n"+bind+_go_blk(s[3],d+1)+_go_ind(d+1)+"return nil\n"+i+"}"
}

:go_emit(ast){
  tf=_go_top(ast)
  vs=tf[0]
  fs=tf[1]
  out=_go_runtime()
  ' package-level decls (exempt from unused check). Both plain vars
  ' and functions are interface{} so call sites can uniformly assert
  ' .(func(...interface{})interface{}).
  *v:vs{out=out+"var "+v+" interface{}\n"}
  *f:fs{out=out+"var "+f+" interface{}\n"}
  out=out+"func main() {\n"
  *s:ast{
    ?s[0]==":"{out=out+_go_def(s,1)+"\n"}:{out=out+_go_s(s,1)+"\n"}
  }
  out=out+"}\n"
  ^out
}
