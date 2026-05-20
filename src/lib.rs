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
        // Without ANTHROPIC_API_KEY, @ returns a stub string.
        std::env::remove_var("ANTHROPIC_API_KEY");
        let out = ev("^@\"hi\"").to_str();
        assert!(out.contains("hi"));
    }
}
