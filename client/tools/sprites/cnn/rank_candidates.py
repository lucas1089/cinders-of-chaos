"""Use the trained critic: rank AI candidates per piece, check against the human picks, score any folder of PNGs.

    python3 -I rank_candidates.py rank  --weights W/critic.pt --cands sets_v2/raw_full --picks sets_v2/picks.csv --out P
    python3 -I rank_candidates.py score --weights W/critic.pt --kind sword --out P/name.png a.png b.png ...
    python3 -I rank_candidates.py curves --metrics W/critic_metrics.json [--metrics ...] --out P/curves.png

Candidate folders: <set>_<piece> (32x32 cands), A_pair_<p1>_<p2> (64x32, first round, set sunsworn) and
P__<set>_<piece1>__<set>_<piece2> (64x32): the left half is the first piece, the right half the second. Every
candidate is re-centred on its alpha box before scoring. The last word of the piece names the kind (PIECE_KIND).
Score = P(real) x P(intended kind); both parts are printed. A variant A pick in picks.csv (slot full, left or right)
is matched to the first round's set (sunsworn), so it also covers the pair folders.
"""
import argparse
import csv
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
from PIL import Image, ImageDraw

import cnnlib as C

PIECE_KIND = {'sword': 'sword', 'axe': 'axe', 'club': 'club', 'wand': 'rod', 'rod': 'rod', 'bow': 'distance',
              'crossbow': 'distance', 'arrow': 'ammo', 'bolt': 'ammo', 'shield': 'shield', 'helmet': 'helmet',
              'armor': 'armor', 'legs': 'legs', 'boots': 'boots', 'ring': 'ring', 'amulet': 'amulet',
              'backpack': 'misc', 'spellbook': 'misc'}
ROUND1_SET = 'sunsworn'


def score(model, X, kind):
    pk, pr = C.critic_scores(model, X)
    pkind = pk[:, C.KINDS.index(kind)]
    return pr, pkind, pr * pkind, pk.argmax(1)


def human_picks(path):
    out = {}
    for r in csv.DictReader(open(path, newline='')):
        if r['variant'] != 'A':
            continue
        if (r['slot'] == 'full' and r['tag'] == 'A_' + r['piece']) or (
                r['slot'] in ('left', 'right') and r['tag'].startswith('A_pair_')):
            out[f"{ROUND1_SET}_{r['piece']}"] = int(r['cand'])
    return out


def centre(img):
    a = img[..., 3] > 0
    if not a.any():
        return img
    ys, xs = np.nonzero(a)
    dy = (31 - ys.max() - ys.min()) // 2
    dx = (31 - xs.max() - xs.min()) // 2
    return np.roll(np.roll(img, dy, 0), dx, 1)


def candidate_groups(root):
    """Yield (piece_name, [(cand_id, 32x32 RGBA)]) for every candidate folder layout under root."""
    groups = {}
    for d in sorted(os.listdir(root)):
        full = os.path.join(root, d)
        if not os.path.isdir(full):
            continue
        if d.startswith('A_pair_'):
            p1, p2 = d[len('A_pair_'):].split('_')
            names = (f'{ROUND1_SET}_{p1}', f'{ROUND1_SET}_{p2}')
        elif d.startswith('P__'):
            names = tuple(d[3:].split('__'))
        else:
            names = (d,)
        for f in sorted(x for x in os.listdir(full) if x.endswith('.png')):
            cid = int(f[5:7])
            if len(names) == 1:
                halves = (C.load_png(os.path.join(full, f)),)
            else:
                a = C.binarize(np.asarray(Image.open(os.path.join(full, f)).convert('RGBA')))
                halves = (a[:32, :32], a[:32, 32:64])
            for n, h in zip(names, halves):
                groups.setdefault(n, []).append((cid, centre(np.ascontiguousarray(h))))
    return sorted(groups.items())


