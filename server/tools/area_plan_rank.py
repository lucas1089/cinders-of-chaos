"""Candidate ranking of an area plan (O738, server/README.md "Area planner candidates and reach repair (O738)").

`area_planner.py compile|stats PLAN --candidates N` compiles the plan with N seeds and keeps the best. Candidate 1 is
the plan's own seed (plan `seed`, or the one from its id), so N = 1 is the plain compile and its bytes; candidate k
takes seed_of(base, k). Each compile is scored by the scorers we already have, as penalty points off 100:
  qa      30 per QA error, 3 per QA warning (the outline lines left out: `shape` counts them)
  shape   area_plan_shape.py on every floor: 10 per limit broken, plus 20 x the larger mirror overlap (mean of floors)
  reach   100 x the share of walkable design tiles cut off and closed with rock (area_plan_compile.reach_stats
          left_share) plus 100 x the share the entry cannot reach (share)
  deco    100 x the share of walkable tiles with 3+ decoration items (spam_share), 5 when the monsters per 100 walkable
          tiles of the area lie outside 1.5-5 (docs/MAP_GUIDE.md)
  look    5 per finding of audit_plan_look.look_findings
A seed whose layout or compile fails scores None and ranks last. The best is the highest score, a tie goes to the lower
candidate number (so the plan's own seed wins a tie). Deterministic: the same plan and N give the same table.
Pure Python over compile_plan; the tests feed it plans of the examples.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_core as C  # noqa: E402
import area_plan_shape as SH  # noqa: E402

PARTS = ('qa', 'shape', 'reach', 'deco', 'look')


def seed_of(base, k):
    """the seed of candidate k (1 = the plan's own); stays in the schema's 1..2000000000"""
    if k <= 1:
        return base
    return (base + (k - 1) * 104729) % 2000000000 or 1


def score_parts(plan, res, look=True):
    """{part: penalty points} of one compile result"""
    qa = sum(30 if lvl == 'ERROR' else 3 for lvl, m in res['qa'] if 'outline of floor' not in m)
    oz = res['origin'][2]
    breaks, syms = 0, []
    cfg = SH.rules()
    for f in range(plan['floors']):
        cells = {(x, y) for x, y, z in res['footprint'] if z == oz + f}
        if len(cells) < cfg['min_floor_tiles']:
            continue
        sc = SH.scores(cells)
        breaks += len(SH.breaches(sc, cfg))
        syms.append(max(sc['sym_lr'], sc['sym_tb']))
    shape = 10 * breaks + 20.0 * (sum(syms) / len(syms) if syms else 0.0)
    r = res['reach']
    reach = 100.0 * (r['left_share'] + r['share'])
    st = res['stats']
    deco = 100.0 * st['decoration']['spam_share'] + (5 if st['monsters'] and not 1.5 <= st['per100'] <= 5.0 else 0)
    lk = 0
    if look:
        import audit_plan_look as LK
        lk = 5 * len(LK.look_findings(plan, res))
    return dict(qa=qa, shape=round(shape, 2), reach=round(reach, 2), deco=round(deco, 2), look=lk)


def rank(plan, n, compile_fn=None, look=True, **kw):
    """-> (rows, best_res). rows: [dict(k, seed, score, parts, error)] in candidate order; best_res the compile of the
    best row (None when every seed failed). compile_fn(plan) defaults to area_plan_compile.compile_plan(plan, **kw)."""
    import area_plan_compile as PC
    compile_fn = compile_fn or (lambda p: PC.compile_plan(p, **kw))
    base = C.plan_seed(plan)
    rows, best, best_res = [], None, None
    for k in range(1, max(1, n) + 1):
        p = dict(plan)
        p['seed'] = seed_of(base, k)
        row = dict(k=k, seed=p['seed'], score=None, parts=None, error=None)
        try:
            res = compile_fn(p)
        except PC.CompileError as e:
            row['error'] = str(e).splitlines()[0][:120]
            rows.append(row)
            continue
        parts = score_parts(p, res, look)
        row['parts'] = parts
        row['score'] = round(100.0 - sum(parts.values()), 2)
        rows.append(row)
        if best is None or row['score'] > best['score']:
            best, best_res = row, res
    return rows, best_res


def table(plan_id, rows):
    """the text table of a ranking, best first, the plan's own seed marked"""
    ranked = sorted(rows, key=lambda r: (r['score'] is None, -(r['score'] or 0), r['k']))
    out = ['candidates of %s (%d seeds; penalty points off 100, server/tools/area_plan_rank.py)' % (plan_id, len(rows)),
           '%-4s %-4s %-11s %7s  %s' % ('rank', 'cand', 'seed', 'score', '  '.join('%6s' % p for p in PARTS))]
    for i, r in enumerate(ranked, 1):
        mark = '*' if r['k'] == 1 else ' '
        if r['score'] is None:
            out.append('%-4d %-3d%s %-11d %7s  failed: %s' % (i, r['k'], mark, r['seed'], '-', r['error']))
        else:
            out.append('%-4d %-3d%s %-11d %7.2f  %s' % (i, r['k'], mark, r['seed'], r['score'],
                                                     '  '.join('%6.2f' % r['parts'][p] for p in PARTS)))
    out.append('* = the plan\'s own seed. Keep a better seed by writing it into the plan\'s "seed".')
    return '\n'.join(out) + '\n'
