#!/usr/bin/env python3
"""py2sra: pattern-based Python -> Sratch transpiler.

Uses Python's own ast module as the front-end (no need to reimplement
Python parsing in Sratch). Compresses recognized agent idioms:

  Anthropic SDK chain            -> @prompt  /  @[u,a,u]
  subprocess.run([...]).stdout   -> #sh(cmd)
  urllib.request.urlopen.read.decode -> #get(url)
  print(x)                       -> >x
  len/str/int/float/range        -> #len/#str/#num/#num/#rng
  x.append(y)/split/strip/...    -> #push/#split/#trim/...

General code (control flow, functions, expressions) translates 1:1.
Unhandled constructs become /*?NodeName*/ markers — easy to grep.

Usage:
  python3 tools/py2sra.py < input.py            # stdin -> stdout
  python3 tools/py2sra.py file.py               # file  -> stdout
"""
import ast
import sys


class P2S:
    def __init__(self):
        self.indent = 0
        self.clients = set()  # variable names bound to Anthropic()

    def transpile(self, src):
        tree = ast.parse(src)
        self._scan(tree)
        return "\n".join(s for s in (self.stmt(x) for x in tree.body) if s is not None)

    def _scan(self, tree):
        for n in ast.walk(tree):
            if (isinstance(n, ast.Assign)
                and isinstance(n.value, ast.Call)
                and isinstance(n.value.func, ast.Name)
                and n.value.func.id == "Anthropic"):
                for t in n.targets:
                    if isinstance(t, ast.Name):
                        self.clients.add(t.id)

    def _i(self): return "  " * self.indent

    def _body(self, stmts):
        self.indent += 1
        lines = []
        for s in stmts:
            r = self.stmt(s)
            if r is not None:
                lines.append(self._i() + r)
        self.indent -= 1
        return "\n".join(lines) + ("\n" if lines else "")

    # ---- statements ----

    def stmt(self, n):
        if isinstance(n, (ast.Import, ast.ImportFrom)):
            return None
        if isinstance(n, ast.Assign):
            # drop "c = Anthropic()"
            if (isinstance(n.value, ast.Call)
                and isinstance(n.value.func, ast.Name)
                and n.value.func.id == "Anthropic"):
                return None
            tgt = self.expr(n.targets[0])
            return f"{tgt}={self.expr(n.value)}"
        if isinstance(n, ast.AugAssign):
            t = self.expr(n.target)
            return f"{t}={t}{self._op(n.op)}{self.expr(n.value)}"
        if isinstance(n, ast.Expr):
            v = n.value
            # print(...) -> >...
            if (isinstance(v, ast.Call)
                and isinstance(v.func, ast.Name)
                and v.func.id == "print"
                and len(v.args) == 1
                and not v.keywords):
                return f">{self.expr(v.args[0])}"
            return self.expr(v)
        if isinstance(n, ast.Return):
            return f"^{self.expr(n.value) if n.value else 'N'}"
        if isinstance(n, ast.FunctionDef):
            params = ",".join(a.arg for a in n.args.args)
            return f":{n.name}({params}){{\n{self._body(n.body)}{self._i()}}}"
        if isinstance(n, ast.If):
            return self._if(n)
        if isinstance(n, ast.For):
            return self._for(n)
        if isinstance(n, ast.While):
            return f"*?{self.expr(n.test)}{{\n{self._body(n.body)}{self._i()}}}"
        if isinstance(n, ast.Break):    return "brk"
        if isinstance(n, ast.Continue): return "cnt"
        if isinstance(n, ast.Pass):     return None
        if isinstance(n, ast.With):
            # ignore the context manager; emit body inline
            return self._body(n.body).rstrip()
        return f"/*?stmt:{type(n).__name__}*/"

    def _if(self, n):
        out = f"?{self.expr(n.test)}{{\n{self._body(n.body)}{self._i()}}}"
        if n.orelse:
            # elif chain → nested if in else block (Sratch lacks elif)
            if len(n.orelse) == 1 and isinstance(n.orelse[0], ast.If):
                self.indent += 1
                inner = self._i() + self.stmt(n.orelse[0])
                self.indent -= 1
                out += f":{{\n{inner}\n{self._i()}}}"
            else:
                out += f":{{\n{self._body(n.orelse)}{self._i()}}}"
        return out

    def _for(self, n):
        # for x in range(N): ... -> *N{} (i=counter) or *x:N{}
        if (isinstance(n.iter, ast.Call)
            and isinstance(n.iter.func, ast.Name)
            and n.iter.func.id == "range"
            and len(n.iter.args) == 1
            and isinstance(n.target, ast.Name)):
            n_arg = self.expr(n.iter.args[0])
            body = self._body(n.body)
            if n.target.id in ("i", "_"):
                return f"*{n_arg}{{\n{body}{self._i()}}}"
            return f"*{n.target.id}:{n_arg}{{\n{body}{self._i()}}}"
        # for x in iterable: ... -> *x:iter{...}
        if isinstance(n.target, ast.Name):
            return f"*{n.target.id}:{self.expr(n.iter)}{{\n{self._body(n.body)}{self._i()}}}"
        return f"/*?for:{ast.dump(n.target)}*/"

    # ---- expressions ----

    def expr(self, n):
        # Priority: detect agent chains before generic dispatch
        r = self._llm_chain(n)
        if r is not None: return r
        r = self._shell_chain(n)
        if r is not None: return r
        r = self._get_chain(n)
        if r is not None: return r
        m = getattr(self, f"e_{type(n).__name__}", None)
        return m(n) if m else f"/*?{type(n).__name__}*/"

    def _llm_chain(self, n):
        # ...messages.create(...).content[0].text
        if not (isinstance(n, ast.Attribute) and n.attr == "text"): return None
        sub = n.value
        if not isinstance(sub, ast.Subscript): return None
        attr = sub.value
        if not (isinstance(attr, ast.Attribute) and attr.attr == "content"): return None
        return self._llm_to_at(attr.value)

    def _llm_to_at(self, call):
        if not isinstance(call, ast.Call): return None
        if not (isinstance(call.func, ast.Attribute) and call.func.attr == "create"):
            return None
        if not (isinstance(call.func.value, ast.Attribute) and call.func.value.attr == "messages"):
            return None
        base = call.func.value.value
        is_client = (
            (isinstance(base, ast.Name) and base.id in self.clients)
            or (isinstance(base, ast.Call) and isinstance(base.func, ast.Name)
                and base.func.id == "Anthropic")
        )
        if not is_client: return None
        messages = model = None
        for kw in call.keywords:
            if kw.arg == "messages": messages = kw.value
            elif kw.arg == "model":  model = kw.value
        if messages is None or not isinstance(messages, ast.List): return None
        contents = []
        for elt in messages.elts:
            if not isinstance(elt, ast.Dict): return None
            content = None
            for k, v in zip(elt.keys, elt.values):
                if isinstance(k, ast.Constant) and k.value == "content":
                    content = v
                    break
            if content is None: return None
            contents.append(self.expr(content))
        if len(contents) == 1:
            res = f"@{contents[0]}"
        else:
            res = f"@[{','.join(contents)}]"
        if model is not None:
            m_str = self.expr(model)
            # Drop the default model spec — Sratch's @ defaults to it.
            if m_str != '"claude-haiku-4-5"':
                res += f" %{m_str}"
        return res

    def _shell_chain(self, n):
        # subprocess.run(['bash','-c', cmd], ...).stdout
        if not (isinstance(n, ast.Attribute) and n.attr == "stdout"): return None
        call = n.value
        if not (isinstance(call, ast.Call)
                and isinstance(call.func, ast.Attribute)
                and call.func.attr == "run"
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "subprocess"
                and call.args):
            return None
        a0 = call.args[0]
        if (isinstance(a0, ast.List) and len(a0.elts) >= 3
            and isinstance(a0.elts[0], ast.Constant) and a0.elts[0].value == "bash"
            and isinstance(a0.elts[1], ast.Constant) and a0.elts[1].value == "-c"):
            return f"#sh({self.expr(a0.elts[2])})"
        return f"#sh({self.expr(a0)})"

    def _get_chain(self, n):
        # urllib.request.urlopen(url).read().decode()
        if not (isinstance(n, ast.Call)
                and isinstance(n.func, ast.Attribute)
                and n.func.attr == "decode"): return None
        rd = n.func.value
        if not (isinstance(rd, ast.Call)
                and isinstance(rd.func, ast.Attribute)
                and rd.func.attr == "read"): return None
        u = rd.func.value
        if not (isinstance(u, ast.Call)
                and isinstance(u.func, ast.Attribute)
                and u.func.attr == "urlopen"
                and u.args): return None
        return f"#get({self.expr(u.args[0])})"

    def e_Constant(self, n):
        v = n.value
        if v is None: return "N"
        if v is True: return "T"
        if v is False: return "F"
        if isinstance(v, str):
            return '"' + v.replace("\\", "\\\\").replace('"', '\\"') \
                          .replace("\n", "\\n").replace("\t", "\\t") \
                          .replace("\r", "\\r") + '"'
        return str(v)

    def e_Name(self, n):
        if n.id == "True": return "T"
        if n.id == "False": return "F"
        if n.id == "None": return "N"
        return n.id

    def e_BinOp(self, n):
        return f"({self.expr(n.left)}{self._op(n.op)}{self.expr(n.right)})"

    def e_BoolOp(self, n):
        op = "&" if isinstance(n.op, ast.And) else "|"
        return "(" + op.join(self.expr(v) for v in n.values) + ")"

    def e_UnaryOp(self, n):
        if isinstance(n.op, ast.USub): return f"(-{self.expr(n.operand)})"
        if isinstance(n.op, ast.Not):  return f"!{self.expr(n.operand)}"
        return "/*?un*/"

    def e_Compare(self, n):
        l = self.expr(n.left)
        if len(n.ops) == 1 and isinstance(n.ops[0], (ast.In, ast.NotIn)):
            r = self.expr(n.comparators[0])
            return f"#has({r},{l})" if isinstance(n.ops[0], ast.In) else f"!#has({r},{l})"
        ops = "".join(self._cmp(o) for o in n.ops)
        rs  = "".join(self.expr(c) for c in n.comparators)
        return f"({l}{ops}{rs})"

    def e_Call(self, n):
        # Plain builtins -> # tools
        if isinstance(n.func, ast.Name):
            m = {"len": "len", "str": "str", "int": "num", "float": "num", "range": "rng"}
            if n.func.id in m:
                args = ",".join(self.expr(a) for a in n.args)
                return f"#{m[n.func.id]}({args})"
        # Method calls -> # tools or attribute call
        if isinstance(n.func, ast.Attribute):
            obj = self.expr(n.func.value)
            attr = n.func.attr
            obj_only = {"strip": "trim", "lower": "lo", "upper": "up",
                        "keys": "keys", "values": "vals"}
            obj_first = {"append": "push", "split": "split"}
            if attr in obj_only:
                return f"#{obj_only[attr]}({obj})"
            if attr in obj_first:
                args = ",".join(self.expr(a) for a in n.args)
                return f"#{obj_first[attr]}({obj},{args})" if args else f"#{obj_first[attr]}({obj})"
            if attr == "join":   # sep.join(l) -> #join(l, sep)
                arg = self.expr(n.args[0]) if n.args else ""
                return f"#join({arg},{obj})"
            args = ",".join(self.expr(a) for a in n.args)
            return f"{obj}.{attr}({args})"
        # Plain function call
        args = ",".join(self.expr(a) for a in n.args)
        return f"{self.expr(n.func)}({args})"

    def e_Attribute(self, n):
        return f"{self.expr(n.value)}.{n.attr}"

    def e_Subscript(self, n):
        v = self.expr(n.value)
        if isinstance(n.slice, ast.Slice):
            return f"/*?slice*/"
        return f"{v}[{self.expr(n.slice)}]"

    def e_List(self, n):
        return "[" + ",".join(self.expr(e) for e in n.elts) + "]"

    def e_Dict(self, n):
        return "{" + ",".join(
            f"{self.expr(k)}:{self.expr(v)}" for k, v in zip(n.keys, n.values)
        ) + "}"

    def e_Tuple(self, n):
        return "[" + ",".join(self.expr(e) for e in n.elts) + "]"

    def e_JoinedStr(self, n):
        # f-string -> "..."+#str(x)+"..."
        parts = []
        for v in n.values:
            if isinstance(v, ast.Constant) and isinstance(v.value, str):
                parts.append('"' + v.value.replace("\\", "\\\\").replace('"', '\\"')
                                       .replace("\n", "\\n").replace("\t", "\\t") + '"')
            elif isinstance(v, ast.FormattedValue):
                parts.append(f"#str({self.expr(v.value)})")
        return "(" + "+".join(parts) + ")" if parts else '""'

    def e_Lambda(self, n):
        params = ",".join(a.arg for a in n.args.args)
        return f":({params}){{^{self.expr(n.body)}}}"

    # ---- helpers ----

    def _op(self, op):
        return {
            ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.Div: "/",
            ast.Mod: "%", ast.FloorDiv: "/",
        }.get(type(op), "+")

    def _cmp(self, op):
        return {
            ast.Eq: "==", ast.NotEq: "!=", ast.Lt: "<", ast.Gt: ">",
            ast.LtE: "<=", ast.GtE: ">=",
        }.get(type(op), "==")


def main():
    src = sys.stdin.read() if len(sys.argv) < 2 else open(sys.argv[1]).read()
    print(P2S().transpile(src))


if __name__ == "__main__":
    main()