def cmd_rank(a):
    model = C.load_critic(a.weights)
    picks = human_picks(a.picks) if a.picks else {}
    os.makedirs(a.out, exist_ok=True)
    report = []
    for d, items in candidate_groups(a.cands):
        kind = PIECE_KIND[d.rsplit('_', 1)[1]]
        cid = [c for c, _ in items]
        X = np.stack([im for _, im in items])
        pr, pkind, comb, pred = score(model, X, kind)
        order = np.argsort(-comb, kind='stable')
        rec = dict(piece=d, kind=kind, n=len(items), top=[cid[i] for i in order[:5]],
                   top_score=[round(float(comb[i]), 3) for i in order[:5]],
                   top_by_real=[cid[i] for i in np.argsort(-pr, kind='stable')[:5]],
                   mean_real=round(float(pr.mean()), 3), kind_agree=round(float((pred == C.KINDS.index(kind)).mean()), 3))
        if d in picks:
            h = cid.index(picks[d])
            rec['human'] = picks[d]
            rec['human_rank'] = int(np.where(order == h)[0][0]) + 1
            rec['human_rank_by_real'] = int(np.where(np.argsort(-pr, kind='stable') == h)[0][0]) + 1
            rec['human_score'] = [round(float(pr[h]), 3), round(float(pkind[h]), 3)]
        report.append(rec)
        print(json.dumps(rec), flush=True)
        # sheet: 16 per row, best first, caption = score x100, * marks the human pick
        rows = []
        for r0 in range(0, len(order), 16):
            sel = order[r0:r0 + 16]
            caps = [('*' if d in picks and cid[i] == picks[d] else '') + f'{cid[i]}:{int(comb[i] * 100)}' for i in sel]
            rows.append((f'rank {r0 + 1}-{r0 + len(sel)}', [X[i] for i in sel], caps))
        C.slot_rows(rows, zoom=2, label_w=90, cap=f'{d} ({kind}): critic order, caption cand:score; * human pick'
                    ).save(os.path.join(a.out, f'rank_{d}.png'))
    hum = [r for r in report if 'human' in r]
    if hum:
        pct = [(r['human_rank'] - 1) / max(1, r['n'] - 1) for r in hum]
        pct_r = [(r['human_rank_by_real'] - 1) / max(1, r['n'] - 1) for r in hum]
        print(f'human picks: {len(hum)}; mean rank percentile by score {np.mean(pct):.2f}, by real {np.mean(pct_r):.2f}'
              f' (0 = critic agrees fully, 0.5 = chance); in critic top 5: {sum(r["human_rank"] <= 5 for r in hum)}',
              flush=True)
    json.dump(report, open(os.path.join(a.out, 'rank_report.json'), 'w'), indent=1)
    # summary strip: top 5 per piece at 1x and 4x
    rows = []
    imgs = {d: dict(items) for d, items in candidate_groups(a.cands)}
    for rec in report:
        ims = [imgs[rec['piece']][c] for c in rec['top']]
        caps = [str(c) for c in rec['top']]
        if 'human' in rec:
            ims += [None, imgs[rec['piece']][rec['human']]]
            caps += ['', f"human {rec['human']} r{rec['human_rank']}"]
        rows.append((rec['piece'], ims, caps))
    for z in (1, 4):
        C.slot_rows(rows, zoom=z, label_w=130, cap='critic top 5 per piece | human pick and its critic rank'
                    ).save(os.path.join(a.out, f'rank_top5_{z}x.png'))


def cmd_score(a):
    model = C.load_critic(a.weights)
    X = np.stack([C.load_png(p) for p in a.files])
    pr, pkind, comb, pred = score(model, X, a.kind)
    for p, r, k, c, pd in zip(a.files, pr, pkind, comb, pred):
        print(f'{os.path.basename(p):40s} real {r:.3f} kind({a.kind}) {k:.3f} score {c:.3f} predicted {C.KINDS[pd]}')
    print(f'mean real {pr.mean():.3f} mean kind {pkind.mean():.3f} mean score {comb.mean():.3f}')
    if a.out:
        caps = [f'{int(c * 100)}' for c in comb]
        rows = [(a.kind, list(X[i:i + 16]), caps[i:i + 16]) for i in range(0, len(X), 16)]
        C.slot_rows(rows, zoom=2).save(a.out)


