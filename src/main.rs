use std::io::{Read, Write};

const USAGE: &str = "usage: sratch <file.sra> | -e <code> | - | --fmt <file> | --repl";

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // --fmt <file>: print canonical formatting and exit.
    if args.get(1).map(|s| s.as_str()) == Some("--fmt") {
        let Some(path) = args.get(2) else { eprintln!("{USAGE}"); std::process::exit(2); };
        let src = match std::fs::read_to_string(path) {
            Ok(s) => s,
            Err(e) => { eprintln!("sratch: cannot read {path}: {e}"); std::process::exit(2); }
        };
        match sratch::format_src(&src) {
            Ok(out) => { print!("{out}"); }
            Err(e) => { eprintln!("sratch: {e}"); std::process::exit(1); }
        }
        return;
    }

    // --repl: interactive read-eval-print loop with persistent state.
    if args.get(1).map(|s| s.as_str()) == Some("--repl") {
        repl();
        return;
    }

    let src = if args.len() < 2 {
        let mut s = String::new();
        if std::io::stdin().read_to_string(&mut s).is_err() {
            eprintln!("{USAGE}");
            std::process::exit(2);
        }
        s
    } else if args[1] == "-e" {
        if args.len() < 3 { eprintln!("{USAGE}"); std::process::exit(2); }
        args[2].clone()
    } else if args[1] == "-" {
        let mut s = String::new();
        std::io::stdin().read_to_string(&mut s).unwrap();
        s
    } else {
        match std::fs::read_to_string(&args[1]) {
            Ok(s) => s,
            Err(e) => { eprintln!("sratch: cannot read {}: {}", args[1], e); std::process::exit(2); }
        }
    };

    match sratch::run(&src) {
        Ok(_) => {}
        Err(e) => { eprintln!("sratch: {}", e); std::process::exit(1); }
    }
}

fn repl() {
    use sratch::lexer::Lexer;
    use sratch::parser::Parser;
    use sratch::Interp;

    let mut interp = Interp::new();
    let stdin = std::io::stdin();
    eprintln!("sratch repl — Ctrl-D to exit");
    loop {
        print!("> ");
        let _ = std::io::stdout().flush();
        let mut line = String::new();
        match stdin.read_line(&mut line) {
            Ok(0) => break,        // EOF
            Ok(_) => {}
            Err(_) => break,
        }
        let line = line.trim_end();
        if line.is_empty() { continue; }
        let prog = match Lexer::new(line).tokens().and_then(|t| Parser::new(t).program()) {
            Ok(p) => p,
            Err(e) => { eprintln!("parse: {e}"); continue; }
        };
        match interp.run_repl(&prog) {
            Ok(v) => {
                // Echo the value of a trailing bare expression.
                let s = v.to_str();
                if !s.is_empty() && s != "n" { println!("{s}"); }
            }
            Err(e) => eprintln!("err: {e}"),
        }
    }
}
