"""Train the CNN critic: item kind classifier + "real item of this game" scorer (real vs degraded/fake negatives).

    python3 -I train_critic.py --data DATA.npz --out WEIGHTS_DIR [--epochs 14] [--holdout-source pair]

Writes WEIGHTS_DIR/critic.pt (or critic_holdout_<src>.pt), a metrics json with the curves, and, for the main run,
pseudo.npz: the critic's kind guess for the unlabelled rows (used by the generator, confidence kept).
Icons from the library icon sets are a different drawing style (frontal RPG icons): left out unless --with-icons.
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

import cnnlib as C


def batches(n, bs, rng):
    p = rng.permutation(n)
    for i in range(0, n - bs + 1, bs):
        yield p[i:i + bs]


def make_fake_set(X, rng, per_type=None):
    out, ty = [], []
    for i in range(len(X)):
        j = rng.integers(len(X))
        im, t = C.make_negative(X[i], rng, other=X[j], kind=None if per_type is None else per_type)
        out.append(im)
        ty.append(t)
    return np.stack(out), np.array(ty)


def evaluate(model, Xt, yt, rng_seed=7):
    model.eval()
    rng = np.random.default_rng(rng_seed)
    pk, pr = C.critic_scores(model, Xt)
    lab = yt < C.NK
    acc = float((pk[lab].argmax(1) == yt[lab]).mean()) if lab.any() else float('nan')
    per = {}
    for k in range(C.NK):
        s = yt == k
        if s.any():
            per[C.KINDS[k]] = [float((pk[s].argmax(1) == k).mean()), int(s.sum())]
    bal = float(np.mean([v[0] for v in per.values()])) if per else float('nan')
    real_ok = float((pr > 0.5).mean())
    neg = {}
    scores_neg = []
    for t, name in enumerate(C.NEG_TYPES):
        Xf, _ = make_fake_set(Xt, rng, per_type=t)
        _, pf = C.critic_scores(model, Xf)
        neg[name] = float((pf < 0.5).mean())
        scores_neg.append(pf)
    sn = np.concatenate(scores_neg)
    # AUC real vs all negatives (rank statistic)
    allv = np.concatenate([pr, sn])
    ranks = allv.argsort().argsort() + 1
    auc = float((ranks[:len(pr)].sum() - len(pr) * (len(pr) + 1) / 2) / (len(pr) * len(sn)))
    model.train()
    return dict(kind_acc=acc, kind_bal_acc=bal, per_kind=per, real_acc=real_ok, neg_reject=neg, auc=auc,
                n_test=int(len(Xt)), n_test_labelled=int(lab.sum()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--epochs', type=int, default=14)
    ap.add_argument('--bs', type=int, default=128)
    ap.add_argument('--holdout-source')
    ap.add_argument('--with-icons', action='store_true')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--threads', type=int, default=0, help='torch threads (0: all cores; use fewer on a shared machine)')
    a = ap.parse_args()
    torch.set_num_threads(a.threads or os.cpu_count() or 4)
    torch.manual_seed(a.seed)
    rng = np.random.default_rng(a.seed)
    D = np.load(a.data)
    X = np.stack([C.binarize(x) for x in D['X']])
    y = D['y'].astype(np.int64)
    src = D['src']
    keep = np.array([a.with_icons or not s.startswith('icons') for s in src])
    keep &= (X[..., 3] > 0).sum(axis=(1, 2)) >= 12
    X, y, src = X[keep], y[keep], src[keep]
    if a.holdout_source:
        te = np.array([s == a.holdout_source for s in src])
    else:
        te = rng.random(len(X)) < 0.15
    Xtr, ytr, Xte, yte = X[~te], y[~te], X[te], y[te]
    print(f'train {len(Xtr)} (labelled {(ytr < C.NK).sum()}), test {len(Xte)} (labelled {(yte < C.NK).sum()})',
          flush=True)
    cnt = np.bincount(ytr[ytr < C.NK], minlength=C.NK).astype(np.float32)
    w = torch.tensor((cnt.max() / np.maximum(cnt, 1)) ** 0.5, dtype=torch.float32)
    model = C.Critic()
    opt = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=1e-4)
    steps = a.epochs * (len(Xtr) // a.bs)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=2e-3, total_steps=steps)
    hist = []
    t0 = time.time()
    for ep in range(a.epochs):
        lk = lr_ = n = 0.0
        for idx in batches(len(Xtr), a.bs, rng):
            reals = np.stack([C.shift(Xtr[i], rng) for i in idx])
            oth = Xtr[rng.integers(len(Xtr), size=len(idx))]
            fakes = np.stack([C.make_negative(Xtr[i], rng, other=o)[0] for i, o in zip(idx, oth)])
            xb = C.to_tensor(np.concatenate([reals, fakes]))
            kl, rl = model(xb)
            tgt = torch.cat([torch.ones(len(idx)), torch.zeros(len(idx))])
            loss_r = F.binary_cross_entropy_with_logits(rl, tgt)
            yb = torch.from_numpy(ytr[idx])
            lab = yb < C.NK
            loss_k = F.cross_entropy(kl[:len(idx)][lab], yb[lab], weight=w) if lab.any() else torch.zeros(())
            loss = loss_r + loss_k
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            lk += float(loss_k.detach())
            lr_ += float(loss_r.detach())
            n += 1
        ev = evaluate(model, Xte, yte)
        rec = dict(epoch=ep + 1, loss_kind=lk / n, loss_real=lr_ / n, minutes=(time.time() - t0) / 60, **ev)
        hist.append(rec)
        print(f"ep {ep + 1} lk {lk / n:.3f} lr {lr_ / n:.3f} kind {ev['kind_acc']:.3f} bal {ev['kind_bal_acc']:.3f} "
              f"real {ev['real_acc']:.3f} auc {ev['auc']:.4f} {rec['minutes']:.1f} min", flush=True)
    os.makedirs(a.out, exist_ok=True)
    tag = 'critic' if not a.holdout_source else f'critic_holdout_{a.holdout_source}'
    torch.save(model.state_dict(), os.path.join(a.out, tag + '.pt'))
    json.dump(dict(args=vars(a), history=hist), open(os.path.join(a.out, tag + '_metrics.json'), 'w'), indent=1)
    if not a.holdout_source:
        model.eval()
        Xall = np.stack([C.binarize(x) for x in D['X']])
        pk, pr = C.critic_scores(model, Xall)
        np.savez_compressed(os.path.join(a.out, 'pseudo.npz'), kind=pk.argmax(1).astype(np.int16),
                            conf=pk.max(1).astype(np.float32), real=pr.astype(np.float32))
    print(json.dumps(hist[-1], indent=1))


if __name__ == '__main__':
    main()
