#!/usr/bin/env python3
"""Client localization check (client/MANIFEST.md "Localization").

Every Chaos overlay string a player reads goes through tr(): `tr('Text %s', x)` in Lua, `!text: tr('Text')` in OTUI
(also `!tooltip:`, `!placeholder:`, `!title:`). The pt-BR table is
client/overlay/modules/client_chaos_locale/pt_br.lua. This check fails when:
  - a tr() key has no pt-BR entry (or an empty one),
  - a pt-BR entry has a different number or kind of % formats than its key,
  - a UI string is hard-coded: an OTUI `text:`/`tooltip:`/`placeholder:`/`title:` value with letters, or a Lua
    string literal with letters given straight to setText, setTooltip, setTitle, setPlaceholder,
    displayInfoBox/displayErrorBox/displayCancelBox/displayGeneralBox or a PopupMenu addOption without tr().
Generated data (codex_data.lua, spelldata.lua, autorotation_data.lua) and *_test.lua are not UI code.

  python3 -I tools/ci/check_locales.py            # check
  python3 -I tools/ci/check_locales.py --missing  # also print the missing keys as Lua lines to paste
  python3 -I tools/ci/check_locales.py --stats    # coverage numbers
  python3 -I tools/ci/check_locales.py --fix FILE...  # wrap the hard-coded UI texts of these files in tr()
A tr() whose key is a run-time value (tr(row.name)) is allowed and counted as dynamic: the strings it gets must be
in pt_br.lua too, which this check cannot see (pt_br.lua lists them under "Run-time keys").
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODULES = os.path.join(ROOT, 'client', 'overlay', 'modules')
STYLES = os.path.join(ROOT, 'client', 'overlay', 'data', 'styles')
PT_BR = os.path.join(MODULES, 'client_chaos_locale', 'pt_br.lua')
SKIP_FILES = {'codex_data.lua', 'spelldata.lua', 'autorotation_data.lua', 'pt_br.lua'}
SINKS = {'setText': (1,), 'setTooltip': (1,), 'setTitle': (1,), 'setPlaceholder': (1,),
         'displayInfoBox': (1, 2), 'displayErrorBox': (1, 2), 'displayCancelBox': (1, 2),
         'displayGeneralBox': (1, 2)}
OTUI_PROPS = ('text', 'tooltip', 'placeholder', 'title')
WORDY = re.compile(r'[A-Za-z\xc0-\xff]{2,}')


# ---------------------------------------------------------------- Lua lexer
class Tok:
    __slots__ = ('kind', 'text', 'value', 'start', 'end', 'line')

    def __init__(self, kind, text, value, start, end, line):
        self.kind, self.text, self.value, self.start, self.end, self.line = kind, text, value, start, end, line

    def __repr__(self):
        return f'Tok({self.kind},{self.text!r})'


_ESC = {'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11, '\\': 92, '"': 34, "'": 39, '\n': 10}
_OPS = ('...', '..', '==', '~=', '<=', '>=', '::', '//', '<<', '>>')


def decode_short(body):
    """Bytes of a quoted Lua string body (between the quotes), as Lua 5.3 reads it."""
    out = bytearray()
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if c != 92:
            out.append(c); i += 1; continue
        i += 1
        e = chr(body[i])
        if e in _ESC:
            out.append(_ESC[e]); i += 1
        elif e == '\r':
            out.append(10); i += 1
            if i < n and body[i] == 10:
                i += 1
        elif e == 'x':
            out.append(int(body[i + 1:i + 3], 16)); i += 3
        elif e == 'z':
            i += 1
            while i < n and chr(body[i]) in ' \t\r\n\f\v':
                i += 1
        elif e == 'u':
            j = body.index(b'}', i)
            out += chr(int(body[i + 2:j], 16)).encode('utf-8'); i = j + 1
        elif e.isdigit():
            j = i
            while j < n and j - i < 3 and chr(body[j]).isdigit():
                j += 1
            out.append(int(body[i:j])); i = j
        else:
            raise ValueError('bad escape \\' + e)
    return bytes(out)


def lex(src):
    """Tokens of Lua source (bytes). Kinds: name, number, string, op. Comments are dropped."""
    toks, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        ch = chr(c)
        if ch == '\n':
            line += 1; i += 1; continue
        if ch in ' \t\r\f\v':
            i += 1; continue
        if src.startswith(b'--', i):
            m = re.compile(rb'\[(=*)\[').match(src, i + 2)
            if m:
                close = b']' + m.group(1) + b']'
                j = src.find(close, m.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find(b'\n', i)
                j = n if j < 0 else j
            line += src.count(b'\n', i, j); i = j; continue
        if ch in '\'"':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == 92:
                    j += 1
                j += 1
            body = src[i + 1:j]
            toks.append(Tok('string', src[i:j + 1], decode_short(body), i, j + 1, line))
            line += src.count(b'\n', i, j + 1); i = j + 1; continue
        m = re.compile(rb'\[(=*)\[').match(src, i)
        if m:
            close = b']' + m.group(1) + b']'
            j = src.find(close, m.end())
            body = src[m.end():j]
            if body.startswith(b'\r\n'):
                body = body[2:]
            elif body.startswith(b'\n'):
                body = body[1:]
            toks.append(Tok('string', src[i:j + len(close)], body, i, j + len(close), line))
            line += src.count(b'\n', i, j); i = j + len(close); continue
        if (ch.isascii() and ch.isalpha()) or ch == '_':
            m = re.compile(rb'[A-Za-z_][A-Za-z0-9_]*').match(src, i)
            toks.append(Tok('name', m.group(), m.group().decode(), i, m.end(), line)); i = m.end(); continue
        if ch in '0123456789' or (ch == '.' and i + 1 < n and chr(src[i + 1]) in '0123456789'):
            m = re.compile(rb'0[xX][0-9a-fA-F.]*([pP][+-]?\d+)?|\d*\.?\d*([eE][+-]?\d+)?').match(src, i)
            toks.append(Tok('number', m.group(), m.group().decode(), i, m.end(), line)); i = m.end(); continue
        for op in _OPS:
            if src.startswith(op.encode(), i):
                toks.append(Tok('op', op.encode(), op, i, i + len(op), line)); i += len(op); break
        else:
            toks.append(Tok('op', bytes([c]), ch, i, i + 1, line)); i += 1
    return toks


def match_close(toks, i):
    """Index of the token closing the bracket at toks[i]."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    depth, j = 0, i
    while j < len(toks):
        t = toks[j]
        if t.kind == 'op' and t.value in pairs:
            depth += 1
        elif t.kind == 'op' and t.value in (')', ']', '}'):
            depth -= 1
            if depth == 0:
                return j
        j += 1
    raise ValueError('unbalanced bracket at line %d' % toks[i].line)


