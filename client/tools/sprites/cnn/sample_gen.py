"""Sample the generators (diffusion, DCGAN), clean the output to pixel art, refine other items img2img, previews.

    python3 -I sample_gen.py samples --weights W --data DATA.npz --out P [--pixellab sets_v2/items/A] [--forge DIR]
    python3 -I sample_gen.py refine  --weights W --out P/refine.png --kind sword a.png b.png ...

samples: for each generator with weights in W (diffusion gen_ema.pt, DCGAN gan_g.pt), per kind one block: real
items (random, from the dataset), generator raw output (random seeds, not picked), the same cleaned
(cnnlib.clean_pixel_art) and the critic's best 8 of 48 cleaned samples. Then a comparison board per piece: real,
item_forge (if --forge has <set>_<piece>.png), PixelLab A (<piece>.png), each generator best and random.
refine: SDEdit img2img at two strengths (noise level 0.3 and 0.5), material code read from the input, then cleaned;
critic scores before and after are printed.
"""
import argparse
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import torch

import cnnlib as C

FOCUS = ('sword', 'axe', 'club', 'rod', 'distance', 'shield', 'helmet', 'armor', 'legs', 'boots', 'ring', 'amulet')
PIECES = {'sword': 'sword', 'axe': 'axe', 'shield': 'shield', 'helmet': 'helmet', 'armor': 'armor', 'legs': 'legs',
          'boots': 'boots', 'rod': 'rod'}


def load_gen(wdir):
    st = json.load(open(os.path.join(wdir, 'gen_metrics.json')))['args']
    m = C.UNet(st['ch'], tuple(int(v) for v in st['mult'].split(',')))
    m.load_state_dict(torch.load(os.path.join(wdir, 'gen_ema.pt'), map_location='cpu'))
    m.eval()
    return m


def gen(model, diff, kind, mats, seed, steps=50, guide=2.5):
    g = torch.Generator().manual_seed(seed)
    k = torch.full((len(mats),), C.KINDS.index(kind))
    x = diff.sample(model, k, torch.tensor(mats), steps=steps, guide=guide, gen=g)
    return [C.binarize(a) for a in C.from_diff(x)]


def samplers(wdir):
    """name -> fn(kind, mats, seed) -> list of uint8 32x32 RGBA, for each generator whose weights exist"""
    out = {}
    if os.path.exists(os.path.join(wdir, 'gen_ema.pt')):
        model, diff = load_gen(wdir), C.Diffusion()
        out['diffusion'] = lambda kind, mats, seed: gen(model, diff, kind, mats, seed)
    if os.path.exists(os.path.join(wdir, 'gan_g.pt')):
        from train_gan import gan_sample, load_gan
        g = load_gan(os.path.join(wdir, 'gan_g.pt'))
        out['dcgan'] = lambda kind, mats, seed: gan_sample(g, C.KINDS.index(kind), mats, seed)
    return out


