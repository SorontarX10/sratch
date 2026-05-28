use crate::ast::*;
use crate::ast::{Expr, Stmt};
use crate::builtins::{call_tool, glob_capture};
use crate::lexer::Lexer;
use crate::parser::Parser;
use std::collections::HashSet;
use crate::llm::llm_call;
use crate::value::{Env, Fun, Val};
use std::cell::RefCell;
use std::rc::Rc;

pub enum Flow { Norm, Ret(Val), Brk, Cnt }

pub struct Interp { pub env: Env }

impl Interp {
    pub fn new() -> Self {
        // T/F/N are resolved as evaluator constants (see eval of Ident),
        // not stored as writable globals — so a function-local named `T`
        // can't clobber the global `true`. Users may still shadow them
        // with an explicit binding.
        Self { env: Env::new() }
    }

    pub fn run(&mut self, prog: &[Stmt]) -> Result<Val, String> {
        let mut last = Val::Nil;
        for s in prog {
            match self.exec(s)? {
                Flow::Norm => {}
                Flow::Ret(v) => return Ok(v),
                _ => return Err("brk/cnt outside loop".into()),
            }
            last = Val::Nil;
        }
        Ok(last)
    }

    /// REPL entry: like `run`, but echoes the value of a trailing bare
    /// expression statement (so `2+3` evaluates to 5 interactively).
    pub fn run_repl(&mut self, prog: &[Stmt]) -> Result<Val, String> {
        for (i, s) in prog.iter().enumerate() {
            if i + 1 == prog.len() {
                if let Stmt::Expr(e) = s {
                    return self.eval(e);
                }
            }
            match self.exec(s)? {
                Flow::Norm => {}
                Flow::Ret(v) => return Ok(v),
                _ => return Err("brk/cnt outside loop".into()),
            }
        }
        Ok(Val::Nil)
    }

    fn exec_block(&mut self, body: &[Stmt]) -> Result<Flow, String> {
        for s in body {
            match self.exec(s)? {
                Flow::Norm => {}
                other => return Ok(other),
            }
        }
        Ok(Flow::Norm)
    }

    fn exec(&mut self, s: &Stmt) -> Result<Flow, String> {
        match s {
            Stmt::Expr(e) => { self.eval(e)?; Ok(Flow::Norm) }
            Stmt::Assign(n, e) => { let v = self.eval(e)?; self.env.set(n, v); Ok(Flow::Norm) }
            Stmt::AssignIdx(arr, idx, val) => {
                let a = self.eval(arr)?;
                let i = self.eval(idx)?;
                let v = self.eval(val)?;
                match a {
                    Val::List(l) => {
                        let ii = i.to_num()? as usize;
                        let mut lb = l.borrow_mut();
                        if ii >= lb.len() { return Err("index out of bounds".into()); }
                        lb[ii] = v;
                    }
                    Val::Dict(d) => {
                        let mut db = d.borrow_mut();
                        if let Some(slot) = db.iter_mut().find(|(k, _)| k.eq_val(&i)) {
                            slot.1 = v;
                        } else {
                            db.push((i, v));
                        }
                    }
                    _ => return Err("index-assign: bad type".into()),
                }
                Ok(Flow::Norm)
            }
            Stmt::Print(e) => { let v = self.eval(e)?; println!("{}", v); Ok(Flow::Norm) }
            Stmt::Return(e) => { let v = self.eval(e)?; Ok(Flow::Ret(v)) }
            Stmt::If(c, t, e) => {
                if self.eval(c)?.truthy() { self.exec_block(t) }
                else if let Some(b) = e { self.exec_block(b) }
                else { Ok(Flow::Norm) }
            }
            Stmt::Repeat(n, body) => {
                let n = self.eval(n)?.to_num()? as i64;
                self.env.push();
                let mut i = 0i64;
                while i < n {
                    self.env.set_local("i", Val::Num(i as f64));
                    match self.exec_block(body)? {
                        Flow::Norm | Flow::Cnt => {}
                        Flow::Brk => break,
                        Flow::Ret(v) => { self.env.pop(); return Ok(Flow::Ret(v)); }
                    }
                    i += 1;
                }
                self.env.pop();
                Ok(Flow::Norm)
            }
            Stmt::For(name, iter, body) => {
                let it = self.eval(iter)?;
                let items: Vec<Val> = match it {
                    Val::List(l) => l.borrow().clone(),
                    Val::Str(s) => s.chars().map(|c| Val::Str(Rc::new(c.to_string()))).collect(),
                    Val::Dict(d) => d.borrow().iter().map(|(k, _)| k.clone()).collect(),
                    Val::Num(n) => {
                        let mut v = Vec::new();
                        let mut i = 0i64;
                        let stop = n as i64;
                        while i < stop { v.push(Val::Num(i as f64)); i += 1; }
                        v
                    }
                    _ => return Err("for: not iterable".into()),
                };
                self.env.push();
                for it in items {
                    self.env.set_local(name, it);
                    match self.exec_block(body)? {
                        Flow::Norm | Flow::Cnt => {}
                        Flow::Brk => break,
                        Flow::Ret(v) => { self.env.pop(); return Ok(Flow::Ret(v)); }
                    }
                }
                self.env.pop();
                Ok(Flow::Norm)
            }
            Stmt::While(c, body) => {
                loop {
                    if !self.eval(c)?.truthy() { break; }
                    match self.exec_block(body)? {
                        Flow::Norm | Flow::Cnt => {}
                        Flow::Brk => break,
                        Flow::Ret(v) => return Ok(Flow::Ret(v)),
                    }
                }
                Ok(Flow::Norm)
            }
            Stmt::Def(name, params, body) => {
                let f = Val::Fn(Rc::new(Fun {
                    name: name.clone(),
                    params: params.clone(),
                    body: body.clone(),
                    captured: None,
                }));
                self.env.set(name, f);
                Ok(Flow::Norm)
            }
            Stmt::Break => Ok(Flow::Brk),
            Stmt::Continue => Ok(Flow::Cnt),
        }
    }

