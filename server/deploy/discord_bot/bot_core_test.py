#!/usr/bin/env python3
"""Tests for bot_core.py (O324): no Discord, no Claude, no network. A throwaway SQLite file or memory.

Covers: the settings (missing and bad keys named without their values), who may use the commands, the hourly limit,
cleaning of pings, images picked for Claude, the classification parsing (repairs, a duplicate id that is not open),
a new bug, a duplicate (count, same author counted once, severity raised, critical alert), status changes (allowed and
refused, duplicate merge, fixed_at, reopening), the list order, export, the daily summary and when it is due, patch
notes (parsing, the site files in the format of patchnotes_core.lua, never overwriting, embeds within the Discord
limits, hand-written notes) and the copy of new notes.

usage: python3 -I server/deploy/discord_bot/bot_core_test.py
"""
import datetime
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bot_core as core  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def raises(fn, text=None):
    try:
        fn()
    except core.BotError as e:
        return text is None or text in str(e)
    return False


class Clock:
    def __init__(self, t=1_800_000_000):
        self.t = t

    def __call__(self):
        return self.t


GOOD = dict(DISCORD_TOKEN='T' * 40, ANTHROPIC_API_KEY='sk-ant-' + 'K' * 30, DISCORD_OWNER_ID='111111111111111111',
            DISCORD_BUGS_CHANNEL_ID='222222222222222222', DISCORD_PATCH_CHANNEL_ID='333333333333333333')


def cls(kind='bug', title='Item some do depot', summary='O item some.', sev='alto', steps=None, dup=None):
    return {'kind': kind, 'title': title, 'summary': summary, 'severity': sev, 'repro_steps': steps or [],
            'duplicate_of': dup}


def test_config():
    c = core.load_config(GOOD)
    check(c.owner_id == 111111111111111111 and c.model == 'claude-sonnet-5-5' and c.fallbacks and c.daily_hour == 9,
          'config defaults')
    check(c.db_path.endswith('bugs.sqlite3') and c.patchnotes_dir.endswith('patchnotes'), 'config paths')
    c = core.load_config(dict(GOOD, DISCORD_BOT_MODEL='claude-opus-5-5', DISCORD_BOT_FALLBACKS='0',
                              DISCORD_GUILD_ID='444444444444', DISCORD_BOT_DAILY_HOUR='8', DISCORD_BOT_USER_LIMIT_HOUR='5'))
    check(c.model == 'claude-opus-5-5' and not c.fallbacks and c.guild_id == 444444444444 and c.daily_hour == 8
          and c.per_user_hour == 5, 'config overrides')
    bad = dict(GOOD)
    del bad['DISCORD_TOKEN']
    bad['ANTHROPIC_API_KEY'] = ' '
    try:
        core.load_config(bad)
        check(False, 'missing keys refused')
    except core.BotError as e:
        check('DISCORD_TOKEN' in str(e) and 'ANTHROPIC_API_KEY' in str(e), 'missing keys named')
    secret = 'sk-ant-SECRETSECRETSECRET1234567890'
    try:
        core.load_config(dict(GOOD, DISCORD_OWNER_ID='abc', ANTHROPIC_API_KEY=secret))
        check(False, 'bad id refused')
    except core.BotError as e:
        check('DISCORD_OWNER_ID' in str(e) and secret not in str(e) and 'abc' not in str(e), 'bad id named, value not shown')
    check(raises(lambda: core.load_config(dict(GOOD, DISCORD_TOKEN='a b' * 10)), 'DISCORD_TOKEN'), 'token with a space')
    check(raises(lambda: core.load_config(dict(GOOD, DISCORD_BOT_DAILY_HOUR='30')), 'DISCORD_BOT_DAILY_HOUR'), 'bad hour')