def split_args(toks, open_i, close_i):
    """[(first, last)] token index ranges (inclusive) of the comma separated arguments inside a call."""
    out, depth, s = [], 0, open_i + 1
    for j in range(open_i + 1, close_i):
        t = toks[j]
        if t.kind == 'op' and t.value in '([{':
            depth += 1
        elif t.kind == 'op' and t.value in ')]}':
            depth -= 1
        elif depth == 0 and t.kind == 'op' and t.value == ',':
            out.append((s, j - 1)); s = j + 1
    if s <= close_i - 1:
        out.append((s, close_i - 1))
    return out


def calls(toks, names):
    """(name, index of the name token, open paren index, close paren index) of every call to one of `names`
    (a plain call, a method call obj:name(...) or a field call a.name(...))."""
    for i, t in enumerate(toks):
        if t.kind == 'name' and t.value in names and i + 1 < len(toks) and toks[i + 1].kind == 'op' \
                and toks[i + 1].value == '(':
            if i > 0 and toks[i - 1].kind == 'name' and toks[i - 1].value == 'function':
                continue
            if i > 1 and toks[i - 1].kind == 'op' and toks[i - 1].value == '.' and toks[i - 2].kind == 'name' \
                    and toks[i - 2].value == 'function':
                continue
            yield t.value, i, i + 1, match_close(toks, i + 1)


def tr_keys(toks):
    """([(key bytes, line)], [line of a tr() whose key is a run-time value]). A key made of literals joined with
    `..` counts as one literal."""
    keys, bad = [], []
    for name, i, o, c in calls(toks, {'tr'}):
        if i > 0 and toks[i - 1].kind == 'op' and toks[i - 1].value in ('.', ':'):
            continue
        args = split_args(toks, o, c)
        if not args:
            continue
        a, b = args[0]
        parts = toks[a:b + 1]
        if all(t.kind == 'string' for t in parts[0::2]) and all(t.kind == 'op' and t.value == '..'
                                                                  for t in parts[1::2]) and len(parts) % 2 == 1:
            keys.append((b''.join(t.value for t in parts[0::2]), toks[a].line))
        else:
            bad.append(toks[i].line)
    return keys, bad


