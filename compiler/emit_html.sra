' emit_html.sra — wrap JS-transpiled program in a self-contained HTML page.
'
' Output: a single .html file that runs the program in the browser
' with console.log redirected into a <pre>. Pairs with emit_js.sra:
'   js  = J.emit_js(ast)
'   doc = H.wrap_html(js)
'   #wr("out.html", doc)
' Open out.html — program output renders in the page.

:_html_head(){
  ^"<!DOCTYPE html>
<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Sratch</title>
<style>
body{font-family:ui-monospace,Menlo,Consolas,monospace;background:#0c0c10;color:#e6e6e6;padding:1.5em;margin:0;line-height:1.4}
h1{font-size:1em;margin:0 0 .75em;color:#888;letter-spacing:.1em;text-transform:uppercase}
pre{background:#16161c;padding:1em;border-radius:6px;border:1px solid #2a2a33;overflow:auto;margin:0;white-space:pre-wrap;word-break:break-word}
.err{color:#ff6b6b}
</style>
</head><body><h1>sratch &middot; output</h1><pre id=\"_o\"></pre><script>
const _o=document.getElementById('_o');
const _fmt=v=>typeof v==='string'?v:(v===null||v===undefined?String(v):JSON.stringify(v));
const console={log:(...a)=>{_o.textContent+=a.map(_fmt).join(' ')+'\\n';},error:(...a)=>{const s=document.createElement('span');s.className='err';s.textContent='ERR: '+a.map(String).join(' ')+'\\n';_o.appendChild(s);}};
window.addEventListener('error',e=>{console.error(e.message);});
"
}

:_html_tail(){
  ^"
</script></body></html>
"
}

:wrap_html(js){
  ^_html_head()+js+_html_tail()
}