    fn eval(&mut self, e: &Expr) -> Result<Val, String> {
        Ok(match e {
            Expr::Num(n) => Val::Num(*n),
            Expr::Str(s) => Val::Str(Rc::new(s.clone())),
            Expr::Bool(b) => Val::Bool(*b),
            Expr::Nil => Val::Nil,
            Expr::Ident(n) => match self.env.get(n) {
                Some(v) => v,
                None => match n.as_str() {
                    "T" => Val::Bool(true),
                    "F" => Val::Bool(false),
                    "N" => Val::Nil,
                    _ => return Err(format!("undefined: {}", n)),
                },
            },
            Expr::List(items) => {
                let mut v = Vec::with_capacity(items.len());
                for it in items { v.push(self.eval(it)?); }
                Val::List(Rc::new(RefCell::new(v)))
            }
            Expr::Dict(kvs) => {
                let mut d = Vec::with_capacity(kvs.len());
                for (k, v) in kvs {
                    let kv = self.eval(k)?;
                    let vv = self.eval(v)?;
                    d.push((kv, vv));
                }
                Val::Dict(Rc::new(RefCell::new(d)))
            }
            Expr::Bin(op, a, b) => {
                if *op == BinOp::And {
                    let av = self.eval(a)?;
                    return Ok(if !av.truthy() { av } else { self.eval(b)? });
                }
                if *op == BinOp::Or {
                    let av = self.eval(a)?;
                    return Ok(if av.truthy() { av } else { self.eval(b)? });
                }
                let av = self.eval(a)?;
                let bv = self.eval(b)?;
                bin(*op, av, bv)?
            }
            Expr::Un(op, x) => {
                let v = self.eval(x)?;
                match op {
                    UnOp::Neg => Val::Num(-v.to_num()?),
                    UnOp::Not => Val::Bool(!v.truthy()),
                }
            }
            Expr::Index(a, i) => {
                let av = self.eval(a)?;
                let iv = self.eval(i)?;
                index(av, iv)?
            }
            Expr::Field(a, k) => {
                let av = self.eval(a)?;
                index(av, Val::Str(Rc::new(k.clone())))?
            }
            Expr::Call(callee, args) => {
                let mut argv = Vec::with_capacity(args.len());
                for a in args { argv.push(self.eval(a)?); }
                let cv = self.eval(callee)?;
                match cv {
                    Val::Fn(f) => self.call_fn(&f, argv)?,
                    _ => return Err("not callable".into()),
                }
            }
            Expr::Tool(name, args) => {
                let mut argv = Vec::with_capacity(args.len());
                for a in args { argv.push(self.eval(a)?); }
                // #inc(path) reads, parses, and evaluates another .sra
                // file in the current scope. Needs interpreter access,
                // so it lives here rather than in builtins.rs.
                if name == "use" {
                    // #use(prompt, tools) — native structured tool-use.
                    // tools is a dict { name: handler_lambda }. Runs the
                    // tool-use loop, dispatching tool calls to handlers.
                    let prompt = argv.first().map(|v| v.to_str()).unwrap_or_default();
                    let handlers: Vec<(String, Val)> = match argv.get(1) {
                        Some(Val::Dict(d)) => d.borrow().iter()
                            .map(|(k, v)| (k.to_str(), v.clone())).collect(),
                        _ => return Err("#use: second arg must be a tools dict".into()),
                    };
                    let names: Vec<String> = handlers.iter().map(|(n, _)| n.clone()).collect();
                    let trace = std::env::var("SRATCH_TRACE").is_ok();
                    let max: usize = std::env::var("SRATCH_AGENT_MAX")
                        .ok().and_then(|s| s.parse().ok()).unwrap_or(20);
                    let mut history = prompt;
                    let mut result = Val::Nil;
                    for _ in 0..max {
                        match crate::llm::llm_tooluse(&history, &names)? {
                            crate::llm::ToolReply::Text(t) => {
                                result = Val::Str(Rc::new(t));
                                break;
                            }
                            crate::llm::ToolReply::Call(tname, input) => {
                                let h = handlers.iter().find(|(n, _)| *n == tname);
                                let out = match h {
                                    Some((_, Val::Fn(f))) => {
                                        self.call_fn(f, vec![Val::Str(Rc::new(input.clone()))])?
                                    }
                                    _ => Val::Str(Rc::new(format!("no tool {}", tname))),
                                };
                                if trace { eprintln!("<<CALL {}({}) >>{}", tname, input, out.to_str()); }
                                history.push_str(&format!("\nTOOL {}({}) -> {}", tname, input, out.to_str()));
                            }
                        }
                    }
                    result
                } else if name == "inc" {
                    let path = argv.first()
                        .ok_or("inc: path required")?
                        .to_str();
                    let prefix = argv.get(1).map(|v| v.to_str());
                    let src = std::fs::read_to_string(&path)
                        .map_err(|e| format!("inc {}: {}", path, e))?;
                    let toks = Lexer::new(&src).tokens()?;
                    let mut prog = Parser::new(toks).program()?;

                    if let Some(pfx) = prefix {
                        // Collect all top-level def/assign names — those
                        // become "module-local" and get mangled with the
                        // prefix everywhere they appear.
                        let mut defs: HashSet<String> = HashSet::new();
                        for s in &prog {
                            match s {
                                Stmt::Def(n, ..) | Stmt::Assign(n, _) => {
                                    defs.insert(n.clone());
                                }
                                _ => {}
                            }
                        }
                        let pfx_owned = pfx.clone();
                        let mangle = move |n: &str| format!("{}_{}", pfx_owned, n);
                        rewrite_stmts(&mut prog, &defs, &mangle);

                        for s in &prog {
                            match self.exec(s)? {
                                Flow::Norm => {}
                                Flow::Ret(v) => return Ok(v),
                                _ => return Err("brk/cnt outside loop in inc".into()),
                            }
                        }
                        // Expose the module as a dict so callers can write
                        // `M.foo(args)` instead of remembering mangled names.
                        let mut entries: Vec<(Val, Val)> = Vec::new();
                        for name in &defs {
                            let mangled = mangle(name);
                            if let Some(v) = self.env.get(&mangled) {
                                entries.push((Val::Str(Rc::new(name.clone())), v));
                            }
                        }
                        self.env.set(&pfx, Val::Dict(Rc::new(RefCell::new(entries))));
                        return Ok(Val::Nil);
                    }

                    for s in &prog {
                        match self.exec(s)? {
                            Flow::Norm => {}
                            Flow::Ret(v) => return Ok(v),
                            _ => return Err("brk/cnt outside loop in inc".into()),
                        }
                    }
                    Val::Nil
                } else {
                    call_tool(name, &argv)?
                }
            }
            Expr::Llm(p, m) => {
                let pv = self.eval(p)?;
                let mv = match m { Some(x) => Some(self.eval(x)?), None => None };
                llm_call(&pv, mv.as_ref())?
            }
            Expr::Agent(initial) => {
                let mut h = self.eval(initial)?.to_str();
                let max: usize = std::env::var("SRATCH_AGENT_MAX")
                    .ok().and_then(|s| s.parse().ok()).unwrap_or(20);
                let trace = std::env::var("SRATCH_TRACE").is_ok();
                let mut out = Val::Str(Rc::new(String::new()));
                for _ in 0..max {
                    let r = llm_call(&Val::Str(Rc::new(h.clone())), None)?;
                    let rs = r.to_str();
                    if trace { eprintln!("<<{}", rs); }
                    if rs.contains("DONE:") {
                        out = Val::Str(Rc::new(rs));
                        break;
                    }
                    if let Some(i) = rs.find("SH:") {
                        let cmd = rs[i + 3..].trim();
                        let obs = call_tool("sh", &[Val::Str(Rc::new(cmd.to_string()))])?;
                        let os = obs.to_str();
                        if trace { eprintln!(">>O:{}", os); }
                        h.push_str("\nO:");
                        h.push_str(&os);
                    } else {
                        if trace { eprintln!(">>E"); }
                        h.push_str("\nE");
                    }
                    out = Val::Str(Rc::new(rs));
                }
                out
            }
            Expr::Lambda(params, body) => {
                Val::Fn(Rc::new(Fun {
                    name: "<lambda>".into(),
                    params: params.clone(),
                    body: body.clone(),
                    captured: Some(self.env.snapshot()),
                }))
            }
        })
    }