def is_op(t, v):
    return t.kind == 'op' and t.value == v


def is_name(t, v):
    return t.kind == 'name' and t.value == v


def top_split(toks, a, b, pred):
    """Split range [a, b] at top-level tokens matching pred: [(start, end)] and the separator indices."""
    parts, seps, depth, s = [], [], 0, a
    for j in range(a, b + 1):
        t = toks[j]
        if t.kind == 'op' and t.value in '([{':
            depth += 1
        elif t.kind == 'op' and t.value in ')]}':
            depth -= 1
        elif depth == 0 and pred(t):
            parts.append((s, j - 1)); seps.append(j); s = j + 1
    parts.append((s, b))
    return parts, seps


def wordy(t):
    return t.kind == 'string' and WORDY.search(t.value.decode('latin-1'))


def lua_lit(bs):
    out = ["'"]
    for c in bs:
        ch = chr(c)
        if ch == '\\':
            out.append('\\\\')
        elif ch == "'":
            out.append("\\'")
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif 32 <= c < 127:
            out.append(ch)
        else:
            out.append('\\%d' % c)
    out.append("'")
    return ''.join(out)


class Rewriter:
    """Finds the UI texts of a Lua file that miss tr() and wraps them: a literal becomes tr('...'), a chain
    'a' .. x .. 'b' becomes tr('a%sb', x), string.format('...', x) becomes tr('...', x); `and`/`or` operands are
    handled one by one; comparisons and other calls are left alone."""

    def __init__(self, src, toks=None):
        self.src = src
        self.toks = toks if toks is not None else lex(src)

    def line_of(self, pos):
        return self.src.count(b'\n', 0, pos) + 1

    def text(self, a, b):
        return self.src[self.toks[a].start:self.toks[b].end].decode('latin-1')

    def apply(self, a, b, edits):
        """Source text of range [a, b] with edits (byte start, byte end, new text) applied."""
        s0, s1 = self.toks[a].start, self.toks[b].end
        out, pos = [], s0
        for es, ee, nt in sorted(edits):
            out.append(self.src[pos:es].decode('latin-1')); out.append(nt); pos = ee
        out.append(self.src[pos:s1].decode('latin-1'))
        return ''.join(out)

    def process(self, a, b):
        toks = self.toks
        if a > b:
            return []
        # a tr(...) call already
        if is_name(toks[a], 'tr') and a + 1 <= b and is_op(toks[a + 1], '(') and match_close(toks, a + 1) == b:
            return []
        # parenthesized
        if is_op(toks[a], '(') and match_close(toks, a) == b:
            return self.process(a + 1, b - 1)
        for kw in ('or', 'and'):
            parts, seps = top_split(toks, a, b, lambda t, kw=kw: is_name(t, kw))
            if len(parts) > 1:
                ed = []
                for pa, pb in parts:
                    ed += self.process(pa, pb)
                return ed
        parts, seps = top_split(toks, a, b, lambda t: t.kind == 'op' and t.value in ('==', '~=', '<', '>', '<=', '>='))
        if len(parts) > 1:
            return []
        if any(is_name(toks[j], 'not') for j in range(a, b + 1)) and is_name(toks[a], 'not'):
            return []
        parts, seps = top_split(toks, a, b, lambda t: is_op(t, '..'))
        if len(parts) > 1:
            lits = [pa == pb and toks[pa].kind == 'string' for pa, pb in parts]
            if not any(l and wordy(toks[pa]) for l, (pa, pb) in zip(lits, parts)):
                ed = []
                for l, (pa, pb) in zip(lits, parts):
                    if not l:
                        ed += self.process(pa, pb)
                return ed
            fmt, args = b'', []
            for l, (pa, pb) in zip(lits, parts):
                if l:
                    fmt += toks[pa].value
                else:
                    fmt += b'\x00'
                    args.append(self.apply(pa, pb, self.process(pa, pb)))
            if args:
                fmt = fmt.replace(b'%', b'%%').replace(b'\x00', b'%s')
                new = 'tr(' + lua_lit(fmt) + ', ' + ', '.join(args) + ')'
            else:
                new = 'tr(' + lua_lit(fmt) + ')'
            return [(toks[a].start, toks[b].end, new)]
        if a == b and toks[a].kind == 'string':
            if wordy(toks[a]):
                return [(toks[a].start, toks[a].end, 'tr(' + toks[a].text.decode('latin-1') + ')')]
            return []
        # string.format('...', ...) as the whole expression
        if b - a >= 4 and is_name(toks[a], 'string') and is_op(toks[a + 1], '.') and is_name(toks[a + 2], 'format') \
                and is_op(toks[a + 3], '(') and match_close(toks, a + 3) == b and wordy(toks[a + 4]):
            inner = split_args(toks, a + 3, b)
            ed = [(toks[a].start, toks[a + 2].end, 'tr')]
            for pa, pb in inner[1:]:
                ed += self.process(pa, pb)
            return ed
        return []

    def edits(self):
        toks = self.toks
        edits = []
        for name, i, o, c in calls(toks, set(SINKS) | {'addOption'}):
            args = split_args(toks, o, c)
            if name == 'addOption':
                # PopupMenu addOption(text, function): a ComboBox's addOption(text, data) texts are often
                # compared with getText(), so those are left to the author
                if len(args) < 2 or not is_name(toks[args[1][0]], 'function'):
                    continue
                which = (1,)
            else:
                if name.startswith('set') and not (i > 0 and is_op(toks[i - 1], ':')):
                    continue  # widget:setText(...), not a local setText(id, text)
                which = SINKS[name]
            for k in which:
                if k <= len(args):
                    edits += self.process(*args[k - 1])
        edits.sort()
        out, last = [], -1
        for e in edits:  # an edit inside another one (a sink in a sink argument) is dropped
            if e[0] >= last:
                out.append(e); last = e[1]
        return out

    def run(self):
        out = self.edits()
        res, pos = [], 0
        for es, ee, nt in out:
            res.append(self.src[pos:es]); res.append(nt.encode('latin-1')); pos = ee
        res.append(self.src[pos:])
        return b''.join(res), len(out)


