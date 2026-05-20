use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Tok {
    Num(f64),
    Str(String),
    Ident(String),
    Plus, Minus, Star, Slash, Percent,
    Eq, EqEq, BangEq, Lt, Gt, Le, Ge,
    Amp, Pipe, Bang,
    LP, RP, LBr, RBr, LBk, RBk,
    Comma, Semi, Colon, Dot, Nl,
    Caret,    // ^  return
    Quest,    // ?  if
    At,       // @  llm
    Hash,     // #  tool
    Gtt,      // >  print
    StarQ,    // *? while
    Eof,
}

impl fmt::Display for Tok {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

pub struct Lexer<'a> {
    src: &'a [u8],
    pos: usize,
}

impl<'a> Lexer<'a> {
    pub fn new(src: &'a str) -> Self {
        Self { src: src.as_bytes(), pos: 0 }
    }

    fn peek(&self, off: usize) -> u8 {
        *self.src.get(self.pos + off).unwrap_or(&0)
    }

    fn bump(&mut self) -> u8 {
        let c = self.peek(0);
        self.pos += 1;
        c
    }

    fn skip_inline_ws(&mut self) {
        loop {
            match self.peek(0) {
                b' ' | b'\t' | b'\r' => { self.pos += 1; }
                b'\'' => {
                    while self.peek(0) != 0 && self.peek(0) != b'\n' { self.pos += 1; }
                }
                _ => break,
            }
        }
    }

    fn read_string(&mut self) -> Result<String, String> {
        self.bump();
        let mut s = String::new();
        loop {
            let c = self.peek(0);
            if c == 0 { return Err("unterminated string".into()); }
            if c == b'"' { self.bump(); break; }
            if c == b'\\' {
                self.bump();
                let esc = self.bump();
                match esc {
                    b'n' => s.push('\n'),
                    b't' => s.push('\t'),
                    b'r' => s.push('\r'),
                    b'\\' => s.push('\\'),
                    b'"' => s.push('"'),
                    b'0' => s.push('\0'),
                    other => s.push(other as char),
                }
            } else {
                s.push(c as char);
                self.bump();
            }
        }
        Ok(s)
    }

    fn read_number(&mut self) -> f64 {
        let start = self.pos;
        while self.peek(0).is_ascii_digit() { self.bump(); }
        if self.peek(0) == b'.' && self.peek(1).is_ascii_digit() {
            self.bump();
            while self.peek(0).is_ascii_digit() { self.bump(); }
        }
        let s = std::str::from_utf8(&self.src[start..self.pos]).unwrap();
        s.parse().unwrap_or(0.0)
    }

    fn read_ident(&mut self) -> String {
        let start = self.pos;
        while {
            let c = self.peek(0);
            c == b'_' || c.is_ascii_alphanumeric()
        } { self.bump(); }
        std::str::from_utf8(&self.src[start..self.pos]).unwrap().to_string()
    }

    pub fn tokens(mut self) -> Result<Vec<Tok>, String> {
        let mut out = Vec::new();
        loop {
            self.skip_inline_ws();
            let c = self.peek(0);
            if c == 0 { break; }
            let t = match c {
                b'\n' => { self.bump(); Tok::Nl }
                b'+' => { self.bump(); Tok::Plus }
                b'-' => { self.bump(); Tok::Minus }
                b'/' => { self.bump(); Tok::Slash }
                b'%' => { self.bump(); Tok::Percent }
                b'(' => { self.bump(); Tok::LP }
                b')' => { self.bump(); Tok::RP }
                b'{' => { self.bump(); Tok::LBr }
                b'}' => { self.bump(); Tok::RBr }
                b'[' => { self.bump(); Tok::LBk }
                b']' => { self.bump(); Tok::RBk }
                b',' => { self.bump(); Tok::Comma }
                b';' => { self.bump(); Tok::Semi }
                b':' => { self.bump(); Tok::Colon }
                b'.' => { self.bump(); Tok::Dot }
                b'^' => { self.bump(); Tok::Caret }
                b'?' => { self.bump(); Tok::Quest }
                b'@' => { self.bump(); Tok::At }
                b'#' => { self.bump(); Tok::Hash }
                b'>' => {
                    self.bump();
                    if self.peek(0) == b'=' { self.bump(); Tok::Ge } else { Tok::Gtt }
                }
                b'<' => {
                    self.bump();
                    if self.peek(0) == b'=' { self.bump(); Tok::Le } else { Tok::Lt }
                }
                b'=' => {
                    self.bump();
                    if self.peek(0) == b'=' { self.bump(); Tok::EqEq } else { Tok::Eq }
                }
                b'!' => {
                    self.bump();
                    if self.peek(0) == b'=' { self.bump(); Tok::BangEq } else { Tok::Bang }
                }
                b'&' => { self.bump(); Tok::Amp }
                b'|' => { self.bump(); Tok::Pipe }
                b'*' => {
                    self.bump();
                    if self.peek(0) == b'?' { self.bump(); Tok::StarQ } else { Tok::Star }
                }
                b'"' => Tok::Str(self.read_string()?),
                c if c.is_ascii_digit() => Tok::Num(self.read_number()),
                c if c == b'_' || c.is_ascii_alphabetic() => {
                    let s = self.read_ident();
                    // 'g' (Gtt) is the > sigil only, identifiers stay literal here
                    Tok::Ident(s)
                }
                other => return Err(format!("unexpected char {:?}", other as char)),
            };
            out.push(t);
        }
        out.push(Tok::Eof);
        Ok(out)
    }
}