def test_auth_and_limit():
    check(core.is_authorized(5, [], 5), 'owner')
    check(not core.is_authorized(6, [1, 2], 5), 'stranger')
    check(core.is_authorized(6, [1, 9], 5, 9), 'admin role')
    check(not core.is_authorized(6, [1], 5, 9), 'no admin role')
    check(not core.is_authorized(6, None, 5, None), 'no roles at all')
    rl = core.RateLimiter(2, 100)
    check(rl.allow('a', 0) and rl.allow('a', 10) and not rl.allow('a', 20), 'limit hit')
    check(rl.allow('b', 20), 'limit per author')
    check(rl.allow('a', 111), 'limit window slides')


def test_clean():
    s = core.clean('oi @everyone e @here <@123> <@!456> <@&789>\x00‮ fim', 200)
    check('@everyone' not in s and '@here' not in s and '<@123>' not in s and '<@!456>' not in s and '<@&789>' not in s
          and '\x00' not in s and '‮' not in s, 'pings and controls removed: ' + repr(s))
    check(core.clean('x' * 50, 10) == 'xxxxxxx...', 'capped')
    check(core.clean_line('a\n\n  b\tc', 50) == 'a b c', 'one line')


def test_images():
    check(core.image_media_type('a.PNG', None) == 'image/png', 'png by name')
    check(core.image_media_type('a.bin', 'image/webp; x=1') == 'image/webp', 'webp by type')
    check(core.image_media_type('a.txt', 'text/plain') is None, 'text is no image')
    atts = [('a.png', 'image/png', 100), ('b.txt', 'text/plain', 5), ('c.jpg', None, core.MAX_IMAGE_BYTES + 1),
            ('d.gif', 'image/gif', 10), ('e.png', 'image/png', 0)] + [('f%d.png' % i, 'image/png', 9) for i in range(8)]
    idx = core.pick_images(atts)
    check(idx[:2] == [0, 3] and len(idx) == core.MAX_IMAGES and 2 not in idx and 4 not in idx, 'images picked: %s' % idx)
    blocks = core.image_blocks([('image/png', b'\x89PNG')])
    check(blocks[0]['type'] == 'image' and blocks[0]['source']['type'] == 'base64'
          and blocks[0]['source']['media_type'] == 'image/png' and blocks[0]['source']['data'] == 'iVBORw==', 'vision block')


def test_prompt_and_parse():
    openb = [{'id': 3, 'title': 'T', 'summary': 'S', 'severity': 'alto', 'report_count': 2},
             {'id': 4, 'title': 'U', 'summary': 'V', 'severity': 'baixo', 'report_count': 9}]
    content = core.classify_content('o jogo travou', [('image/png', b'x')], openb)
    check(content[0]['type'] == 'text' and content[1]['type'] == 'image' and len(content) == 2, 'content blocks')
    t = content[0]['text']
    check(t.index('#4') < t.index('#3') and 'o jogo travou' in t and '<message>' in t, 'most reported first, message wrapped')
    check('none' in core.open_bugs_block([]), 'no open bugs')
    many = [{'id': i, 'title': 't', 'summary': 's', 'severity': 'baixo', 'report_count': 1} for i in range(200)]
    check(core.open_bugs_block(many).count('\n') == core.MAX_OPEN_FOR_PROMPT, 'open list capped')

    raw = json.dumps({'kind': 'bug', 'title': 'Crash ao abrir o mapa', 'summary': 'Fecha sozinho.', 'severity': 'critico',
                      'repro_steps': ['Abrir o mapa', ' ', 3], 'duplicate_of': 3})
    c = core.parse_classification(raw, [3, 4])
    check(c['kind'] == 'bug' and c['severity'] == 'critico' and c['duplicate_of'] == 3
          and c['repro_steps'] == ['Abrir o mapa', '3'], 'good answer: %s' % c)
    c = core.parse_classification('```json\n' + raw + '\n```', [3])
    check(c['duplicate_of'] == 3, 'code fence')
    c = core.parse_classification('Aqui está: ' + raw + ' pronto', [3])
    check(c['title'].startswith('Crash'), 'text around the json')
    check(core.parse_classification(raw, [9])['duplicate_of'] is None, 'duplicate of a bug that is not open')
    check(core.parse_classification(json.dumps({'kind': 'bug', 'title': 't', 'summary': 's', 'severity': 'x',
                                                'duplicate_of': True}), [1])['duplicate_of'] is None, 'bool is no id')
    c = core.parse_classification(json.dumps({'is_bug': True, 'summary': 'algo quebrou', 'severity': 'Médio'}))
    check(c['kind'] == 'bug' and c['severity'] == 'medio' and c['title'] == 'algo quebrou', 'old shape repaired')
    c = core.parse_classification(json.dumps({'kind': 'suggestion', 'title': 'Mais slots', 'summary': 'x',
                                              'severity': 'alto', 'duplicate_of': 3}), [3])
    check(c['kind'] == 'suggestion' and c['duplicate_of'] is None, 'a suggestion has no duplicate')
    check(core.parse_classification('{"kind":"nope"}')['kind'] == 'chat', 'unknown kind is chat')
    check(raises(lambda: core.parse_classification('sem json'), 'JSON'), 'no json refused')
    check(raises(lambda: core.parse_classification('[1,2]'), 'objeto'), 'a list refused')
    c = core.parse_classification(json.dumps({'kind': 'bug', 'title': '@everyone ' + 'x' * 300, 'summary': 'y',
                                              'severity': 'baixo'}))
    check(len(c['title']) <= 100 and '@everyone' not in c['title'], 'title cleaned and capped')


