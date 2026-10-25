#!/usr/bin/env python3
"""Map inbox: areas the owner asked for in chat, kept as plans until they are approved and installed (docs/MAP_GUIDE.md "Map inbox").

An inbox entry is a folder server/tools/areaplan/inbox/<id>/ with only two small files in git:
  plan.json   the area plan (schema server/tools/areaplan/schema.json)
  meta.json   status (pending, approved, installed), the owner's words, a note, the level band, size, the stats of the
              compile and the sha256 of every compiled file
The tiles, the spawn file, the view frame, the manifest and the pictures are NOT in git. The compile is deterministic (same
plan, same bytes; the test proves it), so `build` makes them again from the plan whenever they are wanted.

    python3 -I server/tools/area_inbox.py new --from-prompt "TEXT" [--level LO HI] [--id ID] [--note TEXT]
    python3 -I server/tools/area_inbox.py new --plan PLAN.json [--level LO HI] [--id ID] [--note TEXT] [--prompt TEXT]
    python3 -I server/tools/area_inbox.py list [--json]
    python3 -I server/tools/area_inbox.py check [ID ...]
    python3 -I server/tools/area_inbox.py approve ID [--note TEXT]
    python3 -I server/tools/area_inbox.py build ID OUT_DIR [--assets DIR]
    python3 -I server/tools/area_inbox.py publish OUT_DIR [--status approved,pending] [--assets DIR]
    python3 -I server/tools/area_inbox.py promote ID [--origin X Y Z] [--force]
    python3 -I server/tools/area_inbox.py remove ID

new       the plan comes from the AI adapter (--from-prompt: area_planner.py plan; needs the endpoint of
          area_plan_ai.py, else it says how to set one up and exits 2) or from a file (--plan: a person or Claude in a
          session wrote it). Then validate -> compile -> stats; an error stops it and nothing is written. The entry starts
          pending. --id renames the plan.
list      id, status, level band, size, name.
check     validate and compile the plans of the entries (all, or the ids given); exit 1 on an error. Used by CI.
approve   pending -> approved (validated and compiled again first). The owner says so after looking at the area.
build     OUT_DIR/ID/: ID.otbm (OTBM for the map editor), ID-frame.otbm, ID-spawn.xml, ID.json (manifest), plan.json,
          NOTE.txt, files.txt (sha256 and name per file, read by the Windows fetch-areas.bat) and, when the render inputs
          exist, the pictures ID_z<z>.png and ID_map.png. Render inputs: --assets DIR or $AREAINBOX_ASSETS holding
          items.otb, items.xml, Tibia.dat, Tibia.spr (and numpy + Pillow); without them the pictures are skipped with a message.
publish   build every entry with one of the statuses (default approved and pending) into OUT_DIR, with list.txt (one
          line per area: id|status|lo-hi|name) and index.json. What `chaos-ctl.sh areas-publish` runs.
promote   approved -> installed: the plan moves to server/tools/areaplan/plans/ (where install_content_areas.py reads it).
          It needs an `origin` (the plan has one, or --origin X Y Z); refused when the box lands on another plan's box
          (any z, 10 tiles apart) unless --force. It prints the steps that remain (the map and the tests).
remove    delete a pending or approved entry.
Python 3 standard library; compile needs LuaJIT (LUAJIT=... to point elsewhere), as area_planner.py does.
"""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

INBOX = os.path.join(HERE, 'areaplan', 'inbox')
PLANS = os.path.join(HERE, 'areaplan', 'plans')
OTHER_PLAN_DIRS = [os.path.join(HERE, 'areaplan', d) for d in ('chronicle', 'rooms', 'events')]
SCHEMA = 'chaos-area-inbox/1'
STATUSES = ('pending', 'approved', 'installed')
ID_RE = re.compile(r'^[a-z][a-z0-9_]{2,39}$')
ASSET_FILES = ('items.otb', 'items.xml', 'Tibia.dat', 'Tibia.spr')
MARGIN = 10  # tiles between two areas, on any z (area_planner_test.py "placed areas")


