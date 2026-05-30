' emit_rb.sra — Sratch -> Ruby transpiler.
' Same scaffold as emit_py.sra. Functions become lambdas (callable
' with .()), so they're first-class and recursion works via closure
' capture. The whole program is wrapped in a lambda so top-level ^
' (return) is legal.
'
' Subset: scalars, lists (Array), dicts (Hash), arithmetic, control
' flow, functions/lambdas, common # tools. @/~ -> stubs that raise.

:_rb_runtime(){
  ^"def sr_str(v)
  return 'n' if v.nil?
  return 't' if v==true
  return 'f' if v==false
  return '['+v.map{|x|sr_str(x)}.join(',')+']' if v.is_a?(Array)
  return '{'+v.map{|k,x|k.to_s+':'+sr_str(x)}.join(',')+'}' if v.is_a?(Hash)
  return v.to_i.to_s if v.is_a?(Float) && v.finite? && v==v.to_i
  v.to_s
end
def sr_num(v)
  return v if v.is_a?(Numeric)
  return 1 if v==true
  return 0 if v==false || v.nil?
  (Float(v) rescue 0)
end
def sr_truthy(v)
  return false if v.nil? || v==false || v==0 || v==''
  return !v.empty? if v.respond_to?(:empty?)
  true
end
def sr_eq(a,b); a==b; end
def sr_add(a,b)
  return sr_str(a)+sr_str(b) if a.is_a?(String) || b.is_a?(String)
  return a+b if a.is_a?(Array) && b.is_a?(Array)
  sr_num(a)+sr_num(b)
end
def sr_mul(a,b)
  return a*[0,sr_num(b).to_i].max if a.is_a?(String)
  sr_num(a)*sr_num(b)
end
def sr_idx(v,i)
  if v.is_a?(Array) || v.is_a?(String)
    n=v.length; k=i<0 ? n+i : i.to_i
    return nil if k<0 || k>=n
    return v[k]
  end
  return v[i] if v.is_a?(Hash)
  nil
end
def sr_aset(v,i,x)
  if v.is_a?(Array)
    n=v.length; k=i<0 ? n+i : i.to_i
    v[k]=x if k>=0 && k<n
  elsif v.is_a?(Hash)
    v[i]=x
  end
  v
end
def sr_iter(v)
  return (0...v.to_i).to_a if v.is_a?(Numeric)
  return v.keys if v.is_a?(Hash)
  v.respond_to?(:to_a) ? v.to_a : v.chars
end
def sr_glob(s,p)
  re=''; cap=false
  p.to_s.each_char{|c| if c=='*' then re+='([\\\\s\\\\S]*)'; cap=true elsif c=='?' then re+='[\\\\s\\\\S]' else re+=Regexp.escape(c) end}
  m=s.to_s.match(Regexp.new(re))
  return nil unless m
  cap ? m[1] : m[0]
end
SR={
  'p'=>->(*a){puts a.map{|x|sr_str(x)}.join(' ')},
  'len'=>->(v){v.nil? ? 0 : v.length},
  'str'=>->(v){sr_str(v)},
  'num'=>->(v){sr_num(v)},
  'push'=>->(l,*a){a.each{|x|l.push(x)}; l},
  'pop'=>->(l){l.empty? ? nil : l.pop},
  'has'=>->(c,k){c.is_a?(Hash) ? c.key?(k) : c.include?(k)},
  'split'=>->(s,sep){sep=='' ? s.chars : s.to_s.split(sep)},
  'join'=>->(l,sep){l.map{|x|sr_str(x)}.join(sep)},
  'up'=>->(s){s.to_s.upcase},
  'lo'=>->(s){s.to_s.downcase},
  'trim'=>->(s){s.to_s.strip},
  'keys'=>->(d){d.keys},
  'vals'=>->(d){d.values},
  'rng'=>->(*a){a.length==1 ? (0...a[0].to_i).to_a : (a[0].to_i...a[1].to_i).to_a},
  'j'=>->(v){require 'json'; v.to_json},
  'uj'=>->(s){require 'json'; JSON.parse(s)},
  'sh'=>->(c){`bash -c #{c.inspect}`.chomp},
  'tk'=>->(s){ n=0;i=0;b=s.to_s; while i<b.length; c=b[i]; if c=~/\\s/ then i+=1; next; end; if c=~/[A-Za-z0-9_]/ then st=i; i+=1 while i<b.length && b[i]=~/[A-Za-z0-9_]/; n+=((i-st)+3)/4 else n+=1;i+=1 end; end; [1,n].max }
}
"
}

_RBESC={"\"":"\\\"","\\":"\\\\","\n":"\\n","\t":"\\t","\r":"\\r","#":"\\#"}