def test_new_and_duplicate():
    clock = Clock()
    st = core.Store(':memory:', clock)
    r = core.handle_classification(st, cls('chat'), 1, 10)
    check(r['action'] == 'ignored' and st.list('todos') == [], 'chat ignored')
    r = core.handle_classification(st, cls('suggestion'), 2, 10)
    check(r['action'] == 'ignored', 'suggestion ignored')
    r = core.handle_classification(st, cls(steps=['a', 'b']), 3, 10, 'https://discord.com/channels/1/2/3')
    check(r['action'] == 'new' and r['bug_id'] == 1 and not r['notify_owner'] and r['bug']['repro'] == ['a', 'b'], 'new bug')
    check(core.handle_classification(st, cls(), 3, 10)['action'] == 'known', 'same message again is known')
    check(len(st.list('todos')) == 1, 'known creates nothing')
    r = core.handle_classification(st, cls(dup=1, sev='baixo'), 4, 11)
    check(r['action'] == 'duplicate' and r['count'] == 2 and not r['same_author'] and not r['notify_owner'], 'duplicate')
    r = core.handle_classification(st, cls(dup=1), 5, 11)
    check(r['action'] == 'duplicate' and r['count'] == 2 and r['same_author'], 'same author counted once')
    check(len(st.reports_of(1)) == 3, 'the report is still kept')
    r = core.handle_classification(st, cls(dup=1, sev='critico'), 6, 12)
    check(r['count'] == 3 and r['bug']['severity'] == 'critico' and r['notify_owner'], 'duplicate raises severity, alerts')
    r = core.handle_classification(st, cls(dup=1, sev='critico'), 7, 13)
    check(not r['notify_owner'], 'alert only once')
    # a duplicate of a bug that is closed becomes a new bug
    st.set_status(1, 'corrigido')
    r = core.handle_classification(st, cls(dup=1), 8, 14)
    check(r['action'] == 'new' and r['bug_id'] == 2, 'duplicate of a fixed bug is a new bug')
    r = core.handle_classification(st, cls(dup=99), 9, 14)
    check(r['action'] == 'new', 'duplicate of a missing bug is a new bug')
    r = core.handle_classification(st, cls(sev='critico', title='Dupe de itens'), 10, 15)
    check(r['action'] == 'new' and r['notify_owner'], 'new critical bug alerts the owner')
    alert = core.owner_alert(r['bug'], 'https://x')
    check('crítico' in alert.lower() and 'Dupe de itens' in alert and 'https://x' in alert, 'alert text')
    new = core.handle_classification(st, cls(), 11, 16)
    rt = core.reply_text(new, '<@16>')
    check('Bug #%d' % new['bug_id'] in rt and '<@16>' in rt and 'alta' not in rt, 'reply new')
    dr = core.handle_classification(st, cls(dup=new['bug_id']), 12, 17)
    check('já estava' in core.reply_text(dr, '<@17>') and 'agora são 2' in core.reply_text(dr, '<@17>'), 'reply duplicate')
    sa = core.handle_classification(st, cls(dup=new['bug_id']), 13, 17)
    check('já tinha relatado' in core.reply_text(sa, '<@17>'), 'reply same author')
    check(core.reply_text({'action': 'ignored'}, 'x') == '', 'silent for chat')


