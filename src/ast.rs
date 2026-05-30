#[derive(Debug, Clone)]
pub enum Expr {
    Num(f64),
    Str(String),
    Bool(bool),
    Nil,
    Ident(String),
    List(Vec<Expr>),
    Dict(Vec<(Expr, Expr)>),
    Bin(BinOp, Box<Expr>, Box<Expr>),
    Un(UnOp, Box<Expr>),
    Index(Box<Expr>, Box<Expr>),
    Field(Box<Expr>, String),
    Call(Box<Expr>, Vec<Expr>),   // f(args) — f may be Ident or computed
    Tool(String, Vec<Expr>),      // #name(args)
    Llm(Box<Expr>, Option<Box<Expr>>), // @prompt or @prompt %model
    Agent(Box<Expr>),             // ~prompt — run full ReAct loop, return DONE text
    Lambda(Vec<String>, Vec<Stmt>), // :(a,b){...} — anonymous closure
}

#[derive(Debug, Clone)]
pub enum Stmt {
    Expr(Expr),
    Assign(String, Expr),
    AssignIdx(Expr, Expr, Expr),
    Print(Expr),
    Return(Expr),
    If(Expr, Vec<Stmt>, Option<Vec<Stmt>>),
    Repeat(Expr, Vec<Stmt>),                // *n{..}
    For(String, Expr, Vec<Stmt>),           // *x:list{..}
    While(Expr, Vec<Stmt>),                 // *?cond{..}
    Def(String, Vec<String>, Vec<Stmt>),    // :f(a,b){..}
    Break,
    Continue,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp { Add, Sub, Mul, Div, Mod, Eq, Ne, Lt, Gt, Le, Ge, And, Or, Match }

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UnOp { Neg, Not }