class InboxError(Exception):
    pass


def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def dump_json(obj, path, **kw):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(obj, indent=kw.get('indent', 1), sort_keys=kw.get('sort_keys', True), ensure_ascii=True) + '\n')


def entry_dir(inbox, pid):
    if not ID_RE.match(pid or ''):
        raise InboxError('bad id %r: lower-case letters, digits and _, 3 to 40 characters, starting with a letter' % (pid,))
    return os.path.join(inbox, pid)


def read_entry(inbox, pid):
    d = entry_dir(inbox, pid)
    if not os.path.isfile(os.path.join(d, 'meta.json')):
        raise InboxError('no inbox entry %s (list shows them)' % pid)
    meta = load_json(os.path.join(d, 'meta.json'))
    plan_path = os.path.join(d, 'plan.json')
    plan = load_json(plan_path) if os.path.isfile(plan_path) else None
    return meta, plan


def entries(inbox):
    out = []
    if os.path.isdir(inbox):
        for pid in sorted(os.listdir(inbox)):
            if os.path.isfile(os.path.join(inbox, pid, 'meta.json')):
                out.append(pid)
    return out


# ------------------------------------------------------------------------------------------------ plan -> files
def compile_checked(plan):
    """validate and compile; returns (result, notes). Raises InboxError with the messages on an error"""
    import area_plan_core as C
    import area_plan_compile as PC
    issues = C.validate(plan)
    errs = C.errors(issues)
    notes = [str(i) for i in issues]
    if errs:
        raise InboxError('the plan is not valid:\n' + '\n'.join(str(i) for i in errs))
    try:
        res = PC.compile_plan(plan)
    except PC.CompileError as e:
        raise InboxError('compile failed: %s' % e)
    for lvl, m in res['qa']:
        notes.append('%s %s' % (lvl, m))
    if PC.qa_errors(res):
        raise InboxError('compile QA errors:\n' + '\n'.join('%s %s' % (l, m) for l, m in res['qa'] if l == 'ERROR'))
    return res, notes


def write_compiled(res, out_dir):
    """the compiler's files of the editor into out_dir; returns {name: sha256}"""
    import area_plan_compile as PC
    tmp = tempfile.mkdtemp(prefix='areainbox.')
    try:
        PC.write_outputs(res, tmp)
        names = sorted(n for n in os.listdir(tmp) if os.path.isfile(os.path.join(tmp, n)))
        os.makedirs(out_dir, exist_ok=True)
        sums = {}
        for n in names:
            shutil.copyfile(os.path.join(tmp, n), os.path.join(out_dir, n))
            sums[n] = sha256_file(os.path.join(out_dir, n))
        return sums
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 16), b''):
            h.update(block)
    return h.hexdigest()


def stats_summary(res):
    s = res['stats']
    return dict(tiles=s['tiles'], walkable=s['walkable'], monsters=s['monsters'], spawn_points=s['spawn_points'],
                per100=s['per100'], entry_to_boss=s.get('entry_to_boss'), farthest_zone=s.get('farthest_zone'))


def make_meta(plan, res, status, prompt, note, sums, today=None):
    return {
        'schema': SCHEMA, 'id': plan['id'], 'name': plan.get('name', plan['id']), 'status': status,
        'created': today or datetime.date.today().isoformat(), 'prompt': prompt or '', 'note': note or '',
        'level': plan.get('level'), 'biome': plan.get('biome'), 'size': plan.get('size'), 'floors': plan.get('floors', 1),
        'stats': stats_summary(res),
        'compiled_sha256': sums,
    }


