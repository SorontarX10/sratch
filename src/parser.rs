use crate::ast::*;
use crate::lexer::Tok;

pub struct Parser {
    toks: Vec<Tok>,
    pos: usize,
}

impl Parser {
    pub fn new(toks: Vec<Tok>) -> Self { Self { toks, pos: 0 } }

    fn peek(&self) -> &Tok { &self.toks[self.pos] }
    fn peek2(&self) -> &Tok { self.toks.get(self.pos + 1).unwrap_or(&Tok::Eof) }
    fn bump(&mut self) -> Tok { let t = self.toks[self.pos].clone(); self.pos += 1; t }
    fn eat(&mut self, t: &Tok) -> bool {
        if std::mem::discriminant(self.peek()) == std::mem::discriminant(t) { self.bump(); true } else { false }
    }
    fn expect(&mut self, t: &Tok) -> Result<(), String> {
        if self.eat(t) { Ok(()) } else { Err(format!("expected {:?}, got {:?}", t, self.peek())) }
    }

    fn skip_nl(&mut self) { while matches!(self.peek(), Tok::Nl | Tok::Semi) { self.pos += 1; } }

    pub fn program(&mut self) -> Result<Vec<Stmt>, String> {
        let mut out = Vec::new();
        self.skip_nl();
        while !matches!(self.peek(), Tok::Eof) {
            let s = self.stmt()?;
            out.push(s);
            self.skip_nl();
        }
        Ok(out)
    }

    fn block(&mut self) -> Result<Vec<Stmt>, String> {
        self.expect(&Tok::LBr)?;
        let mut out = Vec::new();
        self.skip_nl();
        while !matches!(self.peek(), Tok::RBr | Tok::Eof) {
            let s = self.stmt()?;
            out.push(s);
            self.skip_nl();
        }
        self.expect(&Tok::RBr)?;
        Ok(out)
    }

    fn stmt(&mut self) -> Result<Stmt, String> {
        match self.peek() {
            Tok::Gtt => { self.bump(); let e = self.expr()?; Ok(Stmt::Print(e)) }
            Tok::Caret => { self.bump(); let e = self.expr()?; Ok(Stmt::Return(e)) }
            Tok::Quest => self.parse_if(),
            Tok::Star => self.parse_loop(false),
            Tok::StarQ => self.parse_loop(true),
            Tok::Colon => self.parse_def(),
            Tok::Ident(name) if matches!(self.peek2(), Tok::Eq) => {
                let n = name.clone();
                self.bump(); self.bump();
                let e = self.expr()?;
                Ok(Stmt::Assign(n, e))
            }
            Tok::Ident(n) if n == "brk" => { self.bump(); Ok(Stmt::Break) }
            Tok::Ident(n) if n == "cnt" => { self.bump(); Ok(Stmt::Continue) }
            _ => {
                let e = self.expr()?;
                if let Tok::Eq = self.peek() {
                    if let Expr::Index(arr, idx) = e.clone() {
                        self.bump();
                        let v = self.expr()?;
                        return Ok(Stmt::AssignIdx(*arr, *idx, v));
                    }
                }
                Ok(Stmt::Expr(e))
            }
        }
    }

    fn parse_if(&mut self) -> Result<Stmt, String> {
        self.bump();
        let c = self.expr()?;
        let t = self.block()?;
        self.skip_nl();
        let e = if matches!(self.peek(), Tok::Colon) && matches!(self.peek2(), Tok::LBr) {
            self.bump();
            Some(self.block()?)
        } else { None };
        Ok(Stmt::If(c, t, e))
    }

    fn parse_loop(&mut self, is_while: bool) -> Result<Stmt, String> {
        self.bump();
        if is_while {
            let c = self.expr()?;
            let b = self.block()?;
            return Ok(Stmt::While(c, b));
        }
        // *n{..}  or  *x:expr{..}
        if let (Tok::Ident(n), Tok::Colon) = (self.peek().clone(), self.peek2().clone()) {
            self.bump(); self.bump();
            let it = self.expr()?;
            let b = self.block()?;
            return Ok(Stmt::For(n, it, b));
        }
        let n = self.expr()?;
        let b = self.block()?;
        Ok(Stmt::Repeat(n, b))
    }

    fn parse_def(&mut self) -> Result<Stmt, String> {
        self.bump();
        let name = if let Tok::Ident(n) = self.bump() { n } else { return Err("def: name expected".into()); };
        self.expect(&Tok::LP)?;
        let mut params = Vec::new();
        if !matches!(self.peek(), Tok::RP) {
            loop {
                if let Tok::Ident(n) = self.bump() { params.push(n); } else { return Err("def: param ident".into()); }
                if !self.eat(&Tok::Comma) { break; }
            }
        }
        self.expect(&Tok::RP)?;
        let body = self.block()?;
        Ok(Stmt::Def(name, params, body))
    }

    // Pratt-ish expression parsing
    fn expr(&mut self) -> Result<Expr, String> { self.parse_or() }

