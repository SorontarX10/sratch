' emit_js.sra — Sratch -> JavaScript transpiler.
'
' Same AST traversal as emit.sra, different target. Output is a
' self-contained .js file: an inline `sr` runtime that bridges
' Sratch semantics (truthiness, +/* on strings/lists, negative
' indexing, iter() over numbers/strings/dicts, glob match) followed
' by the transpiled program. Run with `node out.js`.
'
' Limitations: no @ (LLM) or ~ (agent) emit yet. =~ supports
' single-`*` glob. Function-barrier scoping is approximated by
' JS function scopes; module-globals must be top-level assigns.

:_js_runtime(){
  ^"const sr={
print(...a){console.log(a.map(x=>sr.str(x)).join(' '));},
str(v){if(v===null||v===undefined)return 'n';if(v===true)return 't';if(v===false)return 'f';if(Array.isArray(v))return '['+v.map(sr.str).join(',')+']';if(typeof v==='object')return '{'+Object.entries(v).map(([k,x])=>k+':'+sr.str(x)).join(',')+'}';if(typeof v==='number')return Number.isInteger(v)?String(v):String(v);return String(v);},
num(v){if(typeof v==='number')return v;if(v===true)return 1;if(v===false||v===null||v===undefined)return 0;const n=parseFloat(v);return isNaN(n)?0:n;},
truthy(v){if(v===null||v===undefined||v===false||v===0||v==='')return false;if(Array.isArray(v))return v.length>0;if(typeof v==='object')return Object.keys(v).length>0;return true;},
eq(a,b){if(a===b)return true;if(Array.isArray(a)&&Array.isArray(b)){if(a.length!==b.length)return false;return a.every((x,i)=>sr.eq(x,b[i]));}return false;},
add(a,b){if(typeof a==='string'||typeof b==='string')return sr.str(a)+sr.str(b);if(Array.isArray(a)&&Array.isArray(b))return [...a,...b];return sr.num(a)+sr.num(b);},
mul(a,b){if(typeof a==='string')return a.repeat(Math.max(0,sr.num(b)|0));return sr.num(a)*sr.num(b);},
idx(v,i){if(Array.isArray(v)||typeof v==='string'){const n=v.length,k=i<0?n+i:i;if(k<0||k>=n)return null;return v[k];}if(v&&typeof v==='object')return v[i]===undefined?null:v[i];return null;},
aset(v,i,x){if(Array.isArray(v)){const n=v.length,k=i<0?n+i:i;if(k>=0&&k<n)v[k]=x;}else if(v&&typeof v==='object'){v[i]=x;}return v;},
iter(v){if(typeof v==='number'){const r=[];for(let i=0;i<v;i++)r.push(i);return r;}if(typeof v==='string')return [...v];if(Array.isArray(v))return v;if(v&&typeof v==='object')return Object.keys(v);return [];},
glob(s,p){let re='',cap=false;for(const c of String(p)){if(c==='*'){re+='([\\\\s\\\\S]*)';cap=true;}else if(c==='?'){re+='[\\\\s\\\\S]';}else{re+=c.replace(/[.*+?^${}()|[\\]\\\\]/g,'\\\\$&');}}const m=String(s).match(new RegExp(re));if(!m)return null;return cap?m[1]:m[0];},
_mi:0,
sh(cmd){return require('child_process').execSync(cmd,{shell:'/bin/bash'}).toString().replace(/\\n$/,'');},
llm(p,m){m=m||process.env.SRATCH_MODEL||'claude-haiku-4-5';const mk=process.env.SRATCH_MOCK;if(mk!==undefined){const parts=mk.split('\\n---\\n');const r=parts[sr._mi%parts.length];sr._mi++;return r;}const isO=/^(gpt-|o1|o3|o4|chatgpt|text-)/.test(m);const key=isO?process.env.OPENAI_API_KEY:process.env.ANTHROPIC_API_KEY;if(!key)return '[stub:'+m+'] '+p;const cp=require('child_process');let url,hdr,body;if(isO){url=(process.env.OPENAI_BASE_URL||'https://api.openai.com')+'/v1/chat/completions';hdr=['-H','authorization: Bearer '+key];body=JSON.stringify({model:m,messages:[{role:'user',content:p}]});}else{url=(process.env.ANTHROPIC_BASE_URL||'https://api.anthropic.com')+'/v1/messages';hdr=['-H','x-api-key: '+key,'-H','anthropic-version: 2023-06-01'];body=JSON.stringify({model:m,max_tokens:1024,messages:[{role:'user',content:p}]});}const args=['-sS','-X','POST',url,'-H','content-type: application/json',...hdr,'-d','@-'];const out=cp.execFileSync('curl',args,{input:body}).toString();try{const j=JSON.parse(out);return isO?j.choices[0].message.content:j.content[0].text;}catch(e){return out;}},
agent(h){const max=parseInt(process.env.SRATCH_AGENT_MAX||'20');let out='';for(let i=0;i<max;i++){const r=sr.llm(String(h));if(r.includes('DONE:'))return r;const j=r.indexOf('SH:');if(j>=0){const o=sr.sh(r.slice(j+3).trim());h=String(h)+'\\nO:'+o;}else{h=String(h)+'\\nE';}out=r;}return out;},
tools:{
p:(...a)=>sr.print(...a),
len:v=>Array.isArray(v)||typeof v==='string'?v.length:(v?Object.keys(v).length:0),
str:v=>sr.str(v),
num:v=>sr.num(v),
push:(l,...a)=>{l.push(...a);return l;},
pop:l=>l.pop()??null,
has:(c,k)=>{if(Array.isArray(c))return c.some(x=>sr.eq(x,k));if(typeof c==='string')return c.includes(k);return c&&Object.prototype.hasOwnProperty.call(c,k);},
split:(s,sep)=>sep===''?[...s]:String(s).split(sep),
join:(l,sep)=>l.map(sr.str).join(sep),
up:s=>String(s).toUpperCase(),
lo:s=>String(s).toLowerCase(),
trim:s=>String(s).trim(),
keys:d=>Object.keys(d||{}),
vals:d=>Object.values(d||{}),
rng:(a,b)=>{const lo=b===undefined?0:a,hi=b===undefined?a:b,r=[];for(let i=lo;i<hi;i++)r.push(i);return r;},
j:v=>JSON.stringify(v),
uj:s=>JSON.parse(s),
sh:cmd=>sr.sh(cmd),
get:url=>require('child_process').execFileSync('curl',['-sSL',url]).toString(),
in:()=>{try{const fs=require('fs');const b=fs.readFileSync(0,'utf8');return b.replace(/\\n$/,'');}catch(e){return '';}},
tk:s=>{let n=0,i=0;const b=String(s);while(i<b.length){const c=b[i];if(/\\s/.test(c)){i++;continue;}if(/[A-Za-z0-9_]/.test(c)){const start=i;while(i<b.length&&/[A-Za-z0-9_]/.test(b[i]))i++;n+=Math.ceil((i-start)/4);}else{n++;i++;}}return Math.max(1,n);}
}};
"
}

