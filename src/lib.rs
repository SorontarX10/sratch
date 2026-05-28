pub mod ast;
pub mod builtins;
pub mod eval;
pub mod fmt;
pub mod lexer;
pub mod llm;
pub mod parser;
pub mod value;

pub use eval::Interp;
use lexer::Lexer;
use parser::Parser;
use value::Val;

pub fn run(src: &str) -> Result<Val, String> {
    let toks = Lexer::new(src).tokens()?;
    let prog = Parser::new(toks).program()?;
    Interp::new().run(&prog)
}

/// Parse `src` and re-print it in canonical normalized form.
pub fn format_src(src: &str) -> Result<String, String> {
    let toks = Lexer::new(src).tokens()?;
    let prog = Parser::new(toks).program()?;
    Ok(fmt::format(&prog))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(src: &str) -> Val {
        run(src).expect("sratch eval failed")
    }

    #[test]
    fn arith() {
        assert_eq!(ev("a=1+2*3\n^a").to_str(), "7");
    }

    #[test]
    fn star_loop_vs_multiply_disambiguation() {
        // `*` is multiply inside an expression, but a `*expr{...}` loop
        // on the same line after another statement must parse as a loop.
        // Multiply still works, including inside an if-condition.
        assert_eq!(ev(":f(d){r=\"\" *d{r=r+\"x\"} ^r}\n^f(3)").to_str(), "xxx");
        assert_eq!(ev("^2*3").to_str(), "6");
        assert_eq!(ev("?2*3>5{^\"y\"}:{^\"n\"}").to_str(), "y");
        assert_eq!(ev("a=2 *3{a=a+1}\n^a").to_str(), "5");
    }

    #[test]
    fn formatter_is_idempotent_and_runs() {
        let src = ":f(n){?n<=1{^1} ^n*f(n-1)}\n>f(5)\nm={\"a\":1,\"b\":2}\n*x:[1,2]{>x}";
        let f1 = format_src(src).unwrap();
        let f2 = format_src(&f1).unwrap();
        assert_eq!(f1, f2, "format not idempotent:\n{f1}\n---\n{f2}");
        // formatted source still evaluates to the same result
        assert_eq!(run(&f1).unwrap_or(value::Val::Nil).to_str(),
                   run(src).unwrap_or(value::Val::Nil).to_str());
    }

    #[test]
    fn repl_echoes_trailing_expr() {
        let toks = lexer::Lexer::new("a=21\na*2").tokens().unwrap();
        let prog = parser::Parser::new(toks).program().unwrap();
        let mut it = Interp::new();
        assert_eq!(it.run_repl(&prog).unwrap().to_str(), "42");
    }

    #[test]
    fn native_tool_use_dispatches_handlers() {
        // #use runs a structured tool-use loop: the model (mocked here)
        // emits CALL/DONE; tool calls dispatch to handler lambdas whose
        // return value is fed back into the transcript.
        std::env::remove_var("ANTHROPIC_API_KEY");
        std::env::set_var("SRATCH_MOCK", "CALL dbl 21\n---\nDONE:got 42");
        let out = ev("t={\"dbl\"::(x){^#num(x)*2}}\n^#use(\"double 21\",t)").to_str();
        std::env::remove_var("SRATCH_MOCK");
        assert_eq!(out, "got 42");
    }

    #[test]
    fn sse_delta_parsing() {
        // Anthropic streaming deltas yield incremental text; other events don't.
        let d = r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#;
        assert_eq!(llm::sse_text_delta(d), Some("Hel".to_string()));
        let stop = r#"data: {"type":"message_stop"}"#;
        assert_eq!(llm::sse_text_delta(stop), None);
        assert_eq!(llm::sse_text_delta("event: ping"), None);
    }

    #[test]
    fn prompt_cache_marker() {
        use value::Val;
        use std::rc::Rc;
        let p = Val::Str(Rc::new("system context".into()));
        let plain = llm::build_messages(&p, false);
        let cached = llm::build_messages(&p, true);
        assert!(!plain.contains("cache_control"), "plain shouldn't cache: {plain}");
        assert!(cached.contains("\"cache_control\":{\"type\":\"ephemeral\"}"),
                "cached must mark cache_control: {cached}");
        assert!(cached.contains("system context"));
    }

    #[test]
    fn lambda_and_closures() {
        // anonymous function value
        assert_eq!(ev("f=:(x){^x*2}\n^f(21)").to_str(), "42");
        // closure captures surrounding variable by value
        assert_eq!(ev("n=10\ng=:(x){^x+n}\n^g(5)").to_str(), "15");
        // higher-order: pass a lambda as an argument
        assert_eq!(ev(":ap(fn,x){^fn(x)}\n^ap(:(n){^n*n},7)").to_str(), "49");
        // lambda used in a fold over a list
        assert_eq!(
            ev(":ms(fn,l){s=0 *x:l{s=s+fn(x)} ^s}\n^ms(:(n){^n*n},[1,2,3,4])").to_str(),
            "30"
        );
    }

    #[test]
    fn if_else() {
        let out = ev("a=5\n?a>3{^\"b\"}:{^\"s\"}").to_str();
        assert_eq!(out, "b");
    }

    #[test]
    fn repeat_and_list() {
        let out = ev("l=[]\n*3{l=l+[i]}\n^l").to_str();
        assert_eq!(out, "[0,1,2]");
    }

    #[test]
    fn for_in() {
        let out = ev("s=0\n*x:[1,2,3]{s=s+x}\n^s").to_str();
        assert_eq!(out, "6");
    }

    #[test]
    fn while_loop() {
        let out = ev("i=0\n*?i<3{i=i+1}\n^i").to_str();
        assert_eq!(out, "3");
    }

    #[test]
    fn func_def_and_call() {
        let out = ev(":ad(a,b){^a+b}\n^ad(2,3)").to_str();
        assert_eq!(out, "5");
    }

    #[test]
    fn dict_index() {
        let out = ev("d={\"k\":42}\n^d[\"k\"]").to_str();
        assert_eq!(out, "42");
    }

    #[test]
    fn str_concat() {
        let out = ev("^\"a\"+\"b\"+1").to_str();
        assert_eq!(out, "ab1");
    }

    #[test]
    fn tool_len() {
        let out = ev("^#len(\"hello\")").to_str();
        assert_eq!(out, "5");
    }

    #[test]
    fn nested_if() {
        let out = ev("x=10\n?x>5{?x>8{^\"v\"}:{^\"m\"}}:{^\"s\"}").to_str();
        assert_eq!(out, "v");
    }

    #[test]
    fn llm_stub() {
        // Without ANTHROPIC_API_KEY and SRATCH_MOCK, @ returns a stub string.
        std::env::remove_var("ANTHROPIC_API_KEY");
        std::env::remove_var("SRATCH_MOCK");
        let out = ev("^@\"hi\"").to_str();
        assert!(out.contains("hi"));
    }

    #[test]
    fn string_escapes_agent_dict() {
        // \R \D \S \G \O \E expand to common agent vocabulary
        let out = ev("^\"\\R\"").to_str();
        assert!(out.contains("ReAct") && out.contains("DONE:") && out.contains("SH:"));
        assert_eq!(ev("^\"\\D\"").to_str(), "DONE:");
        assert_eq!(ev("^\"\\S\"").to_str(), "SH:");
        assert_eq!(ev("^\"\\G\"").to_str(), "GOAL:");
    }

    #[test]
    fn tk_counts_tokens_approx() {
        // alphanumeric run "hello" (5 chars) -> ceil(5/4)=2;
        // " world" -> "world" (5)=2; total 4 ish.
        let out = ev("^#tk(\"hello world\")").to_str();
        let n: i64 = out.parse().unwrap();
        assert!((3..=5).contains(&n), "expected ~4 tokens for 'hello world', got {}", n);
        // punctuation each costs 1
        let out2 = ev("^#tk(\"a+b*c\")").to_str();
        let n2: i64 = out2.parse().unwrap();
        assert!((5..=6).contains(&n2), "expected ~5 tokens for 'a+b*c', got {}", n2);
    }

    #[test]
    fn glob_match_captures_after_marker() {
        // capture text following a marker
        let out = ev("^\"DONE:hello\"=~\"DONE:*\"").to_str();
        assert_eq!(out, "hello");
        // pattern not present -> nil ("n" in our printer)
        let out2 = ev("^\"hi\"=~\"DONE:*\"").to_str();
        assert_eq!(out2, "n");
        // prefix*suffix capture
        let out3 = ev("^\"[1,2,3]\"=~\"[*]\"").to_str();
        assert_eq!(out3, "1,2,3");
    }

    #[test]
    fn function_scope_barrier_prevents_clobber() {
        // Without the barrier, the inner function's S=[] would walk
        // outward and overwrite the outer function's S. With the
        // barrier in place, both Ss are independent.
        let src = r#"
:inner(){S=[] #push(S,"inner") ^S}
:outer(){S=[] #push(S,"outer") inner() #push(S,"after") ^S}
^outer()
"#;
        let out = ev(src).to_str();
        assert_eq!(out, "[outer,after]");
    }

    #[test]
    fn self_hosted_py_transpile_runs() {
        // Sratch source -> Python source -> python3 runs it.
        // Skips when run from a working dir without compiler/ or python3.
        if !std::path::Path::new("compiler/emit_py.sra").exists() {
            return;
        }
        if std::process::Command::new("python3").arg("--version")
            .output().is_err() { return; }
        let src = r#"
#inc("compiler/lex.sra")
#inc("compiler/parse.sra")
#inc("compiler/emit_py.sra")
toks=[] pi=0
prog=":fact(n){?n<=1{^1} ^n*fact(n-1)}
>fact(5)"
py=py_emit(parse(lex(prog)))
#wr("/tmp/sratch_py_test.py",py)
>#sh("python3 /tmp/sratch_py_test.py")
"#;
        let out = ev(src).to_str();
        // ev() prints to real stdout; we only get the final value back.
        // Just assert no error path was taken and the result is Nil-ish.
        // The actual fact(5)=120 went to stdout during eval.
        let _ = out;
        // Verify by reading the generated file and re-running explicitly.
        let py = std::fs::read_to_string("/tmp/sratch_py_test.py").unwrap();
        assert!(py.contains("def fact("));
        assert!(py.contains("print(fact(5))"));
        let run = std::process::Command::new("python3")
            .arg("/tmp/sratch_py_test.py")
            .output().unwrap();
        let stdout = String::from_utf8_lossy(&run.stdout).trim().to_string();
        assert_eq!(stdout, "120");
    }

    #[test]
    fn self_hosted_eval_runs_factorial() {
        // Closes the bootstrap: lex + parse + eval, all in Sratch,
        // computing fact(6) inside the inner interpreter.
        // Skips when run from a working directory without the compiler/.
        if !std::path::Path::new("compiler/eval.sra").exists() {
            return;
        }
        let src = r#"
#inc("compiler/lex.sra")
#inc("compiler/parse.sra")
#inc("compiler/eval.sra")
toks=[] pi=0
ENV={"scopes":[{}],"barriers":[]}
prog=":fact(n){?n<=1{^1} ^n*fact(n-1)}
^fact(6)"
ast=parse(lex(prog))
^eval_ast(ast)
"#;
        let out = ev(src).to_str();
        assert_eq!(out, "720");
    }

    #[test]
    fn sh_transpile_round_trip() {
        // Transpile Sratch -> Bash, run it, compare output. Skipped if
        // the compiler module isn't there.
        if !std::path::Path::new("compiler/emit_sh.sra").exists() { return; }
        let out_sh = std::env::temp_dir().join("sratch_sh_out.sh");
        let driver = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_sh.sra","Sh")
src=":fact(n){{?n<=1{{^1}} ^n*fact(n-1)}}
>fact(5)"
sh=Sh.emit_sh(P.parse(L.lex(src)))
#wr("{out}",sh)
^#sh("bash {out}")
"#, out = out_sh.display());
        let out = ev(&driver).to_str();
        std::fs::remove_file(&out_sh).ok();
        assert_eq!(out, "120");
    }

    #[test]
    fn html_wrap_produces_doc() {
        if !std::path::Path::new("compiler/emit_html.sra").exists() { return; }
        let driver = r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
#inc("compiler/emit_html.sra","H")
js=J.emit_js(P.parse(L.lex(">42")))
^H.wrap_html(js)
"#;
        let out = ev(driver).to_str();
        assert!(out.starts_with("<!DOCTYPE html>"), "expected HTML doctype");
        assert!(out.contains("sr.print(42)"), "expected JS body inline");
        assert!(out.contains("</script></body></html>"), "expected proper close");
    }

    fn transpile_run(emit_fn: &str, ext: &str, runner: &str) -> Option<String> {
        let module = format!("compiler/emit_{}.sra", ext);
        if !std::path::Path::new(&module).exists() { return None; }
        let bin = runner.split_whitespace().next().unwrap();
        if std::process::Command::new(bin).arg("--version").output().is_err() { return None; }
        let out_file = std::env::temp_dir().join(format!("sratch_t.{}", ext));
        let driver = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("{module}","E")
src=":fact(n){{?n<=1{{^1}} ^n*fact(n-1)}}
>fact(6)
M=[1,2,3]
#push(M,4)
>#join(M,\",\")"
code=E.{emit_fn}(P.parse(L.lex(src)))
#wr("{out}",code)
^#sh("{runner} {out} 2>&1")
"#, module = module, emit_fn = emit_fn, out = out_file.display(), runner = runner);
        let r = ev(&driver).to_str();
        std::fs::remove_file(&out_file).ok();
        Some(r)
    }

    #[test]
    fn ruby_transpile() {
        if let Some(out) = transpile_run("rb_emit", "rb", "ruby") {
            assert!(out.contains("720") && out.contains("1,2,3,4"), "ruby: {}", out);
        }
    }

    #[test]
    fn go_transpile() {
        if let Some(out) = transpile_run("go_emit", "go", "go run") {
            assert!(out.contains("720") && out.contains("1,2,3,4"), "go: {}", out);
        }
    }

    #[test]
    fn c_transpile() {
        if !std::path::Path::new("compiler/emit_c.sra").exists() { return; }
        if std::process::Command::new("gcc").arg("--version").output().is_err() { return; }
        let cf = std::env::temp_dir().join("sratch_t.c");
        let bin = std::env::temp_dir().join("sratch_t_cbin");
        let d = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_c.sra","C")
src=":fact(n){{?n<=1{{^1}} ^n*fact(n-1)}}
>fact(6)
M=[1,2,3]
#push(M,4)
>#join(M,\",\")"
code=C.c_emit(P.parse(L.lex(src)))
#wr("{cf}",code)
^#sh("gcc -w {cf} -o {bin} 2>&1 && {bin}")
"#, cf = cf.display(), bin = bin.display());
        let o = ev(&d).to_str();
        std::fs::remove_file(&cf).ok();
        std::fs::remove_file(&bin).ok();
        assert!(o.contains("720") && o.contains("1,2,3,4"), "c: {}", o);
    }

    #[test]
    fn bash_dict_via_assoc_array() {
        if !std::path::Path::new("compiler/emit_sh.sra").exists() { return; }
        let out_sh = std::env::temp_dir().join("sratch_dict.sh");
        let d = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_sh.sra","S")
src="d={{\"name\":\"sratch\",\"ver\":3}}
>d.name
>d.ver"
sh=S.emit_sh(P.parse(L.lex(src)))
#wr("{out}",sh)
^#sh("bash {out}")
"#, out = out_sh.display());
        let o = ev(&d).to_str();
        std::fs::remove_file(&out_sh).ok();
        assert!(o.contains("sratch") && o.contains('3'), "bash dict: {}", o);
    }

    #[test]
    fn js_llm_bridge_stub_and_agent() {
        if !std::path::Path::new("compiler/emit_js.sra").exists() { return; }
        if std::process::Command::new("node").arg("--version").output().is_err() { return; }
        let out_js = std::env::temp_dir().join("sratch_jsllm.js");
        // @ stub path (no API key) + provider routing
        let d1 = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
js=J.emit_js(P.parse(L.lex(">@\"hi\" %\"gpt-4o\"")))
#wr("{out}",js)
^#sh("node {out}")
"#, out = out_js.display());
        let o1 = ev(&d1).to_str();
        assert!(o1.contains("stub:gpt-4o") && o1.contains("hi"), "js @ stub: {}", o1);
        // ~ agent loop driven by SRATCH_MOCK
        let d2 = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
js=J.emit_js(P.parse(L.lex(">~\"go\"")))
#wr("{out}",js)
^#sh("SRATCH_MOCK=$(printf 'SH:echo hi\n---\nDONE:ok') node {out}")
"#, out = out_js.display());
        let o2 = ev(&d2).to_str();
        std::fs::remove_file(&out_js).ok();
        assert!(o2.contains("DONE:ok"), "js ~ agent: {}", o2);
    }

    #[test]
    fn py_llm_bridge_stub() {
        if !std::path::Path::new("compiler/emit_py.sra").exists() { return; }
        if std::process::Command::new("python3").arg("--version").output().is_err() { return; }
        let out_py = std::env::temp_dir().join("sratch_pyllm.py");
        let d = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_py.sra","Y")
py=Y.py_emit(P.parse(L.lex(">@\"hi\"")))
#wr("{out}",py)
^#sh("python3 {out}")
"#, out = out_py.display());
        let o = ev(&d).to_str();
        std::fs::remove_file(&out_py).ok();
        assert!(o.contains("stub:claude-haiku-4-5") && o.contains("hi"), "py @ stub: {}", o);
    }

    #[test]
    fn js_transpile_round_trip() {
        // Transpile Sratch -> JS, run it with node, compare output.
        // Skipped if node or the compiler module isn't available.
        if !std::path::Path::new("compiler/emit_js.sra").exists() { return; }
        if std::process::Command::new("node").arg("--version").output().is_err() { return; }
        let prog = std::env::temp_dir().join("sratch_js_prog.sra");
        let js_out = std::env::temp_dir().join("sratch_js_out.js");
        std::fs::write(&prog, ":sq(n){^n*n}\n>sq(7)\n>\"a\"+\"b\"\n").unwrap();
        let driver = format!(r#"
#inc("compiler/lex.sra","L")
#inc("compiler/parse.sra","P")
#inc("compiler/emit_js.sra","J")
src=#rd("{prog}")
js=J.emit_js(P.parse(L.lex(src)))
#wr("{out}",js)
^#sh("node {out}")
"#, prog = prog.display(), out = js_out.display());
        let out = ev(&driver).to_str();
        std::fs::remove_file(&prog).ok();
        std::fs::remove_file(&js_out).ok();
        assert!(out.contains("49"), "expected sq(7)=49 in: {}", out);
        assert!(out.contains("ab"), "expected 'ab' concat in: {}", out);
    }

    #[test]
    fn inc_with_prefix_namespaces_module() {
        // Module-local state (counter) plus a mutating helper that
        // updates it across calls. The prefix mangles both the
        // top-level defs AND every reference to them, so M.tick()
        // and the internal `counter=counter+1` use the same binding.
        let tmp = std::env::temp_dir().join("sratch_ns_test.sra");
        std::fs::write(&tmp, "counter=0\n:tick(){counter=counter+1 ^counter}\n").unwrap();
        let src = format!(
            "#inc(\"{}\",\"M\")\nM.tick()\nM.tick()\n^M.tick()",
            tmp.display()
        );
        let out = ev(&src).to_str();
        std::fs::remove_file(&tmp).ok();
        assert_eq!(out, "3");
    }

    #[test]
    fn inc_loads_external_module() {
        // Write a temp module that defines a function, include it,
        // call the function.
        let tmp = std::env::temp_dir().join("sratch_inc_test.sra");
        std::fs::write(&tmp, ":dbl(x){^x*2}\n").unwrap();
        let src = format!("#inc(\"{}\")\n^dbl(7)", tmp.display());
        let out = ev(&src).to_str();
        std::fs::remove_file(&tmp).ok();
        assert_eq!(out, "14");
    }

    #[test]
    fn global_state_remains_mutable_from_helpers() {
        // Top-level declarations stay reachable: helpers can update them.
        let src = r#"
pi=0
:bump(){pi=pi+1 ^pi}
bump() bump() bump()
^pi
"#;
        let out = ev(src).to_str();
        assert_eq!(out, "3");
    }

    #[test]
    fn llm_multi_turn_via_list() {
        // Mock returns a fixed reply; here we just assert that @list does
        // not error and that the stub path handles a Val::List prompt.
        std::env::remove_var("ANTHROPIC_API_KEY");
        std::env::remove_var("OPENAI_API_KEY");
        std::env::remove_var("SRATCH_MOCK");
        let out = ev("^@[\"hi\",\"hello\",\"more\"]").to_str();
        // stub echoes the .to_str() of the original Val::List
        assert!(out.starts_with("[stub:"));
        assert!(out.contains("hi") && out.contains("hello") && out.contains("more"));
    }

    #[test]
    fn openai_model_routes_to_stub_without_key() {
        // gpt-* prefix is detected as OpenAI; without OPENAI_API_KEY
        // and SRATCH_MOCK the call must hit the deterministic stub
        // (not the Anthropic path).
        std::env::remove_var("ANTHROPIC_API_KEY");
        std::env::remove_var("OPENAI_API_KEY");
        std::env::remove_var("SRATCH_MOCK");
        let out = ev("^@\"hi\" %\"gpt-4o\"").to_str();
        assert!(out.contains("gpt-4o"), "expected gpt-4o in stub, got: {}", out);
        assert!(out.contains("hi"));
    }

    #[test]
    fn agent_loop_primitive() {
        // ~prompt runs a ReAct loop. Drive it with SRATCH_MOCK so the
        // first reply runs a shell, the second emits DONE.
        std::env::remove_var("ANTHROPIC_API_KEY");
        std::env::set_var("SRATCH_MOCK", "SH:echo seven\n---\nDONE:got it");
        let out = ev("^~\"go\"").to_str();
        std::env::remove_var("SRATCH_MOCK");
        assert!(out.starts_with("DONE:"), "expected DONE: prefix, got: {}", out);
    }
}