def hardcoded(toks, src):
    """[(line, text)]: UI texts a Lua file gives straight to a sink without tr() (what --fix would wrap)."""
    r = Rewriter(src, toks)
    return [(r.line_of(es), src[es:ee]) for es, ee, nt in r.edits()]


# ---------------------------------------------------------------- OTUI
OTUI_LINE = re.compile(rb'^(\s*)(!?)(' + b'|'.join(p.encode() for p in OTUI_PROPS) + rb')\s*:\s?(.*?)\s*$')


def otui_scan(src):
    """([(key, line)], [bad tr lines], [(line, hard-coded text)]) of an .otui file."""
    keys, bad, hard = [], [], []
    for ln, raw in enumerate(src.split(b'\n'), 1):
        m = OTUI_LINE.match(raw)
        if not m:
            continue
        bang, value = m.group(2), m.group(4)
        if bang:
            try:
                toks = lex(value)
            except Exception:
                bad.append(ln); continue
            k, b = tr_keys(toks)
            keys += [(key, ln) for key, _ in k]
            bad += [ln for _ in b]
            if not k and not b:
                for t in toks:
                    if t.kind == 'string' and WORDY.search(t.value.decode('latin-1')):
                        hard.append((ln, t.value))
        else:
            v = value
            if len(v) >= 2 and v[:1] == v[-1:] and v[:1] in (b'"', b"'"):
                v = v[1:-1]
            if v not in (b'|', b'') and WORDY.search(v.decode('latin-1')):
                hard.append((ln, value))
    return keys, bad, hard


def otui_fix(src):
    """The .otui source with each hard-coded `text: Foo` turned into `!text: tr('Foo')`, and the count."""
    lines, n = src.split(b'\n'), 0
    for i, raw in enumerate(lines):
        m = OTUI_LINE.match(raw)
        if not m or m.group(2):
            continue
        v = m.group(4)
        if len(v) >= 2 and v[:1] == v[-1:] and v[:1] in (b'"', b"'"):
            v = v[1:-1]
        if v in (b'|', b'') or not WORDY.search(v.decode('latin-1')):
            continue
        lines[i] = m.group(1) + b'!' + m.group(3) + b': tr(' + lua_lit(v.replace(b'\\n', b'\n')).encode('latin-1') + b')'
        n += 1
    return b'\n'.join(lines), n