    fn call_fn(&mut self, f: &Fun, args: Vec<Val>) -> Result<Val, String> {
        self.env.enter_fn();
        // Closures: replay the captured environment into the frame first,
        // then bind params on top (params shadow captured names).
        if let Some(cap) = &f.captured {
            for (k, v) in cap.iter() {
                self.env.set_local(k, v.clone());
            }
        }
        for (i, p) in f.params.iter().enumerate() {
            self.env.set_local(p, args.get(i).cloned().unwrap_or(Val::Nil));
        }
        let r = self.exec_block(&f.body);
        self.env.leave_fn();
        match r? {
            Flow::Ret(v) => Ok(v),
            Flow::Norm => Ok(Val::Nil),
            _ => Err("brk/cnt outside loop".into()),
        }
    }
}

fn bin(op: BinOp, a: Val, b: Val) -> Result<Val, String> {
    use BinOp::*;
    Ok(match op {
        Add => match (&a, &b) {
            (Val::Str(_), _) | (_, Val::Str(_)) => {
                Val::Str(Rc::new(format!("{}{}", a, b)))
            }
            (Val::List(x), Val::List(y)) => {
                let mut v = x.borrow().clone();
                v.extend(y.borrow().iter().cloned());
                Val::List(Rc::new(RefCell::new(v)))
            }
            _ => Val::Num(a.to_num()? + b.to_num()?),
        },
        Sub => Val::Num(a.to_num()? - b.to_num()?),
        Mul => match (&a, &b) {
            (Val::Str(s), _) => {
                let n = b.to_num()? as i64;
                Val::Str(Rc::new(s.repeat(n.max(0) as usize)))
            }
            _ => Val::Num(a.to_num()? * b.to_num()?),
        },
        Div => {
            let d = b.to_num()?;
            if d == 0.0 { return Err("div by zero".into()); }
            Val::Num(a.to_num()? / d)
        }
        Mod => {
            let d = b.to_num()?;
            if d == 0.0 { return Err("mod by zero".into()); }
            Val::Num(a.to_num()? % d)
        }
        Eq => Val::Bool(a.eq_val(&b)),
        Ne => Val::Bool(!a.eq_val(&b)),
        Match => glob_capture(&a.to_str(), &b.to_str()),
        Lt => Val::Bool(cmp_num(&a, &b)? < 0),
        Gt => Val::Bool(cmp_num(&a, &b)? > 0),
        Le => Val::Bool(cmp_num(&a, &b)? <= 0),
        Ge => Val::Bool(cmp_num(&a, &b)? >= 0),
        And | Or => unreachable!(),
    })
}

