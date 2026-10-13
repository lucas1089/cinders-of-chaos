"""Train the small conditional diffusion generator (DDPM, U-Net, 32x32 RGBA) on the item dataset, CPU, time-boxed.

    python3 -I train_gen.py --data DATA.npz --pseudo WEIGHTS_DIR/pseudo.npz --out WEIGHTS_DIR [--minutes 180]

Condition: item kind (dataset label, else the critic's guess when it is 90%+ sure, else "null") and a material code
(dominant colour family of the item, cnnlib.MATERIALS). Both are dropped 15% of the time for classifier-free guidance.
Weapon and armour kinds are sampled 4x as often as the rest. Writes gen_ema.pt (EMA weights) every 15 minutes,
gen_metrics.json (loss curve) and a small sample sheet every 30 minutes into --out/gen_progress/.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

import cnnlib as C

FOCUS = ('sword', 'axe', 'club', 'rod', 'distance', 'shield', 'helmet', 'armor', 'legs', 'boots', 'ring', 'amulet')


def conditions(D, P):
    y = D['y'].astype(np.int64)
    k = y.copy()
    unl = y >= C.NK
    if P is not None:
        sure = unl & (P['conf'] >= 0.9)
        k[sure] = P['kind'][sure]
        k[unl & ~sure] = C.NK
    else:
        k[unl] = C.NK
    m = np.array([C.material_code(x) for x in D['X']], np.int64)
    return k, m


def sheet(model, diff, path, gen, steps=40):
    ks = [C.KINDS.index(n) for n in FOCUS]
    k = torch.tensor([kk for kk in ks for _ in range(6)])
    m = torch.tensor([[0, 1, 2, 5, 6, 8][i % 6] for i in range(len(k))])
    x = diff.sample(model, k, m, steps=steps, guide=2.0, gen=gen)
    imgs = [C.binarize(a) for a in C.from_diff(x)]
    rows = [(FOCUS[j], imgs[j * 6:(j + 1) * 6]) for j in range(len(FOCUS))]
    C.slot_rows(rows, zoom=2).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--pseudo')
    ap.add_argument('--out', required=True)
    ap.add_argument('--minutes', type=float, default=180)
    ap.add_argument('--bs', type=int, default=64)
    ap.add_argument('--ch', type=int, default=32)
    ap.add_argument('--mult', default='1,2,4')
    ap.add_argument('--lr', type=float, default=4e-4)
    ap.add_argument('--resume', action='store_true')
    ap.add_argument('--threads', type=int, default=0, help='torch threads (0: all cores; use fewer on a shared machine)')
    a = ap.parse_args()
    torch.set_num_threads(a.threads or os.cpu_count() or 4)
    torch.manual_seed(0)
    rng = np.random.default_rng(0)
    D = np.load(a.data)
    P = np.load(a.pseudo) if a.pseudo else None
    keep = np.array([not s.startswith('icons') for s in D['src']])
    X = np.stack([C.binarize(x) for x in D['X'][keep]])
    k, m = conditions(D, P)
    k, m = k[keep], m[keep]
    focus_idx = [C.KINDS.index(n) for n in FOCUS]
    wts = np.where(np.isin(k, focus_idx), 4.0, 1.0)
    wts /= wts.sum()
    print('rows', len(X), 'kind counts', {(C.KINDS + ('null',))[i]: int(c) for i, c in
                                          enumerate(np.bincount(k, minlength=C.NK + 1))}, flush=True)
    print('material counts', {C.MATERIALS[i]: int(c) for i, c in enumerate(np.bincount(m, minlength=C.NM))},
          flush=True)
    Xt = C.to_diff(X)
    kt, mt = torch.from_numpy(k), torch.from_numpy(m)
    mult = tuple(int(v) for v in a.mult.split(','))
    model = C.UNet(a.ch, mult)
    ema = C.UNet(a.ch, mult)
    os.makedirs(a.out, exist_ok=True)
    prog = os.path.join(a.out, 'gen_progress')
    os.makedirs(prog, exist_ok=True)
    hist, step0, done_min = [], 0, 0.0
    if a.resume and os.path.exists(os.path.join(a.out, 'gen_last.pt')):
        st = torch.load(os.path.join(a.out, 'gen_last.pt'))
        model.load_state_dict(st['model'])
        ema.load_state_dict(st['ema'])
        hist, step0, done_min = st['hist'], st['step'], st['minutes']
    else:
        ema.load_state_dict(model.state_dict())
    ema.eval()
    for p in ema.parameters():
        p.requires_grad_(False)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.0)
    if a.resume and os.path.exists(os.path.join(a.out, 'gen_last.pt')):
        opt.load_state_dict(st['opt'])
    diff = C.Diffusion()
    print('params', sum(p.numel() for p in model.parameters()), flush=True)
    t0 = time.time()
    last_save = last_sheet = t0
    step = step0
    run = 0.0
    gen = torch.Generator().manual_seed(123)
    while True:
        el = (time.time() - t0) / 60 + done_min
        if el >= a.minutes:
            break
        idx = torch.from_numpy(rng.choice(len(X), size=a.bs, p=wts))
        x0 = Xt[idx]
        kb, mb = kt[idx].clone(), mt[idx].clone()
        kb[torch.rand(a.bs) < 0.15] = C.NK
        mb[torch.rand(a.bs) < 0.15] = C.NM
        t = torch.randint(0, diff.T, (a.bs,))
        eps = torch.randn_like(x0)
        xt = diff.noise(x0, t, eps)
        lr = a.lr * min(1.0, (step + 1) / 500)
        for g in opt.param_groups:
            g['lr'] = lr
        loss = F.mse_loss(model(xt, t, kb, mb), eps)
        opt.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        dec = min(0.999, (1 + step) / (10 + step))
        with torch.no_grad():
            for pe, pm in zip(ema.parameters(), model.parameters()):
                pe.mul_(dec).add_(pm, alpha=1 - dec)
            for be, bm in zip(ema.buffers(), model.buffers()):
                be.copy_(bm)
        run = 0.98 * run + 0.02 * float(loss.detach()) if step > step0 else float(loss)
        step += 1
        if step % 100 == 0:
            hist.append(dict(step=step, minutes=round(el, 2), loss=run))
            print(f'step {step} loss {run:.4f} {el:.1f} min', flush=True)
        now = time.time()
        if now - last_save > 15 * 60:
            last_save = now
            torch.save(ema.state_dict(), os.path.join(a.out, 'gen_ema.pt'))
            torch.save(dict(model=model.state_dict(), ema=ema.state_dict(), opt=opt.state_dict(), hist=hist,
                            step=step, minutes=(now - t0) / 60 + done_min), os.path.join(a.out, 'gen_last.pt'))
            json.dump(dict(args=vars(a), history=hist), open(os.path.join(a.out, 'gen_metrics.json'), 'w'))
        if now - last_sheet > 30 * 60:
            last_sheet = now
            sheet(ema, diff, os.path.join(prog, f'step_{step:06d}.png'), gen)
    torch.save(ema.state_dict(), os.path.join(a.out, 'gen_ema.pt'))
    torch.save(dict(model=model.state_dict(), ema=ema.state_dict(), opt=opt.state_dict(), hist=hist, step=step,
                    minutes=(time.time() - t0) / 60 + done_min), os.path.join(a.out, 'gen_last.pt'))
    json.dump(dict(args=vars(a), history=hist), open(os.path.join(a.out, 'gen_metrics.json'), 'w'))
    sheet(ema, diff, os.path.join(prog, f'step_{step:06d}_final.png'), gen)
    print('done', step, 'steps', flush=True)


if __name__ == '__main__':
    main()