' --- helpers ---
:_js_in_list(l,v){*x:l{?x==v{^T}} ^F}
:_js_esc_str(s){
  r=""
  *c:s{
    ?c=="\""{r=r+"\\\""}:{?c=="\\"{r=r+"\\\\"}:{?c=="\n"{r=r+"\\n"}:{?c=="\t"{r=r+"\\t"}:{?c=="\r"{r=r+"\\r"}:{r=r+c}}}}}
  }
  ^r
}
:_js_indent(d){
  r=""
  *d{r=r+"  "}
  ^r
}

' Collect names assigned at this level (not recursing into function defs).
:_js_collect(stmts){
  vs=[]
  *s:stmts{_js_collect_one(s,vs)}
  ^vs
}
:_js_collect_one(s,vs){
  k=s[0]
  ?k=="="{?!#has(vs,s[1]){#push(vs,s[1])}}
  ?k=="?"{_js_collect_into(s[2],vs) ?s[3]!=N{_js_collect_into(s[3],vs)}}
  ?k=="*"{_js_collect_into(s[2],vs)}
  ?k=="r"{_js_collect_into(s[3],vs)}
  ?k=="w"{_js_collect_into(s[2],vs)}
  ^N
}
:_js_collect_into(stmts,vs){*s:stmts{_js_collect_one(s,vs)}}

' --- expression emitter ---
:_js_e(e){
  k=e[0]
  ?k=="n"{^#str(e[1])}
  ?k=="s"{^"\""+_js_esc_str(e[1])+"\""}
  ?k=="i"{
    nm=e[1]
    ?nm=="T"{^"true"}
    ?nm=="F"{^"false"}
    ?nm=="N"{^"null"}
    ^nm
  }
  ?k=="L"{
    parts=[]
    *x:e[1]{#push(parts,_js_e(x))}
    ^"["+#join(parts,",")+"]"
  }
  ?k=="D"{
    parts=[]
    *p:e[1]{#push(parts,"["+_js_e(p[0])+"]:"+_js_e(p[1]))}
    ^"{"+#join(parts,",")+"}"
  }
  ?k=="B"{^_js_bin(e[1],e[2],e[3])}
  ?k=="U"{
    inner=_js_e(e[2])
    ?e[1]=="-"{^"(-("+inner+"))"}
    ?e[1]=="!"{^"(!sr.truthy("+inner+"))"}
    ^inner
  }
  ?k=="X"{^"sr.idx("+_js_e(e[1])+","+_js_e(e[2])+")"}
  ?k=="F"{^"sr.idx("+_js_e(e[1])+",\""+_js_esc_str(e[2])+"\")"}
  ?k=="C"{
    parts=[]
    *a:e[2]{#push(parts,_js_e(a))}
    ^"("+_js_e(e[1])+")("+#join(parts,",")+")"
  }
  ?k=="T"{
    parts=[]
    *a:e[2]{#push(parts,_js_e(a))}
    ^"sr.tools."+e[1]+"("+#join(parts,",")+")"
  }
  ?k=="@"{
    p=_js_e(e[1])
    ?e[2]!=N{^"sr.llm("+p+","+_js_e(e[2])+")"}
    ^"sr.llm("+p+")"
  }
  ?k=="~"{^"sr.agent("+_js_e(e[1])+")"}
  ^"null"
}

:_js_bin(op,le,re){
  l=_js_e(le)
  r=_js_e(re)
  ?op=="+"{^"sr.add("+l+","+r+")"}
  ?op=="*"{^"sr.mul("+l+","+r+")"}
  ?op=="=="{^"sr.eq("+l+","+r+")"}
  ?op=="!="{^"(!sr.eq("+l+","+r+"))"}
  ?op=="=~"{^"sr.glob("+l+","+r+")"}
  ?op=="&"{^"(sr.truthy("+l+")?("+r+"):("+l+"))"}
  ?op=="|"{^"(sr.truthy("+l+")?("+l+"):("+r+"))"}
  ' arithmetic & comparison fall through with coercion
  ?op=="-"|op=="/"|op=="%"{^"(sr.num("+l+")"+op+"sr.num("+r+"))"}
  ?op=="<"|op==">"|op=="<="|op==">="{^"("+l+op+r+")"}
  ^"null"
}

' --- statement emitter (d = indent depth) ---
:_js_s(s,d){
  k=s[0]
  i=_js_indent(d)
  ?k=="="{^i+s[1]+"="+_js_e(s[2])+";"}
  ?k=="["{^i+"sr.aset("+_js_e(s[1])+","+_js_e(s[2])+","+_js_e(s[3])+");"}
  ?k==">"{^i+"sr.print("+_js_e(s[1])+");"}
  ?k=="^"{^i+"return "+_js_e(s[1])+";"}
  ?k=="?"{
    out=i+"if(sr.truthy("+_js_e(s[1])+")){\n"+_js_block(s[2],d+1)+i+"}"
    ?s[3]!=N{out=out+"else{\n"+_js_block(s[3],d+1)+i+"}"}
    ^out
  }
  ?k=="*"{
    body=_js_block(s[2],d+1)
    ^i+"for(let i=0;i<sr.num("+_js_e(s[1])+");i++){\n"+body+i+"}"
  }
  ?k=="r"{
    body=_js_block(s[3],d+1)
    ^i+"for(let "+s[1]+" of sr.iter("+_js_e(s[2])+")){\n"+body+i+"}"
  }
  ?k=="w"{
    body=_js_block(s[2],d+1)
    ^i+"while(sr.truthy("+_js_e(s[1])+")){\n"+body+i+"}"
  }
  ?k==":"{
    vars=_js_collect(s[3])
    pruned=[]
    *v:vars{?!#has(s[2],v){#push(pruned,v)}}
    head=i+"function "+s[1]+"("+#join(s[2],",")+"){"
    body=""
    ?#len(pruned)>0{body=_js_indent(d+1)+"let "+#join(pruned,",")+";\n"}
    body=body+_js_block(s[3],d+1)
    ^head+"\n"+body+i+"}"
  }
  ?k=="K"{^i+"break;"}
  ?k=="c"{^i+"continue;"}
  ?k=="E"{^i+_js_e(s[1])+";"}
  ^i+"/* unknown: "+k+" */"
}

:_js_block(stmts,d){
  out=""
  *s:stmts{out=out+_js_s(s,d)+"\n"}
  ^out
}

' --- entry points ---
:emit_js(ast){
  vars=_js_collect(ast)
  out=_js_runtime()
  ?#len(vars)>0{out=out+"let "+#join(vars,",")+";\n"}
  out=out+_js_block(ast,0)
  ^out
}

' The runtime alone (so multi-file output can share one copy).
:js_runtime(){^_js_runtime()}

' Program body without the inline runtime; assumes a global `sr`.
' Pair with: node -e "global.sr=require('./sr.js'); require('./prog.js')"
:emit_js_bare(ast){
  vars=_js_collect(ast)
  out=""
  ?#len(vars)>0{out="let "+#join(vars,",")+";\n"}
  out=out+_js_block(ast,0)
  ^out
}