# ---------------------------------------------------------------- pt-BR table
def load_table(path):
    """{key bytes: value str (UTF-8)} of a locale table file: `["key"] = "value",` entries."""
    src = open(path, 'rb').read()
    toks = lex(src)
    table, dup = {}, []
    for i in range(len(toks) - 4):
        a, k, b, eq, v = toks[i:i + 5]
        if a.kind == 'op' and a.value == '[' and k.kind == 'string' and b.kind == 'op' and b.value == ']' \
                and eq.kind == 'op' and eq.value == '=' and v.kind == 'string':
            if k.value in table:
                dup.append(k.value)
            table[k.value] = v.value.decode('utf-8')
    return table, dup


FMT = re.compile(r'%[-+#0]*\d*(?:\.\d+)?([diouxXeEfgGqsaAc%])')


def formats(s):
    """The string.format conversions of s, in order (Lua has no positional arguments: the order must stay)."""
    return [m.group(1) for m in FMT.finditer(s) if m.group(1) != '%']


# ---------------------------------------------------------------- walk
def overlay_files():
    for base in (MODULES, STYLES):
        for d, _, files in os.walk(base):
            for f in sorted(files):
                if f in SKIP_FILES or f.endswith('_test.lua'):
                    continue
                if f.endswith('.lua') or f.endswith('.otui'):
                    yield os.path.join(d, f)


def scan():
    keys, bad, hard = {}, [], []
    for p in overlay_files():
        rel = os.path.relpath(p, ROOT)
        src = open(p, 'rb').read()
        if p.endswith('.otui'):
            k, b, h = otui_scan(src)
        else:
            toks = lex(src)
            k, b = tr_keys(toks)
            h = hardcoded(toks, src)
        for key, ln in k:
            if key:  # tr('') is an empty label
                keys.setdefault(key, []).append((rel, ln))
        bad += [(rel, ln) for ln in b]
        hard += [(rel, ln, t) for ln, t in h]
    return keys, bad, hard


def lua_quote(b):
    out = []
    for c in b:
        ch = chr(c)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif 32 <= c < 127:
            out.append(ch)
        else:
            out.append('\\%d' % c)
    return '"' + ''.join(out) + '"'


def main(argv):
    if '--fix' in argv:
        for p in [a for a in argv if not a.startswith('--')]:
            src = open(p, 'rb').read()
            new, n = otui_fix(src) if p.endswith('.otui') else Rewriter(src).run()
            if n:
                open(p, 'wb').write(new)
                print(f'{p}: {n} text(s) wrapped in tr()')
        return 0
    keys, dynamic, hard = scan()
    table, dup = load_table(PT_BR) if os.path.exists(PT_BR) else ({}, [])
    missing = [k for k in keys if not table.get(k)]
    problems = 0
    for k in dup:
        print(f'pt_br.lua: duplicate key {lua_quote(k)}'); problems += 1
    for k in sorted(missing):
        rel, ln = keys[k][0]
        print(f'{rel}:{ln}: no pt-BR translation for {lua_quote(k)}'); problems += 1
    for k, v in table.items():
        if formats(k.decode('latin-1')) != formats(v):
            print(f'pt_br.lua: the % formats differ for {lua_quote(k)}'); problems += 1
    for rel, ln, t in hard:
        print(f'{rel}:{ln}: hard-coded UI text {t.decode("latin-1")!r}: use tr() (--fix)'); problems += 1
    if '--missing' in argv:
        for k in sorted(missing):
            print(f'  [{lua_quote(k)}] = "",')
    if '--stats' in argv:
        n = sum(len(v) for v in keys.values())
        print(f'tr() calls with a literal key: {n}, distinct keys: {len(keys)}, translated: {len(keys) - len(missing)}, '
              f'tr() with a run-time key: {len(dynamic)}, hard-coded UI texts: {len(hard)}, '
              f'pt-BR entries: {len(table)} ({len([k for k in table if k not in keys])} not literal keys)')
    print('locale check:', 'OK' if not problems else f'{problems} problem(s)')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