def plot(series, title, path, w=520, h=220):
    """series: list of (name, xs, ys, colour). Plain line chart with PIL."""
    im = Image.new('RGB', (w, h), (250, 248, 244))
    d = ImageDraw.Draw(im)
    l, r, t, b = 46, w - 120, 22, h - 26
    xs = [x for s in series for x in s[1]]
    ys = [y for s in series for y in s[2]]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    if y1 == y0:
        y1 = y0 + 1
    pad = (y1 - y0) * 0.05
    y0, y1 = y0 - pad, y1 + pad
    d.text((l, 4), title, fill=(30, 30, 30))
    d.line([(l, b), (r, b)], fill=(120, 120, 120))
    d.line([(l, t), (l, b)], fill=(120, 120, 120))
    for i in range(5):
        v = y0 + (y1 - y0) * i / 4
        yy = b - (b - t) * i / 4
        d.line([(l, yy), (r, yy)], fill=(225, 222, 216))
        d.text((4, yy - 6), f'{v:.3g}', fill=(80, 80, 80))
    d.text((l, b + 6), f'{x0:g}', fill=(80, 80, 80))
    d.text((r - 30, b + 6), f'{x1:g}', fill=(80, 80, 80))
    for j, (name, sx, sy, col) in enumerate(series):
        pts = [(l + (r - l) * (x - x0) / max(1e-9, x1 - x0), b - (b - t) * (y - y0) / (y1 - y0)) for x, y in zip(sx, sy)]
        if len(pts) > 1:
            d.line(pts, fill=col, width=2)
        d.text((r + 8, t + j * 14), name, fill=col)
    im.save(path)


def cmd_curves(a):
    cols = [(31, 119, 180), (214, 39, 40), (44, 160, 44), (148, 103, 189), (255, 127, 14), (23, 190, 207)]
    tiles = []
    for mp in a.metrics:
        M = json.load(open(mp))
        H = M['history']
        name = os.path.basename(mp).replace('_metrics.json', '')
        tmp = a.out + f'.{name}'
        if 'epoch' in H[0]:
            ep = [h['epoch'] for h in H]
            plot([('kind loss', ep, [h['loss_kind'] for h in H], cols[0]),
                  ('real loss', ep, [h['loss_real'] for h in H], cols[1])], f'{name}: training loss / epoch',
                 tmp + '.a.png')
            plot([('kind acc', ep, [h['kind_acc'] for h in H], cols[0]),
                  ('kind bal acc', ep, [h['kind_bal_acc'] for h in H], cols[3]),
                  ('real acc', ep, [h['real_acc'] for h in H], cols[1]),
                  ('AUC', ep, [h['auc'] for h in H], cols[2])], f'{name}: held-out metrics / epoch', tmp + '.b.png')
            tiles += [tmp + '.a.png', tmp + '.b.png']
        else:
            st = [h['step'] for h in H]
            plot([('loss (EMA)', st, [h['loss'] for h in H], cols[0])], f'{name}: diffusion loss / step', tmp + '.a.png')
            tiles.append(tmp + '.a.png')
    ims = [Image.open(p) for p in tiles]
    out = Image.new('RGB', (1040, 220 * ((len(ims) + 1) // 2)), (255, 255, 255))
    for i, im in enumerate(ims):
        out.paste(im, ((i % 2) * 520, (i // 2) * 220))
    out.save(a.out)
    for p in tiles:
        os.remove(p)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('rank')
    r.add_argument('--weights', required=True)
    r.add_argument('--cands', required=True)
    r.add_argument('--picks')
    r.add_argument('--out', required=True)
    s = sub.add_parser('score')
    s.add_argument('--weights', required=True)
    s.add_argument('--kind', required=True, choices=C.KINDS)
    s.add_argument('--out')
    s.add_argument('files', nargs='+')
    c = sub.add_parser('curves')
    c.add_argument('--metrics', action='append', required=True)
    c.add_argument('--out', required=True)
    a = ap.parse_args()
    {'rank': cmd_rank, 'score': cmd_score, 'curves': cmd_curves}[a.cmd](a)


if __name__ == '__main__':
    main()