def test_status():
    clock = Clock()
    st = core.Store(':memory:', clock)
    a = core.handle_classification(st, cls(title='A', sev='medio'), 1, 1)['bug_id']
    b = core.handle_classification(st, cls(title='B', sev='alto'), 2, 2)['bug_id']
    core.handle_classification(st, cls(dup=b), 3, 3)
    core.handle_classification(st, cls(dup=a), 4, 2)  # author 2 also reports a
    check(st.set_status(a, 'confirmado', note='visto')['note'] == 'visto', 'confirm with a note')
    check(raises(lambda: st.set_status(a, 'nada'), 'inválido'), 'unknown status')
    check(raises(lambda: st.set_status(99, 'corrigido'), 'não existe'), 'unknown bug')
    check(raises(lambda: st.set_status(a, 'duplicado'), 'duplicado_de'), 'duplicate needs the original')
    check(raises(lambda: st.set_status(a, 'duplicado', a), 'dele mesmo'), 'not a duplicate of itself')
    check(raises(lambda: st.set_status(a, 'duplicado', 99), 'não existe'), 'original must exist')
    check(st.set_status(a, 'em_andamento')['status'] == 'em_andamento', 'in progress')
    clock.t += 100
    f = st.set_status(a, 'corrigido')
    check(f['status'] == 'corrigido' and f['fixed_at'] == clock.t, 'fixed_at set')
    check(raises(lambda: st.set_status(a, 'em_andamento'), 'Corrigido'), 'fixed cannot go to in progress')
    check(raises(lambda: st.set_status(a, 'nao_e_bug'), 'não dá'), 'fixed is not "not a bug"')
    check([x['id'] for x in st.fixed_unpatched()] == [a], 'fixed and unpatched')
    st.mark_patched([a, b], '1.0')
    check(st.fixed_unpatched() == [] and st.get(a)['patched_in'] == '1.0' and st.get(b)['patched_in'] is None,
          'patched marks only fixed bugs')
    r = st.set_status(a, 'aberto')
    check(r['status'] == 'aberto' and r['fixed_at'] is None and r['patched_in'] is None, 'reopened clears fix and patch')
    # duplicate merge: b has reports of authors 2 and 3, a has authors 1 and 2
    cb, ca = st.get(b)['report_count'], st.get(a)['report_count']
    d = st.set_status(a, 'duplicado', b, 'mesmo bug')
    merged = st.get(b)
    check(d['duplicate_of'] == b and d['status'] == 'duplicado', 'marked duplicate')
    check(merged['report_count'] == cb + 1 and ca == 2, 'only the new author is added: %s %s' % (merged['report_count'], cb))
    check(len(st.reports_of(b)) == 4 and st.reports_of(a) == [], 'reports moved')
    check(merged['severity'] == 'alto', 'severity keeps the worst')
    c = core.handle_classification(st, cls(title='C'), 20, 20)['bug_id']
    check(raises(lambda: st.set_status(c, 'duplicado', a), 'já é duplicado'), 'original cannot be a duplicate')
    check(st.set_status(a, 'aberto')['duplicate_of'] is None, 'reopening clears duplicate_of')
    check(st.set_status(c, 'nao_e_bug')['status'] == 'nao_e_bug', 'not a bug')
    check(st.set_status(c, 'nao_e_bug')['status'] == 'nao_e_bug', 'same status is a no-op')
    check(core.handle_classification(st, cls(dup=c), 21, 21)['action'] == 'new', 'a not-a-bug is not open for duplicates')


