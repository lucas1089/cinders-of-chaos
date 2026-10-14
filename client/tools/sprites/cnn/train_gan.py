"""Train a small conditional DCGAN on the item dataset, CPU, time-boxed. A second, cheaper generator next to the
diffusion model (train_gen.py), so both can be compared on the same previews.

    python3 -I train_gan.py --data DATA.npz --pseudo WEIGHTS_DIR/pseudo.npz --out WEIGHTS_DIR [--minutes 45]

Same conditions as train_gen.py (item kind, material code; kind from the dataset label, else the critic's guess when
it is 90%+ sure). Generator: z + embeddings -> 4x4 -> 32x32 RGBA (transposed convs, batch norm). Discriminator:
spectral-norm convs with a projection head on kind and material, hinge loss. Real items get a random 0-2 px shift,
never a flip: our items keep one drawing direction. Writes gan_g.pt, gan_metrics.json and a sample sheet into
--out/gan_progress/ every 10 minutes.
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
import torch.nn as nn
import torch.nn.functional as F

import cnnlib as C
from train_gen import FOCUS, conditions

ZD = 96


class G(nn.Module):
    def __init__(self, w=32):
        super().__init__()
        self.ek = nn.Embedding(C.NK + 1, 32)
        self.em = nn.Embedding(C.NM + 1, 16)
        self.fc = nn.Linear(ZD + 48, 8 * w * 16)
        self.w = w

        def up(i, o):
            return nn.Sequential(nn.ConvTranspose2d(i, o, 4, 2, 1, bias=False), nn.BatchNorm2d(o), nn.ReLU(True),
                                 nn.Conv2d(o, o, 3, 1, 1, bias=False), nn.BatchNorm2d(o), nn.ReLU(True))
        self.net = nn.Sequential(nn.BatchNorm2d(8 * w), nn.ReLU(True), up(8 * w, 4 * w), up(4 * w, 2 * w),
                                 up(2 * w, w), nn.Conv2d(w, 4, 3, 1, 1), nn.Tanh())

    def forward(self, z, k, m):
        h = self.fc(torch.cat([z, self.ek(k), self.em(m)], 1)).view(-1, 8 * self.w, 4, 4)
        x = self.net(h)
        # transparent pixels carry rgb 0, like the training data (cnnlib.to_diff)
        a = x[:, 3:4]
        return torch.cat([x[:, :3] * (a > 0).float(), a], 1)


class D(nn.Module):
    def __init__(self, w=32):
        super().__init__()
        sn = nn.utils.spectral_norm
        self.f = nn.Sequential(sn(nn.Conv2d(4, w, 3, 1, 1)), nn.LeakyReLU(0.2, True),
                               sn(nn.Conv2d(w, 2 * w, 4, 2, 1)), nn.LeakyReLU(0.2, True),
                               sn(nn.Conv2d(2 * w, 2 * w, 3, 1, 1)), nn.LeakyReLU(0.2, True),
                               sn(nn.Conv2d(2 * w, 4 * w, 4, 2, 1)), nn.LeakyReLU(0.2, True),
                               sn(nn.Conv2d(4 * w, 4 * w, 3, 1, 1)), nn.LeakyReLU(0.2, True),
                               sn(nn.Conv2d(4 * w, 8 * w, 4, 2, 1)), nn.LeakyReLU(0.2, True))
        self.out = sn(nn.Linear(8 * w, 1))
        self.pk = sn(nn.Embedding(C.NK + 1, 8 * w))
        self.pm = sn(nn.Embedding(C.NM + 1, 8 * w))

    def forward(self, x, k, m):
        h = self.f(x).sum((2, 3))
        return self.out(h).squeeze(1) + (h * self.pk(k)).sum(1) + (h * self.pm(m)).sum(1)


def load_gan(path):
    g = G()
    g.load_state_dict(torch.load(path, map_location='cpu'))
    g.eval()
    return g


@torch.no_grad()
def gan_sample(g, kind_idx, mats, seed):
    gen = torch.Generator().manual_seed(seed)
    z = torch.randn(len(mats), ZD, generator=gen)
    x = g(z, torch.full((len(mats),), kind_idx, dtype=torch.long), torch.tensor(mats, dtype=torch.long))
    return [C.binarize(a) for a in C.from_diff(x)]


def sheet(g, path):
    rows = []
    for j, n in enumerate(FOCUS):
        rows.append((n, gan_sample(g, C.KINDS.index(n), [0, 1, 2, 5, 6, 8], 123 + j)))
    C.slot_rows(rows, zoom=2).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--pseudo')
    ap.add_argument('--out', required=True)
    ap.add_argument('--minutes', type=float, default=45)
    ap.add_argument('--bs', type=int, default=64)
    ap.add_argument('--threads', type=int, default=0)
    a = ap.parse_args()
    torch.set_num_threads(a.threads or os.cpu_count() or 4)
    T0 = time.time()
    torch.manual_seed(0)
    rng = np.random.default_rng(0)
    Dd = np.load(a.data)
    P = np.load(a.pseudo) if a.pseudo else None
    keep = np.array([not s.startswith('icons') for s in Dd['src']])
    X = np.stack([C.binarize(x) for x in Dd['X'][keep]])
    k, m = conditions(Dd, P)
    k, m = k[keep], m[keep]
    wts = np.where(np.isin(k, [C.KINDS.index(n) for n in FOCUS]), 4.0, 1.0)
    wts /= wts.sum()
    kt, mt = torch.from_numpy(k), torch.from_numpy(m)
    g, d = G(), D()
    og = torch.optim.Adam(g.parameters(), lr=2e-4, betas=(0.0, 0.9))
    od = torch.optim.Adam(d.parameters(), lr=4e-4, betas=(0.0, 0.9))
    print('data ready', round(time.time() - T0, 1), 's', flush=True)
    print('params G', sum(p.numel() for p in g.parameters()), 'D', sum(p.numel() for p in d.parameters()), flush=True)
    os.makedirs(a.out, exist_ok=True)
    prog = C.ensure(os.path.join(a.out, 'gan_progress'))
    hist = []
    t0 = last = time.time()
    step = 0
    rd = rg = 0.0
    while (time.time() - t0) / 60 < a.minutes:
        idx = rng.choice(len(X), size=a.bs, p=wts)
        xr = C.to_diff(np.stack([C.shift(X[i], rng) for i in idx]))
        kb, mb = kt[idx], mt[idx]
        z = torch.randn(a.bs, ZD)
        xf = g(z, kb, mb)
        ld = F.relu(1 - d(xr, kb, mb)).mean() + F.relu(1 + d(xf.detach(), kb, mb)).mean()
        od.zero_grad()
        ld.backward()
        od.step()
        lg = -d(xf, kb, mb).mean()
        og.zero_grad()
        lg.backward()
        og.step()
        rd = 0.98 * rd + 0.02 * float(ld.detach()) if step else float(ld.detach())
        rg = 0.98 * rg + 0.02 * float(lg.detach()) if step else float(lg.detach())
        step += 1
        el = (time.time() - t0) / 60
        if step % 200 == 0:
            hist.append(dict(step=step, minutes=round(el, 2), loss_d=rd, loss_g=rg))
            print(f'step {step} D {rd:.3f} G {rg:.3f} {el:.1f} min', flush=True)
        if time.time() - last > 600:
            last = time.time()
            g.eval()
            sheet(g, os.path.join(prog, f'step_{step:06d}.png'))
            g.train()
            torch.save(g.state_dict(), os.path.join(a.out, 'gan_g.pt'))
    g.eval()
    torch.save(g.state_dict(), os.path.join(a.out, 'gan_g.pt'))
    json.dump(dict(args=vars(a), history=hist), open(os.path.join(a.out, 'gan_metrics.json'), 'w'))
    sheet(g, os.path.join(prog, f'step_{step:06d}_final.png'))
    print('done', step, 'steps', flush=True)


if __name__ == '__main__':
    main()
