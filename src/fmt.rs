//! Canonical source formatter: AST -> normalized Sratch source.
//! Mirrors compiler/emit.sra. Used by `sratch --fmt`.

use crate::ast::*;

pub fn format(prog: &[Stmt]) -> String {
    let mut out = String::new();
    for s in prog {
        out.push_str(&stmt(s, 0));
        out.push('\n');
    }
    out
}

fn ind(d: usize) -> String { "  ".repeat(d) }

fn block(stmts: &[Stmt], d: usize) -> String {
    let mut out = String::new();
    for s in stmts {
        out.push_str(&stmt(s, d));
        out.push('\n');
    }
    out
}

fn stmt(s: &Stmt, d: usize) -> String {
    let i = ind(d);
    match s {
        Stmt::Assign(n, e) => format!("{i}{n}={}", expr(e)),
        Stmt::AssignIdx(a, idx, v) => format!("{i}{}[{}]={}", expr(a), expr(idx), expr(v)),
        Stmt::Print(e) => format!("{i}>{}", expr(e)),
        Stmt::Return(e) => format!("{i}^{}", expr(e)),
        Stmt::Expr(e) => format!("{i}{}", expr(e)),
        Stmt::Break => format!("{i}brk"),
        Stmt::Continue => format!("{i}cnt"),
        Stmt::If(c, t, e) => {
            let mut r = format!("{i}?{}{{\n{}{i}}}", expr(c), block(t, d + 1));
            if let Some(eb) = e {
                r.push_str(&format!(":{{\n{}{i}}}", block(eb, d + 1)));
            }
            r
        }
        Stmt::Repeat(n, b) => format!("{i}*{}{{\n{}{i}}}", expr(n), block(b, d + 1)),
        Stmt::For(x, it, b) => format!("{i}*{x}:{}{{\n{}{i}}}", expr(it), block(b, d + 1)),
        Stmt::While(c, b) => format!("{i}*?{}{{\n{}{i}}}", expr(c), block(b, d + 1)),
        Stmt::Def(n, ps, b) => {
            format!("{i}:{n}({}){{\n{}{i}}}", ps.join(","), block(b, d + 1))
        }
    }
}

fn op_str(op: BinOp) -> &'static str {
    match op {
        BinOp::Add => "+", BinOp::Sub => "-", BinOp::Mul => "*", BinOp::Div => "/",
        BinOp::Mod => "%", BinOp::Eq => "==", BinOp::Ne => "!=", BinOp::Lt => "<",
        BinOp::Gt => ">", BinOp::Le => "<=", BinOp::Ge => ">=", BinOp::And => "&",
        BinOp::Or => "|", BinOp::Match => "=~",
    }
}

fn esc(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out
}

fn num(n: f64) -> String {
    if n.fract() == 0.0 && n.is_finite() && n.abs() < 1e16 {
        format!("{}", n as i64)
    } else {
        format!("{}", n)
    }
}

fn expr(e: &Expr) -> String {
    match e {
        Expr::Num(n) => num(*n),
        Expr::Str(s) => format!("\"{}\"", esc(s)),
        Expr::Bool(b) => if *b { "T".into() } else { "F".into() },
        Expr::Nil => "N".into(),
        Expr::Ident(n) => n.clone(),
        Expr::List(items) => {
            let parts: Vec<String> = items.iter().map(expr).collect();
            format!("[{}]", parts.join(","))
        }
        Expr::Dict(kvs) => {
            let parts: Vec<String> = kvs.iter()
                .map(|(k, v)| format!("{}:{}", expr(k), expr(v)))
                .collect();
            format!("{{{}}}", parts.join(","))
        }
        Expr::Bin(op, a, b) => format!("({}{}{})", expr(a), op_str(*op), expr(b)),
        Expr::Un(op, x) => {
            let o = match op { UnOp::Neg => "-", UnOp::Not => "!" };
            format!("{o}{}", expr(x))
        }
        Expr::Index(a, i) => format!("{}[{}]", expr(a), expr(i)),
        Expr::Field(a, k) => format!("{}.{k}", expr(a)),
        Expr::Call(f, args) => {
            let parts: Vec<String> = args.iter().map(expr).collect();
            format!("{}({})", expr(f), parts.join(","))
        }
        Expr::Tool(name, args) => {
            let parts: Vec<String> = args.iter().map(expr).collect();
            format!("#{name}({})", parts.join(","))
        }
        Expr::Llm(p, m) => {
            let mut r = format!("@{}", expr(p));
            if let Some(m) = m { r.push_str(&format!(" %{}", expr(m))); }
            r
        }
        Expr::Agent(p) => format!("~{}", expr(p)),
        Expr::Lambda(ps, body) => {
            format!(":({}){{\n{}}}", ps.join(","), block(body, 1))
        }
    }
}
