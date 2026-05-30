' emit_c.sra — Sratch -> C transpiler.
' Dynamic values are a tagged union SrVal {nil,num(double),str,list}.
' Lists are heap SrList* (reference semantics for #push). Memory is
' leaked (arena-free, fine for short programs). Functions are named
' static C functions (no first-class funcs / dicts / @ / ~).
'
' Subset: numbers, strings, lists, arithmetic, comparison, control
' flow, recursion, tools p/len/str/num/push/join/split/rng/has.

:_c_runtime(){
  ^"#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef enum { T_NIL, T_NUM, T_STR, T_LST } Tag;
typedef struct SrVal SrVal;
typedef struct { SrVal* items; int len; int cap; } SrList;
struct SrVal { Tag t; double n; char* s; SrList* l; };
static SrVal srNil(){ SrVal v; v.t=T_NIL; v.n=0; v.s=0; v.l=0; return v; }
static SrVal srNum(double n){ SrVal v=srNil(); v.t=T_NUM; v.n=n; return v; }
static SrVal srStr(const char* s){ SrVal v=srNil(); v.t=T_STR; v.s=strdup(s); return v; }
static SrVal srLstNew(){ SrVal v=srNil(); v.t=T_LST; v.l=(SrList*)calloc(1,sizeof(SrList)); return v; }
static void srPush1(SrVal lst, SrVal x){ SrList* L=lst.l; if(L->len>=L->cap){ L->cap=L->cap?L->cap*2:4; L->items=(SrVal*)realloc(L->items,L->cap*sizeof(SrVal)); } L->items[L->len++]=x; }
static char* srStrOf(SrVal v){
  char* buf=(char*)malloc(64);
  if(v.t==T_NIL){ strcpy(buf,\"n\"); return buf; }
  if(v.t==T_NUM){ if(v.n==(long long)v.n) sprintf(buf,\"%lld\",(long long)v.n); else sprintf(buf,\"%g\",v.n); return buf; }
  if(v.t==T_STR){ free(buf); return strdup(v.s); }
  if(v.t==T_LST){ char* o=(char*)malloc(2); strcpy(o,\"[\"); int sz=2; for(int i=0;i<v.l->len;i++){ char* e=srStrOf(v.l->items[i]); sz+=strlen(e)+1; o=(char*)realloc(o,sz); if(i) strcat(o,\",\"); strcat(o,e); free(e); } o=(char*)realloc(o,sz+1); strcat(o,\"]\"); return o; }
  strcpy(buf,\"?\"); return buf;
}
static double srNumOf(SrVal v){ if(v.t==T_NUM) return v.n; if(v.t==T_STR) return atof(v.s); return 0; }
static int srTruthy(SrVal v){ if(v.t==T_NIL) return 0; if(v.t==T_NUM) return v.n!=0; if(v.t==T_STR) return v.s[0]!=0; if(v.t==T_LST) return v.l->len>0; return 1; }
static SrVal srAdd(SrVal a, SrVal b){ if(a.t==T_STR||b.t==T_STR){ char* x=srStrOf(a); char* y=srStrOf(b); char* o=(char*)malloc(strlen(x)+strlen(y)+1); strcpy(o,x); strcat(o,y); SrVal r=srStr(o); free(x); free(y); free(o); return r; } if(a.t==T_LST&&b.t==T_LST){ SrVal r=srLstNew(); for(int i=0;i<a.l->len;i++) srPush1(r,a.l->items[i]); for(int i=0;i<b.l->len;i++) srPush1(r,b.l->items[i]); return r; } return srNum(srNumOf(a)+srNumOf(b)); }
static SrVal srMul(SrVal a, SrVal b){ if(a.t==T_STR){ int n=(int)srNumOf(b); if(n<0)n=0; int la=strlen(a.s); char* o=(char*)malloc(la*n+1); o[0]=0; for(int i=0;i<n;i++) strcat(o,a.s); SrVal r=srStr(o); free(o); return r; } return srNum(srNumOf(a)*srNumOf(b)); }
static int srEq(SrVal a, SrVal b){ char* x=srStrOf(a); char* y=srStrOf(b); int r=strcmp(x,y)==0; free(x); free(y); return r; }
static SrVal srIdx(SrVal v, SrVal i){ if(v.t==T_LST){ int n=v.l->len; int k=(int)srNumOf(i); if(k<0)k+=n; if(k<0||k>=n) return srNil(); return v.l->items[k]; } if(v.t==T_STR){ int n=strlen(v.s); int k=(int)srNumOf(i); if(k<0)k+=n; if(k<0||k>=n) return srNil(); char b[2]={v.s[k],0}; return srStr(b); } return srNil(); }
static void srP1(SrVal v){ char* s=srStrOf(v); fputs(s,stdout); free(s); }
static SrVal srArg(SrVal* a, int n, int i){ if(i<n) return a[i]; return srNil(); }
static SrVal srLen(SrVal v){ if(v.t==T_LST) return srNum(v.l->len); if(v.t==T_STR) return srNum(strlen(v.s)); return srNum(0); }
static SrVal srJoin(SrVal lst, SrVal sep){ char* sp=srStrOf(sep); char* o=(char*)malloc(1); o[0]=0; int sz=1; for(int i=0;i<lst.l->len;i++){ char* e=srStrOf(lst.l->items[i]); sz+=strlen(e)+strlen(sp); o=(char*)realloc(o,sz); if(i) strcat(o,sp); strcat(o,e); free(e); } SrVal r=srStr(o); free(o); free(sp); return r; }
static SrVal srRng(double lo, double hi){ SrVal r=srLstNew(); for(int i=(int)lo;i<(int)hi;i++) srPush1(r,srNum(i)); return r; }
"
}

_CESC={"\"":"\\\"","\\":"\\\\","\n":"\\n","\t":"\\t","\r":"\\r"}

:_c_esc(s){
  r=""
  *c:s{?#has(_CESC,c){r=r+_CESC[c]}:{r=r+c}}
  ^r
}
:_c_ind(d){
  r=""
  *d{r=r+"  "}
  ^r
}

:_c_top(ast){
  vs=[]
  fs=[]
  *s:ast{
    k=s[0]
    ?k=="="{?!#has(vs,s[1]){#push(vs,s[1])}}
    ?k==":"{?!#has(fs,s[1]){#push(fs,s[1])}}
  }
  ^[vs,fs]
}

:_c_e(e){
  k=e[0]
  ?k=="n"{^"srNum("+#str(e[1])+")"}
  ?k=="s"{^"srStr(\""+_c_esc(e[1])+"\")"}
  ?k=="i"{
    nm=e[1]
    ?nm=="T"{^"srNum(1)"}
    ?nm=="F"{^"srNum(0)"}
    ?nm=="N"{^"srNil()"}
    ^nm
  }
  ?k=="L"{
    ' build a list via a statement-expression block
    parts="srLstNew()"
    n=#len(e[1])
    ?n==0{^"srLstNew()"}
    ' use a helper-call chain: srPushR adds and returns the list
    cur="srLstNew()"
    *x:e[1]{cur="srPushR("+cur+","+_c_e(x)+")"}
    ^cur
  }
  ?k=="B"{^_c_bin(e[1],e[2],e[3])}
  ?k=="U"{
    ?e[1]=="!"{^"srNum(!srTruthy("+_c_e(e[2])+"))"}
    ^"srNum(-srNumOf("+_c_e(e[2])+"))"
  }
  ?k=="X"{^"srIdx("+_c_e(e[1])+","+_c_e(e[2])+")"}
  ?k=="C"{
    P=[]
    *a:e[2]{#push(P,_c_e(a))}
    nm=e[1][1]
    cs="" ?#len(P)>0{cs=#join(P,",")}
    ^nm+"((SrVal[]){"+cs+"},"+#str(#len(P))+")"
  }
  ?k=="T"{^_c_tool(e[1],e[2])}
  ^"srNil()"
}

:_c_tool(name,args){
  P=[]
  *a:args{#push(P,_c_e(a))}
  a0="" ?#len(P)>0{a0=P[0]}
  a1="" ?#len(P)>1{a1=P[1]}
  ?name=="p"{^"srP("+#str(#len(P))+",(SrVal[]){"+#join(P,",")+"})"}
  ?name=="len"{^"srLen("+a0+")"}
  ?name=="str"{^"srStr2("+a0+")"}
  ?name=="num"{^"srNum(srNumOf("+a0+"))"}
  ?name=="push"{^"srPushR("+a0+","+a1+")"}
  ?name=="join"{^"srJoin("+a0+","+a1+")"}
  ?name=="rng"{?#len(P)==1{^"srRng(0,srNumOf("+a0+"))"} ^"srRng(srNumOf("+a0+"),srNumOf("+a1+"))"}
  ?name=="has"{^"srNum(srHas("+a0+","+a1+"))"}
  ^"srNil()"
}

:_c_bin(op,le,re){
  l=_c_e(le)
  r=_c_e(re)
  ?op=="+"{^"srAdd("+l+","+r+")"}
  ?op=="*"{^"srMul("+l+","+r+")"}
  ?op=="=="{^"srNum(srEq("+l+","+r+"))"}
  ?op=="!="{^"srNum(!srEq("+l+","+r+"))"}
  ?op=="-"{^"srNum(srNumOf("+l+")-srNumOf("+r+"))"}
  ?op=="/"{^"srNum(srNumOf("+l+")/srNumOf("+r+"))"}
  ?op=="%"{^"srNum((long long)srNumOf("+l+")%(long long)srNumOf("+r+"))"}
  ?op=="<"{^"srNum(srNumOf("+l+")<srNumOf("+r+"))"}
  ?op==">"{^"srNum(srNumOf("+l+")>srNumOf("+r+"))"}
  ?op=="<="{^"srNum(srNumOf("+l+")<=srNumOf("+r+"))"}
  ?op==">="{^"srNum(srNumOf("+l+")>=srNumOf("+r+"))"}
  ?op=="&"{^"(srTruthy("+l+")?("+r+"):("+l+"))"}
  ?op=="|"{^"(srTruthy("+l+")?("+l+"):("+r+"))"}
  ^"srNil()"
}

:_c_s(s,d){
  k=s[0]
  i=_c_ind(d)
  ?k=="="{^i+s[1]+" = "+_c_e(s[2])+";"}
  ?k==">"{^i+"{ srP1("+_c_e(s[1])+"); printf(\"\\n\"); }"}
  ?k=="^"{^i+"return "+_c_e(s[1])+";"}
  ?k=="?"{
    r=i+"if (srTruthy("+_c_e(s[1])+")) {\n"+_c_blk(s[2],d+1)+i+"}"
    ?s[3]!=N{r=r+" else {\n"+_c_blk(s[3],d+1)+i+"}"}
    ^r
  }
  ?k=="*"{^i+"{ int _N=(int)srNumOf("+_c_e(s[1])+"); for(int _k=0;_k<_N;_k++){ SrVal i=srNum(_k); (void)i;\n"+_c_blk(s[2],d+1)+i+"} }"}
  ?k=="r"{^i+"{ SrVal _it="+_c_e(s[2])+"; SrVal _L=srIterList(_it); for(int _k=0;_k<_L.l->len;_k++){ SrVal "+s[1]+"=_L.l->items[_k];\n"+_c_blk(s[3],d+1)+i+"} }"}
  ?k=="w"{^i+"while (srTruthy("+_c_e(s[1])+")) {\n"+_c_blk(s[2],d+1)+i+"}"}
  ?k=="K"{^i+"break;"}
  ?k=="c"{^i+"continue;"}
  ?k=="E"{^i+"(void)("+_c_e(s[1])+");"}
  ^i+"/* unknown "+k+" */"
}

:_c_blk(stmts,d){
  out=""
  *st:stmts{out=out+_c_s(st,d)+"\n"}
  ^out
}

:_c_def(s){
  nm=s[1]
  bind=""
  j=0
  *p:s[2]{
    bind=bind+"  SrVal "+p+"=srArg(_a,_n,"+#str(j)+"); (void)"+p+";\n"
    j=j+1
  }
  ^"SrVal "+nm+"(SrVal* _a, int _n){\n"+bind+_c_blk(s[3],1)+"  return srNil();\n}"
}

:c_emit(ast){
  tf=_c_top(ast)
  vs=tf[0]
  fs=tf[1]
  out=_c_runtime()
  ' extra runtime helpers needing forward types
  out=out+"static SrVal srPushR(SrVal l, SrVal x){ srPush1(l,x); return l; }\n"
  out=out+"static SrVal srStr2(SrVal v){ char* s=srStrOf(v); SrVal r=srStr(s); free(s); return r; }\n"
  out=out+"static void srP(int n, SrVal* a){ for(int i=0;i<n;i++){ if(i) fputs(\" \",stdout); srP1(a[i]); } fputs(\"\\n\",stdout); }\n"
  out=out+"static SrVal srIterList(SrVal v){ if(v.t==T_LST) return v; if(v.t==T_NUM) return srRng(0,v.n); SrVal r=srLstNew(); if(v.t==T_STR){ for(int i=0;v.s[i];i++){ char b[2]={v.s[i],0}; srPush1(r,srStr(b)); } } return r; }\n"
  out=out+"static int srHas(SrVal c, SrVal x){ if(c.t==T_LST){ for(int i=0;i<c.l->len;i++) if(srEq(c.l->items[i],x)) return 1; return 0; } if(c.t==T_STR){ char* s=srStrOf(x); int r=strstr(c.s,s)!=0; free(s); return r; } return 0; }\n"
  ' forward declarations + globals
  *f:fs{out=out+"SrVal "+f+"(SrVal*,int);\n"}
  *v:vs{out=out+"SrVal "+v+";\n"}
  ' function definitions
  *s:ast{?s[0]==":"{out=out+_c_def(s)+"\n"}}
  ' main
  out=out+"int main(){\n"
  *s:ast{?s[0]!=":"{out=out+_c_s(s,1)+"\n"}}
  out=out+"  return 0;\n}\n"
  ^out
}
