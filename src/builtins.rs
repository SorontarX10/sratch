use crate::value::Val;
use std::cell::RefCell;
use std::process::Command;
use std::rc::Rc;

pub fn call_tool(name: &str, args: &[Val]) -> Result<Val, String> {
    match name {
        // I/O
        "p" => {
            for (i, a) in args.iter().enumerate() {
                if i > 0 { print!(" "); }
                print!("{}", a);
            }
            println!();
            Ok(Val::Nil)
        }
        "in" => {
            let mut s = String::new();
            std::io::stdin().read_line(&mut s).map_err(|e| e.to_string())?;
            if s.ends_with('\n') { s.pop(); }
            if s.ends_with('\r') { s.pop(); }
            Ok(Val::Str(Rc::new(s)))
        }

        // strings / collections
        "len" => {
            let a = arg(args, 0)?;
            Ok(Val::Num(match a {
                Val::Str(s) => s.chars().count() as f64,
                Val::List(l) => l.borrow().len() as f64,
                Val::Dict(d) => d.borrow().len() as f64,
                Val::Nil => 0.0,
                _ => return Err("len: bad type".into()),
            }))
        }
        "str" => Ok(Val::Str(Rc::new(arg(args, 0)?.to_str()))),
        "num" => Ok(Val::Num(arg(args, 0)?.to_num()?)),
        "split" => {
            let s = as_str(arg(args, 0)?)?;
            let sep = as_str(arg(args, 1)?)?;
            let parts: Vec<Val> = if sep.is_empty() {
                s.chars().map(|c| Val::Str(Rc::new(c.to_string()))).collect()
            } else {
                s.split(sep.as_str()).map(|p| Val::Str(Rc::new(p.to_string()))).collect()
            };
            Ok(Val::List(Rc::new(RefCell::new(parts))))
        }
        "join" => {
            let l = as_list(arg(args, 0)?)?;
            let sep = as_str(arg(args, 1)?)?;
            let parts: Vec<String> = l.borrow().iter().map(|v| v.to_str()).collect();
            Ok(Val::Str(Rc::new(parts.join(sep.as_str()))))
        }
        "up" => Ok(Val::Str(Rc::new(as_str(arg(args, 0)?)?.to_uppercase()))),
        "lo" => Ok(Val::Str(Rc::new(as_str(arg(args, 0)?)?.to_lowercase()))),
        "trim" => Ok(Val::Str(Rc::new(as_str(arg(args, 0)?)?.trim().to_string()))),
        "has" => {
            match arg(args, 0)? {
                Val::Dict(d) => {
                    let k = arg(args, 1)?;
                    Ok(Val::Bool(d.borrow().iter().any(|(kk, _)| kk.eq_val(&k))))
                }
                Val::Str(s) => {
                    let sub = as_str(arg(args, 1)?)?;
                    Ok(Val::Bool(s.contains(sub.as_str())))
                }
                Val::List(l) => {
                    let v = arg(args, 1)?;
                    Ok(Val::Bool(l.borrow().iter().any(|x| x.eq_val(&v))))
                }
                _ => Err("has: bad type".into()),
            }
        }
        "push" => {
            let l = as_list(arg(args, 0)?)?;
            for a in &args[1..] { l.borrow_mut().push(a.clone()); }
            Ok(Val::List(l))
        }
        "pop" => {
            let l = as_list(arg(args, 0)?)?;
            let v = l.borrow_mut().pop().unwrap_or(Val::Nil);
            Ok(v)
        }
        "keys" => match arg(args, 0)? {
            Val::Dict(d) => Ok(Val::List(Rc::new(RefCell::new(
                d.borrow().iter().map(|(k, _)| k.clone()).collect()
            )))),
            _ => Err("keys: dict required".into()),
        },
        "vals" => match arg(args, 0)? {
            Val::Dict(d) => Ok(Val::List(Rc::new(RefCell::new(
                d.borrow().iter().map(|(_, v)| v.clone()).collect()
            )))),
            _ => Err("vals: dict required".into()),
        },
        "rng" => {
            let n = arg(args, 0)?.to_num()? as i64;
            let m = if args.len() > 1 { arg(args, 1)?.to_num()? as i64 } else { 0 };
            let (lo, hi) = if args.len() > 1 { (m, n) } else { (0, n) };
            let mut v = Vec::new();
            let mut i = lo;
            while i < hi { v.push(Val::Num(i as f64)); i += 1; }
            Ok(Val::List(Rc::new(RefCell::new(v))))
        }

        // files / shell / http (via curl)
        "rd" => {
            let p = as_str(arg(args, 0)?)?;
            let s = std::fs::read_to_string(p.as_str()).map_err(|e| e.to_string())?;
            Ok(Val::Str(Rc::new(s)))
        }
        "wr" => {
            let p = as_str(arg(args, 0)?)?;
            let s = as_str(arg(args, 1)?)?;
            std::fs::write(p.as_str(), s.as_str()).map_err(|e| e.to_string())?;
            Ok(Val::Nil)
        }
        "sh" => {
            let cmd = as_str(arg(args, 0)?)?;
            let out = Command::new("sh").arg("-c").arg(cmd.as_str()).output().map_err(|e| e.to_string())?;
            let mut s = String::from_utf8_lossy(&out.stdout).into_owned();
            if s.ends_with('\n') { s.pop(); }
            Ok(Val::Str(Rc::new(s)))
        }
        "get" => {
            let url = as_str(arg(args, 0)?)?;
            let out = Command::new("curl").args(["-sSL", url.as_str()]).output().map_err(|e| e.to_string())?;
            Ok(Val::Str(Rc::new(String::from_utf8_lossy(&out.stdout).into_owned())))
        }
        "post" => {
            let url = as_str(arg(args, 0)?)?;
            let body = as_str(arg(args, 1)?)?;
            let mut c = Command::new("curl");
            c.args(["-sSL", "-X", "POST", "-d", body.as_str(), url.as_str()]);
            let out = c.output().map_err(|e| e.to_string())?;
            Ok(Val::Str(Rc::new(String::from_utf8_lossy(&out.stdout).into_owned())))
        }

        // JSON (minimal: encode any Val; decode is "best-effort"-light)
        "j" => Ok(Val::Str(Rc::new(json_encode(&arg(args, 0)?)))),
        "uj" => {
            let s = as_str(arg(args, 0)?)?;
            json_decode(s.as_str())
        }

        _ => Err(format!("unknown tool #{}", name)),
    }
}

