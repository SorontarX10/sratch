use std::cell::RefCell;
use std::collections::HashMap;
use std::fmt;
use std::rc::Rc;

use crate::ast::Stmt;

#[derive(Clone)]
pub enum Val {
    Nil,
    Num(f64),
    Bool(bool),
    Str(Rc<String>),
    List(Rc<RefCell<Vec<Val>>>),
    Dict(Rc<RefCell<Vec<(Val, Val)>>>),
    Fn(Rc<Fun>),
}

pub struct Fun {
    pub name: String,
    pub params: Vec<String>,
    pub body: Vec<Stmt>,
}

impl Val {
    pub fn truthy(&self) -> bool {
        match self {
            Val::Nil => false,
            Val::Bool(b) => *b,
            Val::Num(n) => *n != 0.0,
            Val::Str(s) => !s.is_empty(),
            Val::List(l) => !l.borrow().is_empty(),
            Val::Dict(d) => !d.borrow().is_empty(),
            Val::Fn(_) => true,
        }
    }

    pub fn to_num(&self) -> Result<f64, String> {
        match self {
            Val::Num(n) => Ok(*n),
            Val::Bool(b) => Ok(if *b { 1.0 } else { 0.0 }),
            Val::Str(s) => s.parse().map_err(|_| format!("cannot parse number from {:?}", s)),
            Val::Nil => Ok(0.0),
            _ => Err("not a number".into()),
        }
    }

    pub fn to_str(&self) -> String { format!("{}", self) }

    pub fn eq_val(&self, other: &Val) -> bool {
        match (self, other) {
            (Val::Nil, Val::Nil) => true,
            (Val::Bool(a), Val::Bool(b)) => a == b,
            (Val::Num(a), Val::Num(b)) => a == b,
            (Val::Str(a), Val::Str(b)) => a == b,
            (Val::List(a), Val::List(b)) => Rc::ptr_eq(a, b)
                || {
                    let a = a.borrow();
                    let b = b.borrow();
                    a.len() == b.len() && a.iter().zip(b.iter()).all(|(x, y)| x.eq_val(y))
                },
            _ => false,
        }
    }
}

impl fmt::Display for Val {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Val::Nil => write!(f, "n"),
            Val::Bool(b) => write!(f, "{}", if *b { "t" } else { "f" }),
            Val::Num(n) => {
                if n.fract() == 0.0 && n.is_finite() && n.abs() < 1e16 {
                    write!(f, "{}", *n as i64)
                } else {
                    write!(f, "{}", n)
                }
            }
            Val::Str(s) => write!(f, "{}", s),
            Val::List(l) => {
                write!(f, "[")?;
                for (i, v) in l.borrow().iter().enumerate() {
                    if i > 0 { write!(f, ",")?; }
                    write!(f, "{}", v)?;
                }
                write!(f, "]")
            }
            Val::Dict(d) => {
                write!(f, "{{")?;
                for (i, (k, v)) in d.borrow().iter().enumerate() {
                    if i > 0 { write!(f, ",")?; }
                    write!(f, "{}:{}", k, v)?;
                }
                write!(f, "}}")
            }
            Val::Fn(fun) => write!(f, ":{}", fun.name),
        }
    }
}

#[derive(Default)]
pub struct Env {
    pub scopes: Vec<HashMap<String, Val>>,
}

impl Env {
    pub fn new() -> Self { Self { scopes: vec![HashMap::new()] } }
    pub fn push(&mut self) { self.scopes.push(HashMap::new()); }
    pub fn pop(&mut self) { self.scopes.pop(); }

    pub fn get(&self, n: &str) -> Option<Val> {
        for s in self.scopes.iter().rev() {
            if let Some(v) = s.get(n) { return Some(v.clone()); }
        }
        None
    }

    pub fn set(&mut self, n: &str, v: Val) {
        for s in self.scopes.iter_mut().rev() {
            if s.contains_key(n) { s.insert(n.to_string(), v); return; }
        }
        self.scopes.last_mut().unwrap().insert(n.to_string(), v);
    }

    pub fn set_local(&mut self, n: &str, v: Val) {
        self.scopes.last_mut().unwrap().insert(n.to_string(), v);
    }
}
