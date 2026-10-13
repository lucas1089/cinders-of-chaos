# CNN sprite tools (experiment)

Convolutional models that learn from our 32x32 item art. Three parts:

- **Critic** (`train_critic.py`): a small CNN (437k parameters). One head predicts the item kind. The other
  scores "looks like a real item of this game" against degraded or fake negatives. Used to rank AI candidates
  (`rank_candidates.py rank`) and to score any PNGs (`rank_candidates.py score`).
- **Diffusion generator** (`train_gen.py`): a small conditional DDPM (U-Net, 3.5M parameters, 32x32 RGBA),
  conditioned on item kind and a material code. `sample_gen.py refine` uses it img2img (SDEdit) on other items,
  for example item_forge output.
- **DCGAN** (`train_gan.py`): a cheaper conditional GAN on the same data and conditions, for comparison.

Generator output is cleaned to pixel art: alpha 0/255, specks dropped, palette quantised, selective dark outline
(`cnnlib.clean_pixel_art`). `sample_gen.py samples` draws both generators next to real items, item_forge and
PixelLab.

No weights, datasets or previews are in git. They live in the session scratchpad (`cnn/data`, `cnn/weights`,
`cnn/previews`). Needs numpy, Pillow and PyTorch. The CPU wheel is enough:
`pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cpu`.

## Data sources

Read only, never copied into git:

- The live pair (things_custom23 from the `windows-assets` branch): 1x1 carried items, first sprite.
- Donor libraries B to V (`client/MANIFEST.md`, "Donor art libraries"; the sprite-libraries branch), same filter.
  Catalogue rows tagged "named character" or "branded" are skipped.
- The library item icon sets (`library/item_icons`). They are extracted but left out of training by default:
  they are frontal RPG icons, another drawing style (`--with-icons` to use them).
- Our own generated art (item_forge sets and variants) and our PixelLab outputs (`sets_v2/`). They are scored
  and compared only, never trained on. The critic's "real" class must stay shipped game art, else it would learn
  to approve the candidates it is meant to judge.

Kind labels come from the dat market category, else the cloth slot. Unlabelled rows stay "unknown". They count as
real art for the critic. The generators use the critic's kind guess where it is 90%+ sure.

## Excluded

- The spell effect pack (the "oblique spell effect set"). Its licence forbids training models.
  `build_dataset.py` refuses paths that name it. It only reads items, and pair items that share a sprite with
  any effect are dropped.
- The owner's reference sheets in `purchased_weto/`. Refused by path.

## Commands

    S=<scratchpad>; L=$S/library; T=client/tools/sprites/cnn
    python3 -I $T/build_dataset.py --pair $S/things_custom23/things_custom23 --library $L/donorB ... \
        --icons $L/item_icons --out $S/cnn/data/items.npz
    python3 -I $T/train_critic.py --data $S/cnn/data/items.npz --out $S/cnn/weights
    python3 -I $T/train_critic.py --data ... --out ... --holdout-source pair     # train on donors, test on our pair
    python3 -I $T/rank_candidates.py rank --weights $S/cnn/weights/critic.pt --cands $S/sets_v2/raw_full \
        --picks $S/sets_v2/picks.csv --out $S/cnn/previews/rank
    python3 -I $T/rank_candidates.py score --weights $S/cnn/weights/critic.pt --kind sword --out P.png a.png ...
    python3 -I $T/train_gen.py --data ... --pseudo $S/cnn/weights/pseudo.npz --out $S/cnn/weights --minutes 180
    python3 -I $T/train_gan.py --data ... --pseudo $S/cnn/weights/pseudo.npz --out $S/cnn/weights --minutes 45
    python3 -I $T/sample_gen.py samples --weights $S/cnn/weights --data ... --out $S/cnn/previews/gen \
        --pixellab $S/sets_v2/items/A --forge <item_forge build dir>
    python3 -I $T/sample_gen.py refine --weights $S/cnn/weights --kind sword --out $S/cnn/previews/refine.png a.png ...
    python3 -I $T/rank_candidates.py curves --metrics $S/cnn/weights/critic_metrics.json \
        --metrics $S/cnn/weights/gen_metrics.json --out $S/cnn/previews/curves.png

All trainers take `--threads`; use 2 on the shared build machine.

## Limits

The critic learns "not degraded, not random" from synthetic negatives. It does not know taste. A high score means
the art has clean ramps, a solid silhouette and the right kind. It does not mean the art is good. On the first
PixelLab round it did not agree with the human picks (no pick in its top 5). Use it as a filter for broken
candidates and for wrong kinds, not as a judge of the best one.

The critic also rewards texture: img2img refining of item_forge output raised its score while the art got
visibly worse (noisy surfaces, lost gems). Never use its score as the target of an optimiser.

The generators had about three hours on a shared CPU (diffusion 4k steps, DCGAN 1.2k steps). Their samples are
blobs with the right rough silhouette and colour, not usable as game art. The refiner is not usable either.
Measured results are in the hand-off report of the run.
