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
    /// Captured environment for closures (lambdas). Snapshot of the
    /// variables visible where the function was created. `None` for
    /// ordinary named defs, which resolve free names globally.
    pub captured: Option<HashMap<String, Val>>,
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
    /// Stack of scope indices that begin a function call. `set` only walks
    /// scopes up to (but not crossing) the current barrier — this gives
    /// proper lexical scoping inside function bodies so that a variable
    /// named `x` in an inner function does not silently mutate a caller's
    /// `x`. The outermost scope (index 0) is still treated as global and
    /// is always writable when an existing binding lives there; this
    /// preserves the common pattern of "init at top level, mutate from
    /// helpers."
    pub fn_barriers: Vec<usize>,
}

impl Env {
    pub fn new() -> Self {
        Self { scopes: vec![HashMap::new()], fn_barriers: Vec::new() }
    }
    pub fn push(&mut self) { self.scopes.push(HashMap::new()); }
    pub fn pop(&mut self) { self.scopes.pop(); }

    pub fn enter_fn(&mut self) {
        self.fn_barriers.push(self.scopes.len());
        self.scopes.push(HashMap::new());
    }

    pub fn leave_fn(&mut self) {
        self.fn_barriers.pop();
        self.scopes.pop();
    }

    /// Flatten currently-visible bindings (inner scopes win) into one map.
    /// Used to capture a closure's environment at creation time. Excludes
    /// the global scope (index 0) — globals stay resolvable at call time.
    pub fn snapshot(&self) -> HashMap<String, Val> {
        let mut out = HashMap::new();
        for s in self.scopes.iter().skip(1) {
            for (k, v) in s.iter() {
                out.insert(k.clone(), v.clone());
            }
        }
        out
    }

    pub fn get(&self, n: &str) -> Option<Val> {
        for s in self.scopes.iter().rev() {
            if let Some(v) = s.get(n) { return Some(v.clone()); }
        }
        None
    }

    pub fn set(&mut self, n: &str, v: Val) {
        let barrier = *self.fn_barriers.last().unwrap_or(&0);
        // walk inner-to-outer within the current function frame
        for i in (barrier..self.scopes.len()).rev() {
            if self.scopes[i].contains_key(n) {
                self.scopes[i].insert(n.to_string(), v);
                return;
            }
        }
        // if we're inside a function, fall through to the global scope
        // so that pre-declared globals stay mutable from anywhere
        if barrier > 0 && self.scopes[0].contains_key(n) {
            self.scopes[0].insert(n.to_string(), v);
            return;
        }
        // otherwise create a new binding in the innermost scope
        self.scopes.last_mut().unwrap().insert(n.to_string(), v);
    }

    pub fn set_local(&mut self, n: &str, v: Val) {
        self.scopes.last_mut().unwrap().insert(n.to_string(), v);
    }
}
