"""Shared helpers of the base world renames (server/README.md "Base NPC names", "Base world texts", "Base houses").

Not a tool: patch_base_npc_names.py and patch_base_texts.py import it.

The name lists of the repository hold no old name. Each row is keyed by the SHA-256 (hex) of the old name in lower case;
the tools collect the words and phrases they find in the base data, hash them and look them up. The old names are only
known at run time, while the base data still has them.

Row matching (`match` column):
  word  whole words, case-insensitive; the case of the match is kept (all lower case, all upper case, else as written)
  cap   the same, but only where the match starts with a capital letter, or where it is a whole string, a whole
        ';'-separated element or a lower-case keyword phrase of at most five words (an NPC keyword): for old names
        that are also common English words
"""
import csv
import hashlib
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
NPC_CSV = os.path.join(SERVER, 'data', 'npc', 'base_npc_names.csv')
WORLD_CSV = os.path.join(SERVER, 'data', 'npc', 'base_world_names.csv')
MONSTER_CSV = os.path.join(SERVER, 'data', 'monster', 'base_monster_names.csv')
MATCHES = ('word', 'cap')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')


def own_npc_files():
    """the NPC files this repository installs (data/npc/X.xml, data/npc/scripts/Y.lua, relative to data/npc): ours,
    named by us, never renamed"""
    out = set()
    for dirpath, dirs, files in os.walk(REPO_NPC):
        for f in files:
            if f.endswith(('.xml', '.lua')):
                out.add(os.path.relpath(os.path.join(dirpath, f), REPO_NPC).replace(os.sep, '/'))
    return out
PATHLIKE = re.compile(r'[/\\]|\.(lua|xml|otbm|ogg|wav|png|txt|json|sql)$', re.I)
PATH_EXT = re.compile(r'\.(lua|xml|otbm|ogg|wav|png|txt|json|sql)$', re.I)
PATH_CHARS = re.compile(r"^[\w .'-]*(?:/[\w .'-]*)+$")


def is_path(value):
    """a file or folder path (left alone): a file name, or slashes without sentence punctuation. A backslash that
    escapes a quote, a backslash or a newline inside a Lua string is no path separator."""
    v = re.sub(r'\\[\\\'"nrt]', '', value)
    if PATH_EXT.search(v.strip()):
        return True
    if '\\' in v:
        return True
    if '/' in v:
        return not re.search(r'\s', v.strip()) or bool(PATH_CHARS.match(v.strip()))
    return False


def digest(name):
    """the key of an old name: sha256 of the name in lower case, apostrophes as written, runs of blanks as one space"""
    return hashlib.sha256(re.sub(r'\s+', ' ', name.strip().lower()).encode('utf-8')).hexdigest()


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def read_rows(path, kinds):
    """sha256,name,kind,match -> {sha256: (name, kind, match)}"""
    rows = {}
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            key = (row.get('sha256') or '').strip().lower()
            if not key or key.startswith('#'):
                continue
            name = (row.get('name') or '').strip()
            kind = (row.get('kind') or '').strip()
            match = (row.get('match') or 'word').strip() or 'word'
            if (not re.match(r'^[0-9a-f]{64}$', key) or not name or kind not in kinds or match not in MATCHES
                    or re.search(r'["<>&;\\]', name)):
                raise SystemExit('%s: bad row %r' % (path, row))
            if key in rows:
                raise SystemExit('%s: hash %s twice' % (path, key))
            rows[key] = (name, kind, match)
    return rows


def read_monster_rows(path=MONSTER_CSV):
    """the monster rename list of patch_base_monster_names.py, as rows of read_rows (monsters only, not looks)"""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            key = (row.get('sha256') or '').strip().lower()
            if re.match(r'^[0-9a-f]{64}$', key) and (row.get('kind') or 'monster').strip() == 'monster':
                out[key] = ((row.get('name') or '').strip(), 'monster', 'word')
    return out