def test_lists_and_views():
    clock = Clock()
    st = core.Store(':memory:', clock)
    ids = {}
    for name, sev, n in (('low-many', 'baixo', 5), ('high-one', 'alto', 1), ('high-three', 'alto', 3), ('crit', 'critico', 1)):
        ids[name] = core.handle_classification(st, cls(title=name, sev=sev), len(ids) + 100, 500 + len(ids))['bug_id']
        for k in range(n - 1):
            core.handle_classification(st, cls(dup=ids[name], sev=sev), 1000 + ids[name] * 10 + k, 900 + ids[name] * 10 + k)
    order = [b['title'] for b in st.list()]
    check(order == ['crit', 'high-three', 'high-one', 'low-many'], 'order by severity then reports: %s' % order)
    st.set_status(ids['low-many'], 'corrigido')
    check([b['title'] for b in st.list('corrigido')] == ['low-many'] and len(st.list()) == 3, 'filter by status')
    check(len(st.list('todos')) == 4, 'all')
    check(raises(lambda: st.list('xyz'), 'desconhecido'), 'unknown filter')
    text = core.format_bug_list(st.list())
    check(text.splitlines()[0].startswith('#') and 'Crítico' in text.splitlines()[0], 'list line: ' + text)
    check(core.format_bug_list([]) == 'Nenhum bug nessa lista.', 'empty list')
    big = [{'id': i, 'title': 't' * 70, 'summary': '', 'severity': 'baixo', 'status': 'aberto', 'report_count': 1} for i in range(200)]
    out = core.format_bug_list(big)
    check(len(out) <= 1900 and 'e mais' in out.splitlines()[-1], 'long list is cut: %d' % len(out))
    d = core.format_bug_detail(st, ids['crit'])
    check('crit' in d and 'Crítico' in d and 'Aberto' in d, 'detail')
    check(raises(lambda: core.format_bug_detail(st, 999), 'não existe'), 'detail of a missing bug')
    md = core.export_markdown(st)
    check(md.startswith('# Bugs') and '## #%d: crit' % ids['crit'] in md and 'low-many' not in md, 'export open only')
    md = core.export_markdown(st, True)
    check('low-many' in md and '4 bugs' in md, 'export with closed')
    check('discord.com' not in md and '500' not in md, 'export holds no author ids')


def test_daily():
    clock = Clock(1_800_000_000)
    st = core.Store(':memory:', clock)
    empty = core.build_daily_summary(st)
    check('Nada aberto' in empty and 'Resumo diário' in empty, 'empty day')
    a = core.handle_classification(st, cls(title='Crash', sev='critico'), 1, 1)['bug_id']
    core.handle_classification(st, cls(title='Typo', sev='baixo'), 2, 2)
    core.handle_classification(st, cls(dup=a), 3, 3)
    old = core.handle_classification(st, cls(title='Velho', sev='medio'), 4, 4)['bug_id']
    clock.t += 3 * 86400
    st.set_status(old, 'corrigido')
    new = core.handle_classification(st, cls(title='Novo', sev='alto'), 5, 5)['bug_id']
    s = core.build_daily_summary(st)
    check('1 bug novo' in s and '1 corrigido' in s, 'last 24 hours: ' + s)
    check('crítico 1, alto 1, médio 0, baixo 1' in s, 'open by severity: ' + s)
    check('Críticos abertos' in s and '#%d' % a in s and 'Para olhar primeiro' in s, 'sections')
    check('sem patch note' in s, 'fixed waiting for a patch')
    check(len(s) <= 2000, 'fits a DM')
    tz = datetime.timezone(datetime.timedelta(hours=-3))
    d = lambda h, m=0, day=29: datetime.datetime(2026, 10, day, h, m, tzinfo=tz)  # noqa: E731
    check(not core.daily_due(d(8, 59), None), 'not before 09:00')
    check(core.daily_due(d(9, 0), None) and core.daily_due(d(9, 0), '2026-10-28'), 'due at 09:00')
    check(not core.daily_due(d(9, 30), '2026-10-29'), 'not twice a day')
    check(core.daily_due(d(12, 0), None), 'catch up after a late start')
    check(not core.daily_due(d(15, 0), None), 'no catch up after the window')
    check(core.daily_due(d(7, 0), None, hour=7) and not core.daily_due(d(6, 0), None, hour=7), 'other hour')
    check(core.daily_due(d(22, 0), None, hour=20, window_hours=6), 'window stops at midnight')


