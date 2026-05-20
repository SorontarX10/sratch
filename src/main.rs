use std::io::Read;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let src = if args.len() < 2 {
        let mut s = String::new();
        if std::io::stdin().read_to_string(&mut s).is_err() {
            eprintln!("usage: sratch <file.sr> | -e <code> | -");
            std::process::exit(2);
        }
        s
    } else if args[1] == "-e" {
        if args.len() < 3 { eprintln!("usage: sratch -e <code>"); std::process::exit(2); }
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
