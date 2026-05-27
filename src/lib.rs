pub mod ast;
pub mod builtins;
pub mod eval;
pub mod lexer;
pub mod llm;
pub mod parser;
pub mod value;

use eval::Interp;
use lexer::Lexer;
use parser::Parser;
use value::Val;

pub fn run(src: &str) -> Result<Val, String> {
    let toks = Lexer::new(src).tokens()?;
    let prog = Parser::new(toks).program()?;
    Interp::new().run(&prog)
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