NOTES_JSON = {
    'pt': {'title': 'Cinzas e correções', 'intro': 'Uma semana calma.',
           'new': [{'lead': 'Novo chefe', 'text': 'O Guardião acordou.'}], 'changes': [],
           'fixes': [{'lead': '', 'text': 'Itens não somem mais do depósito.'}], 'balance': []},
    'en': {'title': 'Ashes and fixes', 'intro': 'A calm week.',
           'new': [{'lead': 'New boss', 'text': 'The Guardian woke up.'}], 'changes': [],
           'fixes': [{'lead': '', 'text': 'Items no longer vanish from the depot.'}], 'balance': []},
}


def test_patch_notes():
    p = core.parse_patch(json.dumps(NOTES_JSON))
    check(p['pt']['title'] == 'Cinzas e correções' and p['en']['fixes'][0]['text'].startswith('Items'), 'parse_patch')
    check(core.parse_patch('```\n' + json.dumps(NOTES_JSON) + '\n```')['pt']['intro'] == 'Uma semana calma.', 'fenced')
    check(raises(lambda: core.parse_patch(json.dumps({'pt': NOTES_JSON['pt']})), 'formato'), 'English missing')
    empty = dict(NOTES_JSON['pt'], new=[], fixes=[])
    check(raises(lambda: core.parse_patch(json.dumps({'pt': empty, 'en': empty})), 'vazias'), 'empty notes refused')
    check(core.parse_translation(json.dumps({'en': NOTES_JSON['en']}))['title'] == 'Ashes and fixes', 'translation')
    md = core.render_site_md(p['pt'], '2026-10-29', 'pt')
    check(md.splitlines()[0] == '# Cinzas e correções' and md.splitlines()[1] == 'Date: 2026-10-29', 'site header')
    check('## Novidades' in md and '## Correções' in md and '## Mudanças' not in md, 'site pt headings')
    check('- **Novo chefe.** O Guardião acordou.' in md and '- Itens não somem mais do depósito.' in md, 'site bullets')
    check('## New' in core.render_site_md(p['en'], '2026-10-29', 'en'), 'site en headings')

    h = core.parse_hand_written('Manutenção', {'new': '- Boss :: Um novo chefe\n\n* outro item', 'changes': '',
                                               'fixes': 'Corrigi X', 'balance': ' '})
    check(h['new'] == [{'lead': 'Boss', 'text': 'Um novo chefe'}, {'lead': '', 'text': 'outro item'}]
          and h['fixes'][0]['text'] == 'Corrigi X' and h['balance'] == [], 'hand written')
    back = core.parse_hand_written('T', core.notes_to_fields(h))
    check(back['new'] == h['new'], 'edit modal round trip')
    check(raises(lambda: core.parse_hand_written('', {'new': 'x'}), 'título'), 'title needed')
    check(raises(lambda: core.parse_hand_written('T', {}), 'vazias'), 'text needed')

    with tempfile.TemporaryDirectory() as tmp:
        d = os.path.join(tmp, 'notes')
        n1 = core.write_site_files(d, '2026-10-29', p['pt'], p['en'])
        n2 = core.write_site_files(d, '2026-10-29', p['pt'], p['en'])
        check(n1 == '2026-10-29' and n2 == '2026-10-29-2', 'never overwrites: %s %s' % (n1, n2))
        check(sorted(os.listdir(d)) == ['2026-10-29-2.md', '2026-10-29-2.pt-br.md', '2026-10-29.md', '2026-10-29.pt-br.md'],
              'both files written, no temp files left: %s' % os.listdir(d))
        check(open(os.path.join(d, '2026-10-29.md'), encoding='utf-8').read().startswith('# Ashes and fixes'), 'en file')
        dst = os.path.join(tmp, 'game')
        os.makedirs(dst)
        open(os.path.join(dst, '2026-10-29.md'), 'w').write('keep')
        open(os.path.join(d, '.hidden.md'), 'w').write('x')
        open(os.path.join(d, 'a b.md'), 'w').write('x')
        done = core.sync_new_notes(d, dst)
        check(sorted(done) == ['2026-10-29-2.md', '2026-10-29-2.pt-br.md', '2026-10-29.pt-br.md'], 'new notes copied: %s' % done)
        check(open(os.path.join(dst, '2026-10-29.md')).read() == 'keep', 'existing note kept')
        check(core.sync_new_notes(d, dst) == [], 'second sync copies nothing')
        check(core.sync_new_notes(os.path.join(tmp, 'none'), dst) == [], 'no source folder')


