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