:_rb_esc(s){
  r=""
  *c:s{?#has(_RBESC,c){r=r+_RBESC[c]}:{r=r+c}}
  ^r
}
:_rb_ind(d){
  r=""
  *d{r=r+"  "}
  ^r
}
:_rb_id(n){
  ?n=="T"{^"true"}
  ?n=="F"{^"false"}
  ?n=="N"{^"nil"}
  ^n
}

:_rb_e(e){
  k=e[0]
  ?k=="n"{^#str(e[1])}
  ?k=="s"{^"\""+_rb_esc(e[1])+"\""}
  ?k=="i"{^_rb_id(e[1])}
  ?k=="L"{
    P=[]
    *x:e[1]{#push(P,_rb_e(x))}
    ^"["+#join(P,",")+"]"
  }
  ?k=="D"{
    P=[]
    *p:e[1]{#push(P,_rb_e(p[0])+"=>"+_rb_e(p[1]))}
    ^"{"+#join(P,",")+"}"
  }
  ?k=="B"{^_rb_bin(e[1],e[2],e[3])}
  ?k=="U"{
    ?e[1]=="!"{^"(!sr_truthy("+_rb_e(e[2])+"))"}
    ^"(-(" +_rb_e(e[2])+"))"
  }
  ?k=="X"{^"sr_idx("+_rb_e(e[1])+","+_rb_e(e[2])+")"}
  ?k=="F"{^"sr_idx("+_rb_e(e[1])+",\""+_rb_esc(e[2])+"\")"}
  ?k=="C"{
    P=[]
    *a:e[2]{#push(P,_rb_e(a))}
    ^"("+_rb_e(e[1])+").("+#join(P,",")+")"
  }
  ?k=="T"{
    P=[]
    *a:e[2]{#push(P,_rb_e(a))}
    ^"SR[\""+e[1]+"\"].("+#join(P,",")+")"
  }
  ?k=="lambda"{^_rb_lambda(e[1],e[2])}
  ?k=="@"{^"(raise 'no @ in rb emit')"}
  ?k=="~"{^"(raise 'no ~ in rb emit')"}
  ^"nil"
}

:_rb_lambda(params,body){
  ' inline lambda: ->(a,b){ body }
  bd=_rb_blk(body,0)
  ^"->("+#join(params,",")+"){\n"+bd+"}"
}

:_rb_bin(op,le,re){
  l=_rb_e(le)
  r=_rb_e(re)
  ?op=="+"{^"sr_add("+l+","+r+")"}
  ?op=="*"{^"sr_mul("+l+","+r+")"}
  ?op=="=="{^"sr_eq("+l+","+r+")"}
  ?op=="!="{^"(!sr_eq("+l+","+r+"))"}
  ?op=="=~"{^"sr_glob("+l+","+r+")"}
  ?op=="&"{^"(sr_truthy("+l+") ? ("+r+") : ("+l+"))"}
  ?op=="|"{^"(sr_truthy("+l+") ? ("+l+") : ("+r+"))"}
  ?op=="/"{^"(sr_num("+l+").to_f/sr_num("+r+"))"}
  ?op=="-"|op=="%"{^"(sr_num("+l+")"+op+"sr_num("+r+"))"}
  ?op=="<"|op==">"|op=="<="|op==">="{^"("+l+op+r+")"}
  ^"nil"
}

:_rb_s(s,d){
  k=s[0]
  i=_rb_ind(d)
  ?k=="="{^i+s[1]+" = "+_rb_e(s[2])}
  ?k=="["{^i+"sr_aset("+_rb_e(s[1])+","+_rb_e(s[2])+","+_rb_e(s[3])+")"}
  ?k==">"{^i+"SR[\"p\"].("+_rb_e(s[1])+")"}
  ?k=="^"{^i+"return "+_rb_e(s[1])}
  ?k=="?"{
    r=i+"if sr_truthy("+_rb_e(s[1])+")\n"+_rb_blk(s[2],d+1)
    ?s[3]!=N{r=r+i+"else\n"+_rb_blk(s[3],d+1)}
    r=r+i+"end"
    ^r
  }
  ?k=="*"{^i+"(0...sr_num("+_rb_e(s[1])+").to_i).each do |i|\n"+_rb_blk(s[2],d+1)+i+"end"}
  ?k=="r"{^i+"sr_iter("+_rb_e(s[2])+").each do |"+s[1]+"|\n"+_rb_blk(s[3],d+1)+i+"end"}
  ?k=="w"{^i+"while sr_truthy("+_rb_e(s[1])+")\n"+_rb_blk(s[2],d+1)+i+"end"}
  ?k==":"{
    ps=#join(s[2],",")
    ^i+s[1]+" = ->("+ps+"){\n"+_rb_blk(s[3],d+1)+i+"}"
  }
  ?k=="K"{^i+"break"}
  ?k=="c"{^i+"next"}
  ?k=="E"{^i+_rb_e(s[1])}
  ^i+"# unknown_stmt_"+k
}

:_rb_blk(stmts,d){
  out=""
  *st:stmts{out=out+_rb_s(st,d)+"\n"}
  ^out
}

:rb_emit(ast){
  ' wrap body in a lambda so top-level ^ (return) is legal
  ^_rb_runtime()+"\n(lambda do\n"+_rb_blk(ast,0)+"end).()\n"
}