fn cmp_num(a: &Val, b: &Val) -> Result<i32, String> {
    if let (Val::Str(x), Val::Str(y)) = (a, b) {
        return Ok(match x.cmp(y) { std::cmp::Ordering::Less => -1, std::cmp::Ordering::Equal => 0, std::cmp::Ordering::Greater => 1 });
    }
    let x = a.to_num()?;
    let y = b.to_num()?;
    Ok(if x < y { -1 } else if x > y { 1 } else { 0 })
}

fn index(a: Val, i: Val) -> Result<Val, String> {
    match a {
        Val::List(l) => {
            let ii = i.to_num()? as i64;
            let lb = l.borrow();
            let n = lb.len() as i64;
            let k = if ii < 0 { n + ii } else { ii };
            if k < 0 || k >= n { return Ok(Val::Nil); }
            Ok(lb[k as usize].clone())
        }
        Val::Str(s) => {
            let ii = i.to_num()? as i64;
            let chars: Vec<char> = s.chars().collect();
            let n = chars.len() as i64;
            let k = if ii < 0 { n + ii } else { ii };
            if k < 0 || k >= n { return Ok(Val::Nil); }
            Ok(Val::Str(Rc::new(chars[k as usize].to_string())))
        }
        Val::Dict(d) => {
            for (k, v) in d.borrow().iter() {
                if k.eq_val(&i) { return Ok(v.clone()); }
            }
            Ok(Val::Nil)
        }
        _ => Err("not indexable".into()),
    }
}