fn arg(args: &[Val], i: usize) -> Result<Val, String> {
    args.get(i).cloned().ok_or_else(|| format!("missing arg {}", i))
}

fn as_str(v: Val) -> Result<Rc<String>, String> {
    match v {
        Val::Str(s) => Ok(s),
        other => Ok(Rc::new(other.to_str())),
    }
}

fn as_list(v: Val) -> Result<Rc<RefCell<Vec<Val>>>, String> {
    match v {
        Val::List(l) => Ok(l),
        _ => Err("list required".into()),
    }
}

pub fn json_encode(v: &Val) -> String {
    match v {
        Val::Nil => "null".into(),
        Val::Bool(b) => if *b { "true".into() } else { "false".into() },
        Val::Num(n) => {
            if n.fract() == 0.0 && n.is_finite() && n.abs() < 1e16 {
                format!("{}", *n as i64)
            } else { format!("{}", n) }
        }
        Val::Str(s) => json_escape(s),
        Val::List(l) => {
            let mut out = String::from("[");
            for (i, x) in l.borrow().iter().enumerate() {
                if i > 0 { out.push(','); }
                out.push_str(&json_encode(x));
            }
            out.push(']');
            out
        }
        Val::Dict(d) => {
            let mut out = String::from("{");
            for (i, (k, val)) in d.borrow().iter().enumerate() {
                if i > 0 { out.push(','); }
                let ks = match k { Val::Str(s) => json_escape(s), other => json_escape(&other.to_str()) };
                out.push_str(&ks);
                out.push(':');
                out.push_str(&json_encode(val));
            }
            out.push('}');
            out
        }
        Val::Fn(_) => "null".into(),
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// Tiny recursive-descent JSON parser
struct JP<'a> { s: &'a [u8], p: usize }
impl<'a> JP<'a> {
    fn ws(&mut self) { while self.p < self.s.len() && self.s[self.p].is_ascii_whitespace() { self.p += 1; } }
    fn peek(&self) -> u8 { *self.s.get(self.p).unwrap_or(&0) }
    fn val(&mut self) -> Result<Val, String> {
        self.ws();
        match self.peek() {
            b'{' => self.obj(),
            b'[' => self.arr(),
            b'"' => self.str_().map(|s| Val::Str(Rc::new(s))),
            b't' => { self.p += 4; Ok(Val::Bool(true)) }
            b'f' => { self.p += 5; Ok(Val::Bool(false)) }
            b'n' => { self.p += 4; Ok(Val::Nil) }
            _ => self.num(),
        }
    }
    fn str_(&mut self) -> Result<String, String> {
        self.p += 1;
        let mut out = String::new();
        while self.p < self.s.len() && self.s[self.p] != b'"' {
            if self.s[self.p] == b'\\' {
                self.p += 1;
                let e = self.s[self.p]; self.p += 1;
                match e {
                    b'n' => out.push('\n'),
                    b't' => out.push('\t'),
                    b'r' => out.push('\r'),
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'u' => {
                        let hex = std::str::from_utf8(&self.s[self.p..self.p+4]).unwrap_or("0000");
                        self.p += 4;
                        if let Ok(n) = u32::from_str_radix(hex, 16) {
                            if let Some(c) = char::from_u32(n) { out.push(c); }
                        }
                    }
                    other => out.push(other as char),
                }
            } else {
                out.push(self.s[self.p] as char);
                self.p += 1;
            }
        }
        self.p += 1;
        Ok(out)
    }
    fn num(&mut self) -> Result<Val, String> {
        let start = self.p;
        if self.peek() == b'-' { self.p += 1; }
        while self.p < self.s.len() && (self.s[self.p].is_ascii_digit() || matches!(self.s[self.p], b'.' | b'e' | b'E' | b'+' | b'-')) {
            self.p += 1;
        }
        let s = std::str::from_utf8(&self.s[start..self.p]).map_err(|e| e.to_string())?;
        Ok(Val::Num(s.parse().map_err(|_| format!("bad num {}", s))?))
    }
    fn arr(&mut self) -> Result<Val, String> {
        self.p += 1;
        let mut v = Vec::new();
        self.ws();
        if self.peek() == b']' { self.p += 1; return Ok(Val::List(Rc::new(RefCell::new(v)))); }
        loop {
            v.push(self.val()?);
            self.ws();
            if self.peek() == b',' { self.p += 1; continue; }
            if self.peek() == b']' { self.p += 1; break; }
            return Err("json: expected , or ]".into());
        }
        Ok(Val::List(Rc::new(RefCell::new(v))))
    }
    fn obj(&mut self) -> Result<Val, String> {
        self.p += 1;
        let mut d = Vec::new();
        self.ws();
        if self.peek() == b'}' { self.p += 1; return Ok(Val::Dict(Rc::new(RefCell::new(d)))); }
        loop {
            self.ws();
            let k = self.str_()?;
            self.ws();
            if self.peek() != b':' { return Err("json: expected :".into()); }
            self.p += 1;
            let v = self.val()?;
            d.push((Val::Str(Rc::new(k)), v));
            self.ws();
            if self.peek() == b',' { self.p += 1; continue; }
            if self.peek() == b'}' { self.p += 1; break; }
            return Err("json: expected , or }".into());
        }
        Ok(Val::Dict(Rc::new(RefCell::new(d))))
    }
}

fn json_decode(s: &str) -> Result<Val, String> {
    JP { s: s.as_bytes(), p: 0 }.val()
}