def test_embeds():
    p = core.parse_patch(json.dumps(NOTES_JSON))['pt']
    e = core.render_embeds(p, '0.9.3', '2026-10-29')
    check(len(e) == 1 and e[0]['title'] == 'Patch 0.9.3: Cinzas e correções' and e[0]['description'] == 'Uma semana calma.', 'embed head')
    names = [f['name'] for f in e[0]['fields']]
    check(names == ['Novidades', 'Correções'] and '**Novo chefe.** O Guardião' in e[0]['fields'][0]['value'], 'embed fields')
    check(e[0]['footer']['text'] == '2026-10-29', 'embed footer')
    big = dict(p, fixes=[{'lead': 'L%d' % i, 'text': 'x' * 390} for i in range(30)], new=[{'lead': '', 'text': 'y' * 390}] * 30)
    es = core.render_embeds(big, '', '2026-10-29')
    check(len(es) >= 2, 'long notes split into several embeds: %d' % len(es))
    for em in es:
        total = len(em.get('title', '')) + len(em.get('description', '')) + sum(len(f['name']) + len(f['value']) for f in em['fields'])
        check(total <= 6000 and len(em['fields']) <= 25 and all(len(f['value']) <= 1024 for f in em['fields']), 'embed within limits: %d' % total)
    check(es[0]['title'] == 'Cinzas e correções', 'no version, plain title')


def test_forum():
    check(core.in_bugs_channel(5, None, 5) and core.in_bugs_channel(9, 5, 5), 'the channel and a thread of it')
    check(not core.in_bugs_channel(9, 7, 5) and not core.in_bugs_channel(9, None, 5), 'other channels and threads')
    check(not core.in_bugs_channel(5, None, 0), 'no channel set')
    check(core.report_text('teste', 'teste: baú não abre.', True) == 'teste: baú não abre.\nteste', 'forum title in front')
    check(core.report_text('', 'baú não abre', True) == 'baú não abre', 'title alone')
    check(core.report_text('também comigo', 'baú não abre', False) == 'também comigo', 'a reply keeps its own text')
    check(core.report_text('o baú não abre', None, False) == 'o baú não abre', 'a plain channel message')


def main():
    for t in (test_config, test_auth_and_limit, test_clean, test_images, test_prompt_and_parse, test_new_and_duplicate,
              test_status, test_lists_and_views, test_daily, test_patch_notes, test_embeds, test_forum):
        t()
    print('bot_core_test: %s' % ('ok' if not failures else '%d failure(s)' % failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