// ---- AST mangling for #inc(path, prefix) ----
// Mangles every top-level def/assign name and every identifier that
// references one of those names. References inside function bodies that
// happen to be shadowed by parameters of the same name will also be
// mangled — a known limitation; in practice module-internal names are
// underscored and don't collide with parameters.
fn rewrite_stmts(stmts: &mut [Stmt], defs: &HashSet<String>, mangle: &impl Fn(&str) -> String) {
    for s in stmts { rewrite_stmt(s, defs, mangle); }
}

fn rewrite_stmt(s: &mut Stmt, defs: &HashSet<String>, mangle: &impl Fn(&str) -> String) {
    match s {
        Stmt::Expr(e) => rewrite_expr(e, defs, mangle),
        Stmt::Assign(n, e) => {
            if defs.contains(n) { *n = mangle(n); }
            rewrite_expr(e, defs, mangle);
        }
        Stmt::AssignIdx(a, i, v) => {
            rewrite_expr(a, defs, mangle);
            rewrite_expr(i, defs, mangle);
            rewrite_expr(v, defs, mangle);
        }
        Stmt::Print(e) | Stmt::Return(e) => rewrite_expr(e, defs, mangle),
        Stmt::If(c, t, e) => {
            rewrite_expr(c, defs, mangle);
            rewrite_stmts(t, defs, mangle);
            if let Some(eb) = e { rewrite_stmts(eb, defs, mangle); }
        }
        Stmt::Repeat(n, b) => {
            rewrite_expr(n, defs, mangle);
            rewrite_stmts(b, defs, mangle);
        }
        Stmt::For(_, it, b) => {
            rewrite_expr(it, defs, mangle);
            rewrite_stmts(b, defs, mangle);
        }
        Stmt::While(c, b) => {
            rewrite_expr(c, defs, mangle);
            rewrite_stmts(b, defs, mangle);
        }
        Stmt::Def(n, _, b) => {
            if defs.contains(n) { *n = mangle(n); }
            rewrite_stmts(b, defs, mangle);
        }
        Stmt::Break | Stmt::Continue => {}
    }
}

fn rewrite_expr(e: &mut Expr, defs: &HashSet<String>, mangle: &impl Fn(&str) -> String) {
    match e {
        Expr::Ident(n) => { if defs.contains(n) { *n = mangle(n); } }
        Expr::List(items) => { for it in items { rewrite_expr(it, defs, mangle); } }
        Expr::Dict(kvs) => {
            for (k, v) in kvs {
                rewrite_expr(k, defs, mangle);
                rewrite_expr(v, defs, mangle);
            }
        }
        Expr::Bin(_, a, b) => { rewrite_expr(a, defs, mangle); rewrite_expr(b, defs, mangle); }
        Expr::Un(_, x) => rewrite_expr(x, defs, mangle),
        Expr::Index(a, i) => { rewrite_expr(a, defs, mangle); rewrite_expr(i, defs, mangle); }
        Expr::Field(a, _) => rewrite_expr(a, defs, mangle),
        Expr::Call(f, args) => {
            rewrite_expr(f, defs, mangle);
            for a in args { rewrite_expr(a, defs, mangle); }
        }
        Expr::Tool(_, args) => { for a in args { rewrite_expr(a, defs, mangle); } }
        Expr::Llm(p, m) => {
            rewrite_expr(p, defs, mangle);
            if let Some(mm) = m { rewrite_expr(mm, defs, mangle); }
        }
        Expr::Agent(p) => rewrite_expr(p, defs, mangle),
        Expr::Lambda(_, body) => rewrite_stmts(body, defs, mangle),
        Expr::Num(_) | Expr::Str(_) | Expr::Bool(_) | Expr::Nil => {}
    }
}
