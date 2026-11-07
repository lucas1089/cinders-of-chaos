#!/usr/bin/env python3
"""python3 -I unity/tools/hd2d_preview_test.py : hd2d_preview.py on synthetic sprites (no real pair): the classification
rule, the light colour index and falloff, the camera framing of the room, the draw order, the shadow direction and a
small full render."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import hd2d_preview as H  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


I = H.ThingInfo
# classification
check(H.classify(I(1, 1, {'ground': 100})) == 'floor', 'ground is floor')
check(H.classify(I(1, 1, {'clip': True, 'bottom': True})) == 'floor', 'ground border is floor')
check(H.classify(I(1, 1, {'bottom': True})) == 'floor', 'flat on-bottom item is floor')
check(H.classify(I(3, 4, {'notmoveable': True})) == 'floor', 'carpet without block flags is floor')
check(H.classify(I(2, 2, {'bottom': True, 'notwalkable': True})) == 'upright', 'wall stands')
check(H.classify(I(2, 2, {'notwalkable': True, 'light': (6, 206)})) == 'upright', 'torch stands')
check(H.classify(I(1, 1, {'pickupable': True})) == 'upright', 'pickup item stands')
check(H.classify(I(2, 2, {}, 'outfit')) == 'upright', 'outfit stands')

# light colour cube and attribute
check(H.colour_from_index(0) == (0, 0, 0), 'index 0 black')
check(H.colour_from_index(215) == (255, 255, 255), 'index 215 white')
check(H.colour_from_index(206) == (255, 204, 102), 'index 206 warm orange')
check(H.colour_from_index(36 * 1 + 6 * 2 + 3) == (51, 102, 153), 'index r g b order')
lo = H.light_of(I(2, 2, {'light': (6, 206)}))
check(lo is not None and lo[0] == 6.0 and lo[1][0] > lo[1][1] > lo[1][2], 'light radius and warm colour')
check(H.light_of(I(2, 2, {})) is None and H.light_of(I(1, 1, {'light': (0, 5)})) is None, 'no light, level 0')
f = H.falloff(np.array([0.0, 2.55, 5.1, 9.0]), 6.0)
check(abs(f[0] - 1) < 1e-9 and 0 < f[1] < 1 and f[2] == 0 and f[3] == 0 and f[0] > f[1], 'falloff monotone, zero at the edge')

# footprints: bottom-right cell on the tile
check(H.floor_rect(I(3, 3), 5, 7) == (3, 5, 6, 8), 'floor rect covers up and left')
x0, x1, h, z = H.billboard_rect(I(2, 2), 4, 4)
check((x0, x1, h) == (3, 5, 2.0) and z == 4 + H.BASE_Z, 'billboard rect 2 x 2 keeps its tile as bottom-right')
check(H.shear_of(I(2, 2, {'bottom': True, 'notwalkable': True})) == 1.0, 'a 2 x 2 wall leans east as it rises')
check(H.shear_of(I(1, 2, {'notwalkable': True})) == 0.0 and H.shear_of(I(2, 2, {}, 'outfit')) == 0.0
      and H.shear_of(I(3, 3, {'notmoveable': True})) == 0.0, 'no shear: one cell wide, outfits, flat things')

# camera: the room stays in frame for several sizes
for w, h_ in ((480, 300), (960, 600), (1280, 720)):
    cam = H.fit_camera(w, h_)
    q = cam.project(H.room_points())
    check(q[:, 0].min() >= 0 and q[:, 0].max() <= w and q[:, 1].min() >= 0 and q[:, 1].max() <= h_, 'room in frame %dx%d' % (w, h_))
    check((q[:, 2] > 0).all(), 'room in front of the camera')
    check(q[:, 0].max() - q[:, 0].min() > 0.8 * w or q[:, 1].max() - q[:, 1].min() > 0.8 * h_, 'room fills the frame')
# nearer floor rows are wider and lower on the screen (perspective, camera from the south)
q = cam.project(np.array([[0, 0, 0], [15, 0, 0], [0, 0, 11], [15, 0, 11]], float))
check(q[2, 1] > q[0, 1] and (q[3, 0] - q[2, 0]) > (q[1, 0] - q[0, 0]), 'south edge lower and wider')
# a ray through a pixel hits the floor where the projection says
cam = H.fit_camera(640, 400)
p = np.array([[7.5, 0.0, 5.5]])
px, py, _ = cam.project(p)[0]
r = cam.rays(np.array([px - 0.5]), np.array([py - 0.5]))[0]
t = -cam.pos[1] / r[1]
hit = cam.pos + t * r
check(abs(hit[0] - 7.5) < 1e-6 and abs(hit[2] - 5.5) < 1e-6, 'rays invert the projection')


class Syn(H.Assets):
    """Synthetic sprites: a light floor tile, a 2 x 2 grey wall, a torch with the light attribute, one outfit."""

    def __init__(self):
        self.i = {1: I(1, 1, {'ground': 100}), 2: I(2, 2, {'notwalkable': True}),
                  3: I(2, 2, {'notwalkable': True, 'light': (6, 206)}), 5: I(1, 1, {}, 'outfit')}

    def info(self, kind, cid):
        return self.i[cid if kind == 'item' else 5]

    def image(self, kind, cid):
        t = self.info(kind, cid)
        a = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
        if kind == 'outfit':
            a[8:32, 10:22] = (60, 200, 60, 255)
        elif cid == 1:
            a[:] = (200, 190, 170, 255)
        elif cid == 2:
            a[8:, :] = (150, 150, 150, 255)
        else:
            a[20:60, 40:50] = (255, 220, 120, 255)
        return a


A = Syn()
scene = [H.Placement('item', 1, x, y) for y in range(H.ROOM_H) for x in range(H.ROOM_W)]
scene += [H.Placement('item', 2, 9, 3), H.Placement('item', 2, 3, 8), H.Placement('item', 3, 5, 3), H.Placement('outfit', 1, 8, 6)]
floors, ups = H.split_scene(scene, A)
check(len(floors) == H.ROOM_W * H.ROOM_H and len(ups) == 4, 'split floors and uprights')
zs = [(p.ty, p.tx) for p, _, _ in ups]
check(zs == sorted(zs), 'uprights far to near, then west to east: %s' % zs)
check(len(H.collect_lights(ups, A)) == 1, 'one light from the torch')

# classic: 32 px per tile, flat, the room plus its wall row and column and a one tile pad
c = H.render_classic(scene, A)
check(c.shape == ((H.ROOM_H + 3) * 32, (H.ROOM_W + 4) * 32, 4), "classic size %s" % (c.shape,))

# shadows fall away from the light: a wall west of the light shades the floor on its far (west) side
lights = [H.Light((12.0, 1.5, 5.0), 6.0, (1, 1, 1), -1)]
wall = [(H.Placement('item', 2, 6, 5), I(2, 2, {'notwalkable': True}), 0)]
sm = H.shadow_maps(wall, [A.image('item', 2)], lights, (-4.0, -4.0), (H.ROOM_W + 8, H.ROOM_H + 8))[0]
res = H.SHADOW_RES
z_i = int((5.8 + 4) * res)
sh_w = sm[z_i, int((4.5 + 4) * res)]       # west of the wall (away from the light; the 2 x 2 wall leans east)
sh_e = sm[z_i, int((9.0 + 4) * res)]       # east of it, towards the light
check(sm.max() > 0.5 and sh_w > 0.4 and sh_e < 0.05, 'shadow away from the light (%.2f west, %.2f east)' % (sh_w, sh_e))

# full render: right size, the torch pool is brighter than the far corner
img, parts = H.hd2d_render(scene, A, 240, 150, return_parts=True)
check(img.shape == (150, 240, 3) and img.dtype == np.uint8, 'hd2d shape')
cam = parts['camera']


def px_of(x, z):
    q = cam.project(np.array([[x, 0.0, z]]))[0]
    return int(q[1]), int(q[0])


near = img[px_of(6.5, 5.5)].astype(int).sum()
far = img[px_of(13.5, 9.5)].astype(int).sum()
check(near > far, 'floor is brighter near the torch (%d vs %d)' % (near, far))
check(parts['covered'].mean() > 0.3, 'room covers the picture')

# depth of field: middle rows unchanged, edge rows blurred
rng = np.random.RandomState(1)
noise = rng.rand(100, 60, 3).astype(np.float32)
out = H.depth_of_field(noise, focus=0.5, band=0.25, max_radius=4.0)
check(np.allclose(out[40:60], noise[40:60], atol=1e-5), 'dof keeps the middle band sharp')
check(out[:5].std() < 0.6 * noise[:5].std() and out[-5:].std() < 0.6 * noise[-5:].std(), 'dof blurs top and bottom')
w = H.dof_weights(100, 0.5, 0.25, 5)
check(np.allclose(w.sum(1), 1.0, atol=1e-5), 'dof weights sum to one')

print('hd2d_preview_test: %s' % ('FAILED %d' % failed if failed else 'ok'))
sys.exit(1 if failed else 0)