    fn parse_or(&mut self) -> Result<Expr, String> {
        let mut l = self.parse_and()?;
        while matches!(self.peek(), Tok::Pipe) {
            self.bump();
            let r = self.parse_and()?;
            l = Expr::Bin(BinOp::Or, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn parse_and(&mut self) -> Result<Expr, String> {
        let mut l = self.parse_cmp()?;
        while matches!(self.peek(), Tok::Amp) {
            self.bump();
            let r = self.parse_cmp()?;
            l = Expr::Bin(BinOp::And, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn parse_cmp(&mut self) -> Result<Expr, String> {
        let l = self.parse_add()?;
        let op = match self.peek() {
            Tok::EqEq => BinOp::Eq, Tok::BangEq => BinOp::Ne,
            Tok::Lt => BinOp::Lt, Tok::Gtt => BinOp::Gt,
            Tok::Le => BinOp::Le, Tok::Ge => BinOp::Ge,
            _ => return Ok(l),
        };
        self.bump();
        let r = self.parse_add()?;
        Ok(Expr::Bin(op, Box::new(l), Box::new(r)))
    }
    fn parse_add(&mut self) -> Result<Expr, String> {
        let mut l = self.parse_mul()?;
        loop {
            let op = match self.peek() {
                Tok::Plus => BinOp::Add, Tok::Minus => BinOp::Sub,
                _ => break,
            };
            self.bump();
            let r = self.parse_mul()?;
            l = Expr::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn parse_mul(&mut self) -> Result<Expr, String> {
        let mut l = self.parse_unary()?;
        loop {
            let op = match self.peek() {
                Tok::Star => BinOp::Mul, Tok::Slash => BinOp::Div, Tok::Percent => BinOp::Mod,
                _ => break,
            };
            self.bump();
            let r = self.parse_unary()?;
            l = Expr::Bin(op, Box::new(l), Box::new(r));
        }
        Ok(l)
    }
    fn parse_unary(&mut self) -> Result<Expr, String> {
        match self.peek() {
            Tok::Minus => { self.bump(); let e = self.parse_unary()?; Ok(Expr::Un(UnOp::Neg, Box::new(e))) }
            Tok::Bang => { self.bump(); let e = self.parse_unary()?; Ok(Expr::Un(UnOp::Not, Box::new(e))) }
            _ => self.parse_postfix(),
        }
    }
    fn parse_postfix(&mut self) -> Result<Expr, String> {
        let mut e = self.parse_atom()?;
        loop {
            match self.peek() {
                Tok::LBk => {
                    self.bump();
                    let i = self.expr()?;
                    self.expect(&Tok::RBk)?;
                    e = Expr::Index(Box::new(e), Box::new(i));
                }
                Tok::LP => {
                    self.bump();
                    let mut args = Vec::new();
                    if !matches!(self.peek(), Tok::RP) {
                        loop {
                            args.push(self.expr()?);
                            if !self.eat(&Tok::Comma) { break; }
                        }
                    }
                    self.expect(&Tok::RP)?;
                    e = Expr::Call(Box::new(e), args);
                }
                Tok::Dot => {
                    self.bump();
                    if let Tok::Ident(n) = self.bump() {
                        e = Expr::Field(Box::new(e), n);
                    } else { return Err("expected ident after .".into()); }
                }
                _ => break,
            }
        }
        Ok(e)
    }
    fn parse_atom(&mut self) -> Result<Expr, String> {
        match self.peek().clone() {
            Tok::Num(n) => { self.bump(); Ok(Expr::Num(n)) }
            Tok::Str(s) => { self.bump(); Ok(Expr::Str(s)) }
            Tok::Ident(n) => { self.bump(); Ok(Expr::Ident(n)) }
            Tok::LP => { self.bump(); let e = self.expr()?; self.expect(&Tok::RP)?; Ok(e) }
            Tok::LBk => self.parse_list(),
            Tok::LBr => self.parse_dict(),
            Tok::At => {
                self.bump();
                let p = self.parse_unary()?;
                let m = if matches!(self.peek(), Tok::Percent) {
                    self.bump();
                    Some(Box::new(self.parse_unary()?))
                } else { None };
                Ok(Expr::Llm(Box::new(p), m))
            }
            Tok::Tilde => {
                self.bump();
                let e = self.parse_unary()?;
                Ok(Expr::Agent(Box::new(e)))
            }
            Tok::Hash => {
                self.bump();
                let name = if let Tok::Ident(n) = self.bump() { n } else { return Err("#name expected".into()); };
                let mut args = Vec::new();
                if self.eat(&Tok::LP) {
                    if !matches!(self.peek(), Tok::RP) {
                        loop {
                            args.push(self.expr()?);
                            if !self.eat(&Tok::Comma) { break; }
                        }
                    }
                    self.expect(&Tok::RP)?;
                }
                Ok(Expr::Tool(name, args))
            }
            other => Err(format!("unexpected token {:?}", other)),
        }
    }

    fn parse_list(&mut self) -> Result<Expr, String> {
        self.expect(&Tok::LBk)?;
        let mut items = Vec::new();
        self.skip_nl();
        while !matches!(self.peek(), Tok::RBk) {
            items.push(self.expr()?);
            self.skip_nl();
            if !self.eat(&Tok::Comma) { break; }
            self.skip_nl();
        }
        self.expect(&Tok::RBk)?;
        Ok(Expr::List(items))
    }

    fn parse_dict(&mut self) -> Result<Expr, String> {
        self.expect(&Tok::LBr)?;
        let mut items = Vec::new();
        self.skip_nl();
        while !matches!(self.peek(), Tok::RBr) {
            let k = self.expr()?;
            self.expect(&Tok::Colon)?;
            let v = self.expr()?;
            items.push((k, v));
            self.skip_nl();
            if !self.eat(&Tok::Comma) { break; }
            self.skip_nl();
        }
        self.expect(&Tok::RBr)?;
        Ok(Expr::Dict(items))
    }
}