def npc_file(npc_dir, new_name, old_sha):
    """the file name of a base NPC that the npcnames step renames: <new_name>.xml once renamed, before that the file
    whose name has the sha256 old_sha (the old name stays out of the repository); None when neither is there"""
    if os.path.isfile(os.path.join(npc_dir, new_name + '.xml')):
        return new_name + '.xml'
    if os.path.isdir(npc_dir):
        for f in sorted(os.listdir(npc_dir)):
            if f.endswith('.xml') and digest(f[:-4]) == old_sha:
                return f
    return None


# ------------------------------------------------------------------------------------------------ phrases of a text
WORD = r"[A-Za-z][A-Za-z0-9]*(?:(?:\\?'|&apos;|&#39;)[A-Za-z]+)*"
WORD_RX = re.compile(WORD)
APOS_RX = re.compile(r"\\'|&apos;|&#39;")


def norm(s):
    return APOS_RX.sub("'", s)


def phrases(text, longest=5):
    """every run of 1..longest words of a text (lower case, apostrophes plain, one space between words); the last word
    also without a possessive ending or a part after an apostrophe ("name's", "a'b's" -> "a'b", "a")"""
    out = set()
    for chunk in re.split(r"[^A-Za-z0-9' ]+", norm(text)):
        words = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z0-9]*(?:'[A-Za-z]*)*", chunk)]
        for i in range(len(words)):
            for j in range(i + 1, min(len(words), i + longest) + 1):
                head = ' '.join(words[i:j - 1])
                last = words[j - 1]
                parts = last.split("'")
                for k in range(1, len(parts) + 1):
                    w = "'".join(parts[:k]).rstrip("'")
                    if w:
                        out.add((head + ' ' + w) if head else w)
    return out


def known(rows, texts, longest=5):
    """{old lower: (new, kind, match)} of the phrases of the texts whose hash a row knows"""
    seen, out = set(), {}
    for t in texts:
        for p in phrases(t, longest):
            if p in seen:
                continue
            seen.add(p)
            r = rows.get(digest(p))
            if r and r[0].lower() != p:
                out[p] = r
    return out


# ------------------------------------------------------------------------------------------------ the renamer
KEYWORD = re.compile(r"^[a-z']+(?: [a-z']+){0,4}$")  # a lower-case keyword phrase such as "x sent me"
def _pattern(old):
    out = []
    for part in re.split(r"(')", old):
        if part == "'":
            out.append(r"(?:\\'|'|&apos;|&#39;)")
        elif part:
            out.append(r'\s+'.join(re.escape(w) for w in part.split(' ')))
    return ''.join(out)


TITLE_PREV = re.compile(r"(?:^|[^.!?:;\"{(\s]\s*|[A-Za-z]+\s+)([A-Z][a-z]+) $")
TITLE_NEXT = re.compile(r" ([A-Z][a-z]+)")
TITLE_CASE = re.compile(r"^(?:[A-Z][a-z']*|of|the|and)(?: (?:[A-Z][a-z']*|of|the|and)){1,4}$")  # "Crimson X", a name


def in_title(value, start, end):
    """the match is a word of a longer name in title case ("Crimson X", "X Lurker"): the whole text is a short title
    case name, or a capitalized word stands right after it, or right before it (when that word does not start the
    text or a sentence)"""
    if TITLE_NEXT.match(value, end) or TITLE_CASE.match(value):
        return True
    head = value[:start]
    prev = re.search(r'([A-Z][a-z]+) $', head)
    if not prev:
        return False
    before = head[:prev.start()]
    return not (before.strip() == '' or re.search(r'[.!?:;"{(]\s*$', before))


class Renamer:
    """whole-word replacement of old names inside one string value.

    names: {old lower: (new, kind, match)}; titles: the values are names of things (outfits, mounts), where a `cap`
    row inside a title-case name ("Crimson X") is a plain word and stays; keep: phrases (lower case) that stay as they are even when they are or
    contain an old name (the names of items, monsters and NPCs the data still uses: other tools own them); soft:
    the kept names that are only item names: where such a name is written with a capital letter and is an old
    person's name, it is the person and is renamed (the NPC "X" against the item "x")."""

    def __init__(self, names, keep=(), soft=(), titles=False):
        self.names = names
        self.soft = set(soft)
        self.titles = titles
        self.count = 0
        self.by_kind = {}
        olds = sorted(names, key=len, reverse=True)
        self.first = {o.split(' ')[0].split("'")[0] for o in olds}
        self.rx = re.compile(r"(?<![A-Za-z0-9_])(?<![A-Za-z]')(?<![A-Za-z]\\')(%s)(?![A-Za-z0-9_])"
                             % '|'.join(_pattern(o) for o in olds), re.I) if olds else None
        rx = self.rx
        longer = sorted({k for k in keep if rx and rx.search(k)}, key=len, reverse=True)
        self.keep = re.compile(r"(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])" % '|'.join(_pattern(k) for k in longer),
                               re.I) if longer else None

    def maybe(self, value):
        """cheap test: does the value have a word that starts an old name"""
        if not self.rx:
            return False
        for w in re.findall(r"[A-Za-z][A-Za-z0-9]*", value):
            if w.lower() in self.first:
                return True
        return False

    def lookup(self, matched):
        key = re.sub(r'\s+', ' ', norm(matched)).lower()
        return self.names.get(key)

    @staticmethod
    def styled(matched, new):
        if matched == matched.lower():
            return new.lower()
        if matched == matched.upper() and len(re.sub(r'[^A-Za-z]', '', matched)) > 1:
            return new.upper()
        return new

    def __call__(self, value):
        if not self.maybe(value):
            return value
        kept = []
        if self.keep:
            def hide(m):
                # an item name that is itself an old person's name (an NPC "X" and an item "x") is the
                # person where it is written with a capital letter; monster and NPC names always stay
                row = self.lookup(m.group(0))
                if (row and row[1] in ('npc', 'person') and m.group(0)[0].isupper()
                        and re.sub(r'\s+', ' ', norm(m.group(0))).lower() in self.soft):
                    return m.group(0)
                kept.append(m.group(0))
                return '\x00%d\x00' % (len(kept) - 1)
            value = self.keep.sub(hide, value)
        out, last = [], 0
        for m in self.rx.finditer(value):
            matched = m.group(1)
            row = self.lookup(matched)
            if not row:
                continue
            new, kind, match = row
            if self.titles and match == 'cap' and matched[0].isupper() and in_title(value, m.start(), m.end()):
                continue
            if match == 'cap' and not matched[0].isupper():
                before = value[:m.start()]
                after = value[m.end():]
                element = (before == '' or before.endswith(';')) and (after == '' or after.startswith(';'))
                if not element and not KEYWORD.match(value):
                    continue
            new = self.styled(matched, new)
            head = value[last:m.start()]
            if new.lower().startswith('the '):
                if re.search(r'(?<![A-Za-z])the\s+$', head, re.I):
                    new = new[4:]
                elif matched[0].isupper() and re.search(r'(^|[.!?]\s+|["{]\s*)$', value[:m.start()]):
                    new = new[0].upper() + new[1:]
            art = re.search(r'(?<![A-Za-z])(an?)(\s+)$', head, re.I)
            if art:
                want = 'an' if new[:1].lower() in 'aeiou' else 'a'
                had = art.group(1)
                if had == had.upper() and (len(had) > 1 or new == new.upper()):
                    want = want.upper()
                elif had[0].isupper():
                    want = want.capitalize()
                head = head[:art.start(1)] + want + art.group(2)
            out.append(head)
            out.append(new)
            last = m.end()
            self.count += 1
            self.by_kind[kind] = self.by_kind.get(kind, 0) + 1
        if not out:
            if kept:
                value = re.sub('\x00(\\d+)\x00', lambda m: kept[int(m.group(1))], value)
            return value
        out.append(value[last:])
        value = ''.join(out)
        if kept:
            value = re.sub('\x00(\\d+)\x00', lambda m: kept[int(m.group(1))], value)
        return value


# ------------------------------------------------------------------------------------------------ strings of files
ATTR = re.compile(r'(\s)([A-Za-z_:][\w:.-]*)(\s*=\s*)(")([^"]*)(")')
TAG = re.compile(r'<[A-Za-z][^<>]*>')


def xml_values(text):
    for t in TAG.finditer(text):
        for m in ATTR.finditer(t.group(0)):
            yield m.group(2), m.group(5)


def patch_xml(text, fn, skip_attrs=(), skip_tag=None):
    """fn(value) for every attribute value of every tag (paths, file/script attributes and skip_attrs left alone)"""
    def attr(m):
        key, value = m.group(2), m.group(5)
        if is_path(value) or key.lower() in ('file', 'script', 'path') or key.lower() in skip_attrs:
            return m.group(0)
        new = fn(value)
        return m.group(0) if new == value else '%s%s%s"%s"' % (m.group(1), key, m.group(3), new)

    def tag(m):
        t = m.group(0)
        if '=' not in t or (skip_tag and skip_tag(t)):
            return t
        return ATTR.sub(attr, t)
    return TAG.sub(tag, text)


def lua_string_spans_q(text):
    """[(start, end, quote)] of the contents of every string literal, comments skipped; quote is ', " or [ (long)"""
    spans, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '-' and text.startswith('--', i):
            m = re.match(r'--\[(=*)\[', text[i:i + 64])
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, i + m.end())
                i = n if j < 0 else j + len(close)
            else:
                j = text.find('\n', i)
                i = n if j < 0 else j + 1
            continue
        if c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            spans.append((i + 1, min(j, n), c))
            i = j + 1
            continue
        if c == '[':
            m = re.match(r'\[(=*)\[', text[i:i + 64])
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, i + m.end())
                j = n if j < 0 else j
                spans.append((i + m.end(), j, '[' + m.group(1)))
                i = j + len(close)
                continue
        i += 1
    return spans