def cmd_samples(a):
    torch.set_num_threads(a.threads or os.cpu_count() or 4)
    gens = samplers(a.weights)
    critic = C.load_critic(os.path.join(a.weights, 'critic.pt'))
    D = np.load(a.data)
    pair = np.array([s == 'pair' for s in D['src']])
    os.makedirs(a.out, exist_ok=True)
    t0 = time.time()
    summary, best, rnd_store = {}, {}, {}
    for name, fn in gens.items():
        rng = np.random.default_rng(5)
        blocks = []
        for kind in FOCUS:
            ki = C.KINDS.index(kind)
            real_idx = np.nonzero((D['y'] == ki) & pair)[0]
            if len(real_idx) < 8:
                real_idx = np.nonzero(D['y'] == ki)[0]
            real = [C.binarize(D['X'][i]) for i in rng.choice(real_idx, 8, replace=False)]
            mats = [[0, 1, 2, 5, 6, 8, 3, 4][i % 8] for i in range(48)]
            raw = fn(kind, mats, 1000 + ki)
            cl = [C.clean_pixel_art(x) for x in raw]
            pk, pr = C.critic_scores(critic, np.stack(cl))
            _, prr = C.critic_scores(critic, np.stack(raw))
            comb = pr * pk[:, ki]
            order = np.argsort(-comb)
            pkreal, prreal = C.critic_scores(critic, np.stack([C.binarize(D['X'][i]) for i in real_idx[:400]]))
            summary.setdefault(name, {})[kind] = dict(
                gen_raw_real=float(prr.mean()), gen_clean_real=float(pr.mean()), gen_clean_kind=float(pk[:, ki].mean()),
                gen_clean_kind_top1=float((pk.argmax(1) == ki).mean()), real_items_real=float(prreal.mean()),
                real_items_kind=float(pkreal[:, ki].mean()))
            print(name, kind, json.dumps({k: round(v, 3) for k, v in summary[name][kind].items()}), flush=True)
            best[name, kind] = [cl[i] for i in order[:8]]
            rnd_store[name, kind] = cl[:8]
            blocks.append([(f'{kind}: real', real), (f'{name} raw (random)', raw[:8]),
                           ('cleaned (same)', cl[:8]),
                           ('critic best 8/48', best[name, kind], [f'{int(comb[i] * 100)}' for i in order[:8]])])
        for z in (1, 4):
            for j in range(0, len(blocks), 4):
                rows = [r for blk in blocks[j:j + 4] for r in blk]
                C.slot_rows(rows, zoom=z, label_w=150,
                            cap=f'{name} generator samples (not hand picked except last row)'
                            ).save(os.path.join(a.out, f'{name}_samples_{j // 4 + 1}_{z}x.png'))
    # comparison board per piece
    rng = np.random.default_rng(6)
    rows = []
    for piece, kind in PIECES.items():
        ki = C.KINDS.index(kind)
        real_idx = np.nonzero((D['y'] == ki) & pair)[0]
        cells = [C.binarize(D['X'][i]) for i in rng.choice(real_idx, 2, replace=False)] + [None]
        forge = [C.load_png(p) for p in sorted(glob.glob(os.path.join(a.forge, f'*_{piece}.png')))[:2]] if a.forge else []
        cells += (forge or [None]) + [None]
        pl = os.path.join(a.pixellab or '', f'{piece}.png')
        cells += ([C.load_png(pl)] if a.pixellab and os.path.exists(pl) else [None])
        for name in gens:
            cells += [None] + best[name, kind][:2] + rnd_store[name, kind][:1]
        rows.append((piece, cells))
    cap = 'real x2 | item_forge x2 | PixelLab pick | ' + ' | '.join(f'{n}: critic-best x2, random x1' for n in gens)
    for z in (1, 4):
        C.slot_rows(rows, zoom=z, label_w=70, cap=cap).save(os.path.join(a.out, f'compare_{z}x.png'))
    json.dump(summary, open(os.path.join(a.out, 'gen_scores.json'), 'w'), indent=1)
    print(f'sampling {(time.time() - t0) / 60:.1f} min')


def cmd_refine(a):
    torch.set_num_threads(a.threads or os.cpu_count() or 4)
    model, diff = load_gen(a.weights), C.Diffusion()
    critic = C.load_critic(os.path.join(a.weights, 'critic.pt'))
    ki = C.KINDS.index(a.kind)
    X = np.stack([C.load_png(p) for p in a.files])
    mats = torch.tensor([C.material_code(x) for x in X])
    rows = [('input', list(X))]
    _, pr0 = C.critic_scores(critic, X)
    caps0 = [f'{int(v * 100)}' for v in pr0]
    rows[0] = ('input', list(X), caps0)
    res = dict(input=float(pr0.mean()))
    for s in (0.3, 0.5):
        g = torch.Generator().manual_seed(7)
        x = diff.sample(model, torch.full((len(X),), ki), mats, steps=max(10, int(50 * s)), guide=2.0,
                        x=C.to_diff(X), start=s, gen=g)
        out = [C.clean_pixel_art(C.binarize(v)) for v in C.from_diff(x)]
        _, pr = C.critic_scores(critic, np.stack(out))
        res[f'strength_{s}'] = float(pr.mean())
        rows.append((f'refined {s}', out, [f'{int(v * 100)}' for v in pr]))
    print(a.kind, json.dumps({k: round(v, 3) for k, v in res.items()}))
    for z in (1, 4):
        C.slot_rows(rows, zoom=z, label_w=90, cap=f'img2img refine ({a.kind}); caption = critic P(real) x100'
                    ).save(a.out.replace('.png', f'_{z}x.png'))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('samples')
    s.add_argument('--weights', required=True)
    s.add_argument('--data', required=True)
    s.add_argument('--out', required=True)
    s.add_argument('--pixellab')
    s.add_argument('--forge')
    s.add_argument('--threads', type=int, default=0)
    r = sub.add_parser('refine')
    r.add_argument('--weights', required=True)
    r.add_argument('--out', required=True)
    r.add_argument('--kind', required=True, choices=C.KINDS)
    r.add_argument('--threads', type=int, default=0)
    r.add_argument('files', nargs='+')
    a = ap.parse_args()
    {'samples': cmd_samples, 'refine': cmd_refine}[a.cmd](a)


if __name__ == '__main__':
    main()