# ------------------------------------------------------------------------------------------------ commands
def plan_from_prompt(prompt, band):
    """run area_planner.py plan --from-prompt into a temporary file; (plan, output text). Raises InboxError (exit 2
    when no endpoint is set)"""
    tmp = tempfile.mkdtemp(prefix='areainbox.')
    try:
        out = os.path.join(tmp, 'plan.json')
        cmd = [sys.executable, '-I', os.path.join(HERE, 'area_planner.py'), 'plan', '--from-prompt', prompt, '--out', out]
        if band:
            cmd += ['--level', str(band[0]), str(band[1])]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        text = proc.stdout + proc.stderr
        if proc.returncode == 2:
            e = InboxError(text.strip() + '\n\nOr write the plan yourself and run: area_inbox.py new --plan PLAN.json')
            e.code = 2
            raise e
        if proc.returncode != 0 or not os.path.isfile(out):
            raise InboxError('the planner did not give a valid plan:\n' + text.strip())
        return load_json(out), text
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def cmd_new(a, inbox=INBOX, plans_dirs=None):
    if bool(a.from_prompt) == bool(a.plan):
        raise InboxError('new needs exactly one of --from-prompt TEXT and --plan FILE')
    band = tuple(a.level) if a.level else None
    if a.from_prompt:
        plan, _ = plan_from_prompt(a.from_prompt, band)
        prompt = a.from_prompt
    else:
        plan = load_json(a.plan)
        prompt = a.prompt or ''
    if band and not a.from_prompt:
        plan['level'] = [band[0], band[1]]
    if a.id:
        plan['id'] = a.id
    pid = plan.get('id')
    d = entry_dir(inbox, pid)
    taken = [os.path.join(p, pid + '.json') for p in (plans_dirs or [PLANS] + OTHER_PLAN_DIRS)]
    if os.path.exists(d) or any(os.path.exists(t) for t in taken):
        raise InboxError('the id %s is taken (an inbox entry or a plan of server/tools/areaplan/); use --id' % pid)
    res, notes = compile_checked(plan)
    for n in notes:
        print(n)
    tmp = tempfile.mkdtemp(prefix='areainbox.')
    try:
        sums = write_compiled(res, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    meta = make_meta(plan, res, 'pending', prompt, a.note, sums)
    os.makedirs(d)
    dump_json(plan, os.path.join(d, 'plan.json'), indent=2, sort_keys=False)
    dump_json(meta, os.path.join(d, 'meta.json'))
    s = meta['stats']
    print('%s: pending. %d tiles, %d walkable, %d monsters on %d points, %.2f per 100 walkable' % (
        pid, s['tiles'], s['walkable'], s['monsters'], s['spawn_points'], s['per100']))
    print('entry: %s' % d)
    print('next: commit it; the owner opens it with the map editor (Windows fetch-areas.bat after '
          'chaos-ctl areas-publish) and says approve; then `area_inbox.py approve %s`.' % pid)
    return 0


def cmd_list(a, inbox=INBOX):
    rows = []
    for pid in entries(inbox):
        m, _ = read_entry(inbox, pid)
        rows.append(m)
    if a.json:
        print(json.dumps([dict(id=m['id'], name=m['name'], status=m['status'], level=m['level'], size=m['size']) for m in rows],
                         indent=1))
        return 0
    if not rows:
        print('the inbox is empty')
    for m in rows:
        lv = m.get('level') or ['?', '?']
        sz = m.get('size') or ['?', '?']
        print('%-24s %-9s levels %s-%s  %sx%s  %s' % (m['id'], m['status'], lv[0], lv[1], sz[0], sz[1], m['name']))
    return 0


def cmd_check(a, inbox=INBOX):
    ids = a.ids or entries(inbox)
    bad = 0
    for pid in ids:
        meta, plan = read_entry(inbox, pid)
        if meta.get('schema') != SCHEMA or meta.get('id') != pid or meta.get('status') not in STATUSES:
            print('%s: meta.json is not a %s entry with a known status' % (pid, SCHEMA))
            bad += 1
            continue
        if plan is None:
            if meta['status'] != 'installed':
                print('%s: plan.json is missing' % pid)
                bad += 1
            continue
        if plan.get('id') != pid:
            print('%s: plan.json has the id %s' % (pid, plan.get('id')))
            bad += 1
            continue
        try:
            compile_checked(plan)
            print('%s: ok (%s)' % (pid, meta['status']))
        except InboxError as e:
            print('%s: %s' % (pid, e))
            bad += 1
    return 1 if bad else 0


def cmd_approve(a, inbox=INBOX):
    meta, plan = read_entry(inbox, a.id)
    if meta['status'] != 'pending':
        raise InboxError('%s is %s, not pending' % (a.id, meta['status']))
    compile_checked(plan)
    meta['status'] = 'approved'
    if a.note:
        meta['note'] = a.note
    dump_json(meta, os.path.join(entry_dir(inbox, a.id), 'meta.json'))
    print('%s: approved. `promote %s` moves the plan to server/tools/areaplan/plans/.' % (a.id, a.id))
    return 0


def find_assets(path=None, env=None):
    """the render inputs (items.otb, items.xml, Tibia.dat, Tibia.spr) in a folder: the paths, or None"""
    env = os.environ if env is None else env
    path = path or env.get('AREAINBOX_ASSETS')
    if not path or not os.path.isdir(path):
        return None
    got = [os.path.join(path, n) for n in ASSET_FILES]
    return got if all(os.path.isfile(p) for p in got) else None


def note_text(meta):
    lv = meta.get('level') or ['?', '?']
    s = meta['stats']
    lines = ['%s (%s)' % (meta['name'], meta['id']), 'status: %s' % meta['status'],
             'levels %s-%s, %s, %s x %s tiles, %s floor(s)' % (lv[0], lv[1], meta.get('biome'), meta['size'][0], meta['size'][1],
                                                              meta.get('floors', 1)),
             '%d walkable tiles, %d monsters on %d points, %.2f per 100 walkable' % (
                 s['walkable'], s['monsters'], s['spawn_points'], s['per100'])]
    if meta.get('prompt'):
        lines.append('asked: ' + meta['prompt'])
    if meta.get('note'):
        lines.append('note: ' + meta['note'])
    lines.append('')
    lines.append('Open %s.otbm in the map editor (open-map-editor.bat PATH). Say "approve %s" in the chat to keep it, or '
                 'what to change.' % (meta['id'], meta['id']))
    return '\n'.join(lines) + '\n'


def build_entry(inbox, pid, out_dir, assets=None):
    """OUT_DIR/pid/ with the editor files. Returns (dir, messages)"""
    meta, plan = read_entry(inbox, pid)
    if plan is None:
        raise InboxError('%s has no plan.json (it is installed: the plan is in server/tools/areaplan/plans/)' % pid)
    res, _ = compile_checked(plan)
    msgs = []
    dest = os.path.join(out_dir, pid)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    sums = write_compiled(res, dest)
    shutil.rmtree(os.path.join(dest, 'data'), ignore_errors=True)  # the chest script is for the server, not the editor
    sums = {n: h for n, h in sums.items() if os.path.isfile(os.path.join(dest, n))}
    if sums != meta.get('compiled_sha256'):
        msgs.append('note: the compiled files differ from the ones made when the entry was created (the generator or its '
                    'tables changed since); the files in %s are the current ones' % dest)
    shutil.copyfile(os.path.join(entry_dir(inbox, pid), 'plan.json'), os.path.join(dest, 'plan.json'))
    with open(os.path.join(dest, 'NOTE.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(note_text(meta))
    got = find_assets(assets)
    if got is None:
        msgs.append('pictures skipped: no render inputs (--assets DIR or $AREAINBOX_ASSETS with %s)' % ', '.join(ASSET_FILES))
    else:
        import area_plan_compile as PC
        try:
            for p, miss in PC.render_floors(res, dest, *got):
                msgs.append('picture %s' % os.path.basename(p))
        except Exception as e:  # numpy or Pillow missing, an unreadable pair: the files stay useful without pictures
            msgs.append('pictures skipped: %s: %s' % (type(e).__name__, e))
    names = sorted(n for n in os.listdir(dest) if os.path.isfile(os.path.join(dest, n)) and n != 'files.txt')
    with open(os.path.join(dest, 'files.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for n in names:
            f.write('%s  %s\n' % (sha256_file(os.path.join(dest, n)), n))
    return dest, msgs


def cmd_build(a, inbox=INBOX):
    dest, msgs = build_entry(inbox, a.id, a.out_dir, a.assets)
    for m in msgs:
        print(m)
    print(dest)
    return 0


def ascii_line(text):
    return re.sub(r'[^A-Za-z0-9 .,\'()-]', '', text or '')[:60]


def cmd_publish(a, inbox=INBOX):
    want = [s for s in a.status.split(',') if s]
    for s in want:
        if s not in STATUSES:
            raise InboxError('unknown status %s' % s)
    os.makedirs(a.out_dir, exist_ok=True)
    listing, index, failed = [], [], 0
    for pid in entries(inbox):
        meta, plan = read_entry(inbox, pid)
        if meta['status'] not in want or plan is None:
            continue
        try:
            dest, msgs = build_entry(inbox, pid, a.out_dir, a.assets)
        except InboxError as e:
            print('%s: skipped: %s' % (pid, e))
            failed += 1
            continue
        for m in msgs:
            print('%s: %s' % (pid, m))
        lv = meta.get('level') or [0, 0]
        listing.append('%s|%s|%s-%s|%s' % (pid, meta['status'], lv[0], lv[1], ascii_line(meta['name'])))
        index.append(dict(id=pid, name=meta['name'], status=meta['status'], level=meta.get('level'),
                          files=sorted(n for n in os.listdir(dest) if os.path.isfile(os.path.join(dest, n)))))
    with open(os.path.join(a.out_dir, 'list.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(l + '\n' for l in listing))
    dump_json(index, os.path.join(a.out_dir, 'index.json'))
    print('published %d area(s) into %s%s' % (len(listing), a.out_dir, ' (%d skipped, see above)' % failed if failed else ''))
    return 0


def box_of(plan):
    o = plan.get('origin')
    if not o:
        return None
    return (o['x'], o['y'], o['z'], plan['size'][0], plan['size'][1])


def overlaps(b, plans_dirs, own_id):
    """the ids of other plans whose box (any z: the frames and the world spawn overlap across floors) comes within MARGIN
    tiles of box b"""
    hit = []
    for d in plans_dirs:
        if not os.path.isdir(d):
            continue
        for n in sorted(os.listdir(d)):
            if not n.endswith('.json'):
                continue
            try:
                p = load_json(os.path.join(d, n))
            except (ValueError, OSError):
                continue
            o = box_of(p) if isinstance(p, dict) and 'size' in p else None
            if not o or p.get('id') == own_id:
                continue
            if b[0] < o[0] + o[3] + MARGIN and o[0] < b[0] + b[3] + MARGIN \
                    and b[1] < o[1] + o[4] + MARGIN and o[1] < b[1] + b[4] + MARGIN:
                hit.append(p.get('id', n))
    return hit


def cmd_promote(a, inbox=INBOX, plans=PLANS, plans_dirs=None):
    meta, plan = read_entry(inbox, a.id)
    if meta['status'] != 'approved':
        raise InboxError('%s is %s: only an approved entry is promoted (approve %s)' % (a.id, meta['status'], a.id))
    if plan is None:
        raise InboxError('%s has no plan.json' % a.id)
    if a.origin:
        plan['origin'] = dict(x=a.origin[0], y=a.origin[1], z=a.origin[2])
    if not plan.get('origin'):
        raise InboxError('the plan has no origin (where the area goes on the world map). Give one with --origin X Y Z: '
                         'the plans of server/tools/areaplan/plans/ use z 8 or 9 in the open parts of x 14900-17500, '
                         'y 14300-15200; the install refuses a spot the map already uses (install_content_areas.py '
                         '--dry-run on the live map says)')
    dirs = plans_dirs if plans_dirs is not None else [plans] + OTHER_PLAN_DIRS
    clash = overlaps(box_of(plan), dirs, a.id)
    if clash and not a.force:
        raise InboxError('the origin %s lands on %s (any z, within %d tiles); pick another with --origin, or --force'
                         % (plan['origin'], ', '.join(clash), MARGIN))
    target = os.path.join(plans, a.id + '.json')
    if os.path.exists(target):
        raise InboxError('%s already exists' % target)
    compile_checked(plan)
    dump_json(plan, target, indent=2, sort_keys=False)
    d = entry_dir(inbox, a.id)
    os.remove(os.path.join(d, 'plan.json'))
    meta['status'] = 'installed'
    meta['promoted_to'] = 'server/tools/areaplan/plans/%s.json' % a.id
    meta['compiled_sha256'] = {}
    dump_json(meta, os.path.join(d, 'meta.json'))
    print('%s: moved to %s (status installed)' % (a.id, target))
    print('Remaining, nothing else is wired by this command:')
    print('  1. the install: python3 -I server/tools/install_content_areas.py DATA_DIR --dry-run, then without it (the live map;')
    print('     it gives the plan a teleport slot by level band; hunt_teleports_config.lua `plans` is optional: it only')
    print('     names the display monster; raise `modules` there if the room has no slot left)')
    print('  2. in server/: luajit tools/progression_model.lua --check, luajit tests/hunt_teleports_test.lua, and the')
    print('     checks of the area planner CI step (python3 -I server/tools/area_planner.py validate / compile)')
    print('  3. server/README.md (the hunt table) and ROADMAP.md')
    return 0


def cmd_remove(a, inbox=INBOX):
    meta, _ = read_entry(inbox, a.id)
    if meta['status'] == 'installed':
        raise InboxError('%s is installed: its plan lives in server/tools/areaplan/plans/' % a.id)
    shutil.rmtree(entry_dir(inbox, a.id))
    print('%s: removed' % a.id)
    return 0


def parser():
    p = argparse.ArgumentParser(prog='area_inbox.py', description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    n = sub.add_parser('new')
    n.add_argument('--from-prompt')
    n.add_argument('--plan')
    n.add_argument('--prompt', help='the owner words to keep with a --plan entry')
    n.add_argument('--level', nargs=2, type=int, metavar=('LO', 'HI'))
    n.add_argument('--id')
    n.add_argument('--note')
    ls = sub.add_parser('list')
    ls.add_argument('--json', action='store_true')
    c = sub.add_parser('check')
    c.add_argument('ids', nargs='*')
    ap = sub.add_parser('approve')
    ap.add_argument('id')
    ap.add_argument('--note')
    b = sub.add_parser('build')
    b.add_argument('id')
    b.add_argument('out_dir')
    b.add_argument('--assets')
    pu = sub.add_parser('publish')
    pu.add_argument('out_dir')
    pu.add_argument('--status', default='approved,pending')
    pu.add_argument('--assets')
    pr = sub.add_parser('promote')
    pr.add_argument('id')
    pr.add_argument('--origin', nargs=3, type=int, metavar=('X', 'Y', 'Z'))
    pr.add_argument('--force', action='store_true')
    rm = sub.add_parser('remove')
    rm.add_argument('id')
    return p


COMMANDS = dict(new=cmd_new, list=cmd_list, check=cmd_check, approve=cmd_approve, build=cmd_build, publish=cmd_publish,
                promote=cmd_promote, remove=cmd_remove)


def main(argv=None, inbox=INBOX):
    a = parser().parse_args(argv)
    try:
        return COMMANDS[a.cmd](a, inbox=inbox)
    except InboxError as e:
        print(e)
        return getattr(e, 'code', 1)


if __name__ == '__main__':
    sys.exit(main())