def lua_string_spans(text):
    """[(start, end)] of the contents of every string literal, comments skipped"""
    return [(a, b) for a, b, q in lua_string_spans_q(text)]


def lua_escape(new, quote):
    """a changed string value made safe for its delimiter: a quote of the delimiter's kind that is not escaped yet gets
    a backslash; a long string must not get its closing bracket"""
    if quote in ('"', "'"):
        return re.sub(r'(?<!\\)((?:\\\\)*)' + re.escape(quote), lambda m: m.group(1) + '\\' + quote, new)
    close = ']' + quote[1:] + ']'
    return new.replace(close, ']' + quote[1:] + ' ]')


def lua_strings(text):
    for a, b in lua_string_spans(text):
        yield text[a:b]


SPELL_WORDS = re.compile(r'(?:words|Words)\s*(?:\(|=)\s*$')
# a string assigned to a key that names a file, map, path or folder (mapName = 'x': loaded as data/world/.../x.otbm)
FILE_KEY = re.compile(r'(?i)\b(?:map|file|path|dir|folder|script)\w*\s*=\s*$')


def patch_lua(text, fn, skip_words=False):
    """fn(value) for the contents of every string literal (paths left alone, and strings assigned to a key that names a
    file, map, path or folder such as mapName = 'x'; with skip_words, spell and talkaction words: a string right after
    `words(` or `words =`)"""
    out, last = [], 0
    for a, b, q in lua_string_spans_q(text):
        value = text[a:b]
        if is_path(value):
            continue
        before = text[max(0, a - 40):a - len(q)]
        if FILE_KEY.search(before) or (skip_words and SPELL_WORDS.search(before)):
            continue
        new = fn(value)
        if new != value:
            new = lua_escape(new, q)
            out.append(text[last:a])
            out.append(new)
            last = b
    if not out:
        return text
    out.append(text[last:])
    return ''.join(out)


def map_path(data_dir):
    """DATA_DIR/world/<mapName>.otbm (mapName of the config.lua next to DATA_DIR), else the only .otbm there"""
    world = os.path.join(data_dir, 'world')
    cfg = os.path.join(os.path.dirname(os.path.abspath(data_dir)), 'config.lua')
    if os.path.isfile(cfg):
        m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', read(cfg), re.M)
        if m:
            p = os.path.join(world, m.group(1) + '.otbm')
            if os.path.isfile(p):
                return p
    maps = sorted(n for n in os.listdir(world) if n.endswith('.otbm')) if os.path.isdir(world) else []
    return os.path.join(world, maps[0]) if len(maps) == 1 else None
