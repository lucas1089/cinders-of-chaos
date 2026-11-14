#!/usr/bin/env python3
"""Kill dissolve (O563): the seven dissolve shaders, their tile pictures and the offline previews.

usage: python3 -I client/tools/gen_kill_dissolve.py             write the shaders and the pictures
       python3 -I client/tools/gen_kill_dissolve.py --check     fail when a shipped file differs from what is generated
       python3 -I client/tools/gen_kill_dissolve.py video OUT_DIR   one MP4 per cosmetic (sample monster, 4x, never shipped)
       python3 -I client/tools/gen_kill_dissolve.py sheet OUT.png   contact sheet of every cosmetic at 6 moments (never shipped)

What is generated (client/MANIFEST.md "game_killdissolve", base patch 0201):
  client/overlay/data/shaders/chaos_outfit_kd_<mode>.frag   one outfit fragment stage per mode (the vertex stage is
        chaos_outfit_vertex.frag); the seven modes share one template below and differ in a few lines (MODES)
  client/overlay/modules/game_killdissolve/images/<mode>_<tint>.png   the tile picture of a kill effect: the sample
        creature of this file at 42% of the dissolve, 64x64 (the Customise window's tiles; ICONS lists the pairs)

How a dissolve is drawn (the shader, per pixel; u_Params = progress, tint + 1, seed, the part's width in sprite pixels;
u_Src = the part's rectangle in the texture, base patch 0201):
  every cell of the creature (CELL sprite pixels) leaves the body at its own progress `die` (top first for sand, from
  the edges for embers, outer first for the void, at random for pixels ...); from then on its pixels travel as grains
  for `life` of the progress on a path `vel` + `grav` and fade. The shader draws a pixel by looking BACK along that
  path (two fixed-point steps): the grain that lands on this pixel came from the cell it would have left. The body
  is the sprite itself while its cell has not left yet. Colours: the pixel's own, mixed with the tint colour.

The emulation below (numpy, float32) is the same maths line by line; the previews and the tile pictures are drawn
with it. The sample creature is drawn here (no sprite of the client pair is read or shipped).
"""
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.dirname(HERE)
ROOT = os.path.dirname(CLIENT)
SHADERS = os.path.join(CLIENT, 'overlay', 'data', 'shaders')
IMAGES = os.path.join(CLIENT, 'overlay', 'modules', 'game_killdissolve', 'images')
COSMETICS = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'cosmetics_config.lua')

# tint index (the cosmetic's `tint` 0..7; the shader gets tint + 1): 0 = the mode's own colour
TINTS = [None, (0.35, 0.85, 0.40), (0.85, 0.15, 0.20), (0.60, 0.30, 0.95), (1.00, 0.82, 0.30),
         (0.55, 0.85, 1.00), (0.88, 0.88, 0.92), (1.00, 0.50, 0.15)]
TINT_NAMES = ['own', 'green', 'crimson', 'violet', 'gold', 'frost', 'bone', 'ember']

# ---------------------------------------------------------------------------------------------------- the modes
# glsl: die(uv, h), vel(uv, h, h2), grav(uv, h, h2) as GLSL expressions (uv in 0..1, y down, h and h2 the cell's two
# hashes, wind = -1 / 1 by the seed); py: the same as numpy lambdas on (x, y, h, h2, wind) arrays.
# cell: sprite pixels per cell; life: share of the progress a grain lives (die + life <= 1); dens(a): chance a landing
# cell shows a grain at age a; mix: how far a grain goes to the tint colour; dflt: the mode's own tint colour; glow:
# (width in progress, colour) of the edge that burns on the body just before a cell leaves; body: (amount, from, to)
# the body drifts to the tint colour over that progress range; ms: how long the dissolve plays.
MODES = {
    'sand': dict(
        name='Sand in the wind', cell=1.0, life=0.30, ms=1000, mix=0.35, dflt=(0.86, 0.74, 0.50), glow=None, body=None,
        die='0.05 + 0.60 * (0.70 * uv.y + 0.30 * h)',
        vel='vec2(wind * (0.60 + 0.45 * h2), -0.03 - 0.10 * h2)',
        grav='vec2(0.0, 0.10)',
        dens='0.90 * (1.0 - a)',
        py=dict(die=lambda x, y, h, h2, w: 0.05 + 0.60 * (0.70 * y + 0.30 * h),
                vel=lambda x, y, h, h2, w: (w * (0.60 + 0.45 * h2), -0.03 - 0.10 * h2),
                grav=lambda x, y, h, h2, w: (0.0 * x, 0.10 + 0.0 * x),
                dens=lambda a: 0.90 * (1.0 - a))),
    'pixels': dict(
        name='Pixels coming apart', cell=2.0, life=0.40, ms=1000, mix=0.0, dflt=(1.0, 1.0, 1.0), glow=None, body=None,
        die='0.05 + 0.55 * h',
        vel='vec2(cos(6.2831853 * h2), sin(6.2831853 * h2) - 0.45) * (0.14 + 0.22 * h)',
        grav='vec2(0.0, 0.06)',
        dens='1.0 - a * a',
        py=dict(die=lambda x, y, h, h2, w: 0.05 + 0.55 * h,
                vel=lambda x, y, h, h2, w: (np.cos(6.2831853 * h2) * (0.14 + 0.22 * h),
                                            (np.sin(6.2831853 * h2) - 0.45) * (0.14 + 0.22 * h)),
                grav=lambda x, y, h, h2, w: (0.0 * x, 0.06 + 0.0 * x),
                dens=lambda a: 1.0 - a * a)),
    'ash': dict(
        name='Ash crumble', cell=1.5, life=0.42, ms=1100, mix=0.65, dflt=(0.56, 0.54, 0.52), glow=None,
        body=(0.9, 0.0, 0.5),
        die='0.05 + 0.52 * (0.35 * uv.y + 0.65 * h)',
        vel='vec2((h2 - 0.5) * 0.10, 0.18 + 0.30 * h2)',
        grav='vec2(0.0, 0.26)',
        dens='0.85 * (1.0 - a)',
        py=dict(die=lambda x, y, h, h2, w: 0.05 + 0.52 * (0.35 * y + 0.65 * h),
                vel=lambda x, y, h, h2, w: ((h2 - 0.5) * 0.10, 0.18 + 0.30 * h2),
                grav=lambda x, y, h, h2, w: (0.0 * x, 0.26 + 0.0 * x),
                dens=lambda a: 0.85 * (1.0 - a))),
    'burn': dict(
        name='Burning from the edges', cell=1.0, life=0.32, ms=1000, mix=0.85, dflt=(1.0, 0.55, 0.15),
        glow=(0.08, (1.0, 0.62, 0.20)), body=(0.55, 0.0, 0.6),
        die='0.05 + 0.58 * (1.0 - clamp(length((uv - vec2(0.5, 0.56)) * vec2(1.0, 0.9)) * 1.9, 0.0, 1.0)) + 0.09 * h',
        vel='vec2((h2 - 0.5) * 0.10, -0.22 - 0.30 * h2)',
        grav='vec2(0.0, -0.05)',
        dens='0.75 * (1.0 - a)',
        py=dict(die=lambda x, y, h, h2, w: 0.05 + 0.58 * (1.0 - np.clip(
                    np.sqrt((x - 0.5) ** 2 + ((y - 0.56) * 0.9) ** 2) * 1.9, 0.0, 1.0)) + 0.09 * h,
                vel=lambda x, y, h, h2, w: ((h2 - 0.5) * 0.10, -0.22 - 0.30 * h2),
                grav=lambda x, y, h, h2, w: (0.0 * x, -0.05 + 0.0 * x),
                dens=lambda a: 0.75 * (1.0 - a))),
    'void': dict(
        name='Void collapse', cell=1.5, life=0.40, ms=1100, mix=0.60, dflt=(0.58, 0.22, 0.92),
        glow=(0.06, (0.75, 0.40, 1.0)), body=(0.5, 0.0, 0.5),
        die='0.04 + 0.52 * clamp(length((uv - vec2(0.5, 0.56)) * vec2(1.0, 0.9)) * 1.8, 0.0, 1.0) + 0.10 * h',
        vel='(vec2(0.5, 0.56) - uv) * 1.05',
        grav='vec2(0.0, 0.0)',
        dens='0.90 * (1.0 - a * 0.7)',
        extra='    float coreP = smoothstep(0.45, 0.80, p) * (1.0 - smoothstep(0.88, 1.0, p));\n'
              '    float coreD = length((here - vec2(0.5, 0.56)) * vec2(1.0, 0.9));\n'
              '    float core = coreP * exp(-coreD * coreD * 90.0);\n'
              '    outc = vec4(mix(outc.rgb, vec3(0.92, 0.80, 1.0), clamp(core, 0.0, 1.0)), max(outc.a, core * 0.9));\n',
        py=dict(die=lambda x, y, h, h2, w: 0.04 + 0.52 * np.clip(
                    np.sqrt((x - 0.5) ** 2 + ((y - 0.56) * 0.9) ** 2) * 1.8, 0.0, 1.0) + 0.10 * h,
                vel=lambda x, y, h, h2, w: ((0.5 - x) * 1.05, (0.56 - y) * 1.05),
                grav=lambda x, y, h, h2, w: (0.0 * x, 0.0 * x),
                dens=lambda a: 0.90 * (1.0 - a * 0.7))),
    'frost': dict(
        name='Frost shatter and melt', cell=4.0, life=0.40, ms=1100, mix=0.75, dflt=(0.62, 0.88, 1.0),
        glow=(0.05, (0.82, 0.96, 1.0)), body=(0.75, 0.0, 0.35),
        die='0.08 + 0.50 * (0.45 * h + 0.55 * uv.y)',
        vel='vec2((h2 - 0.5) * 0.14, 0.12 + 0.16 * h2)',
        grav='vec2(0.0, 0.20)',
        dens='0.95 * (1.0 - a)',
        py=dict(die=lambda x, y, h, h2, w: 0.08 + 0.50 * (0.45 * h + 0.55 * y),
                vel=lambda x, y, h, h2, w: ((h2 - 0.5) * 0.14, 0.12 + 0.16 * h2),
                grav=lambda x, y, h, h2, w: (0.0 * x, 0.20 + 0.0 * x),
                dens=lambda a: 0.95 * (1.0 - a))),
    'gold': dict(
        name='Gold dust rising', cell=1.5, life=0.45, ms=1100, mix=0.80, dflt=(1.0, 0.82, 0.30),
        glow=(0.05, (1.0, 0.90, 0.50)), body=(0.8, 0.0, 0.4),
        die='0.05 + 0.50 * (0.40 * (1.0 - uv.y) + 0.60 * h)',
        vel='vec2((h2 - 0.5) * 0.14, -0.40 - 0.35 * h2)',
        grav='vec2(0.0, -0.12)',
        dens='0.85 * (1.0 - a * a)',
        py=dict(die=lambda x, y, h, h2, w: 0.05 + 0.50 * (0.40 * (1.0 - y) + 0.60 * h),
                vel=lambda x, y, h, h2, w: ((h2 - 0.5) * 0.14, -0.40 - 0.35 * h2),
                grav=lambda x, y, h, h2, w: (0.0 * x, -0.12 + 0.0 * x),
                dens=lambda a: 0.85 * (1.0 - a * a))),
}
ORDER = ['sand', 'pixels', 'ash', 'burn', 'void', 'frost', 'gold']

# the tile pictures: (mode, tint) pairs of the cosmetics (server cosmetics_config.lua `dissolve` / `tint`; --check reads them)
ICONS = [('pixels', 1), ('burn', 2), ('ash', 2), ('sand', 0), ('pixels', 0), ('ash', 0), ('frost', 0), ('burn', 7),
         ('void', 0), ('gold', 4)]

# ---------------------------------------------------------------------------------------------------- the GLSL
TEMPLATE = '''// Cinders of Chaos outfit shader (game_killdissolve, written for this server). Kill dissolve "%(name)s": the dying
// monster's own sprite leaves the body cell by cell and travels on as grains (see client/tools/gen_kill_dissolve.py).
// GENERATED by client/tools/gen_kill_dissolve.py: do not edit by hand. Vertex stage chaos_outfit_vertex.frag.
// u_Params: x = progress 0..1, y = tint index + 1 (1 = the mode's own colour), z = seed 0..1, w = the part's width in
// sprite pixels. u_Src = the part's rectangle in the texture (base patch 0201); without it (u_Src.z < 1) the sprite is
// drawn as it is.
uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Params;
uniform vec4 u_Src;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_Px;
varying vec2 v_Texel;

float hashA(vec2 c)
{
    return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

float hashB(vec2 c)
{
    return fract(sin(dot(c, vec2(39.3468, 11.135))) * 24634.6345);
}

// the sprite at the local position uv (0..1 over the part), seen from the fragment at `here`; nothing outside the part
vec4 spriteAt(vec2 uv, vec2 here)
{
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0)
        return vec4(0.0);
    vec2 d = (uv - here) * u_Src.zw * v_Texel;
    vec4 c = texture2D(u_Tex0, v_TexCoord + d);
    vec4 m = texture2D(u_Tex0, v_TexCoord2 + d);
    if (m.r > 0.9) {
        c *= m.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if (m.g > 0.9) {
        c *= u_Color[2];
    } else if (m.b > 0.9) {
        c *= u_Color[3];
    }
    return c;
}

vec3 tintColour(float t, vec3 own)
{
    if (t < 1.5)
        return own;
    if (t < 2.5)
        return vec3(0.35, 0.85, 0.40);
    if (t < 3.5)
        return vec3(0.85, 0.15, 0.20);
    if (t < 4.5)
        return vec3(0.60, 0.30, 0.95);
    if (t < 5.5)
        return vec3(1.00, 0.82, 0.30);
    if (t < 6.5)
        return vec3(0.55, 0.85, 1.00);
    if (t < 7.5)
        return vec3(0.88, 0.88, 0.92);
    return vec3(1.00, 0.50, 0.15);
}

float dieAt(vec2 uv, float h)
{
    return %(die)s;
}

vec2 velOf(vec2 uv, float h, float h2, float wind)
{
    return %(vel)s;
}

vec2 gravOf(vec2 uv, float h, float h2)
{
    return %(grav)s;
}

float densAt(float a)
{
    return %(dens)s;
}

void main()
{
    if (u_Src.z < 1.0) {
        vec4 plain = texture2D(u_Tex0, v_TexCoord);
        if (plain.a < 0.01)
            discard;
        gl_FragColor = plain;
        return;
    }
    vec2 here = (v_Px - u_Src.xy) / u_Src.zw;
    float p = clamp(u_Params.x, 0.0, 1.0);
    float seed = u_Params.z;
    float wind = seed > 0.5 ? -1.0 : 1.0;
    vec2 lp = vec2(max(u_Params.w, 8.0), max(u_Params.w, 8.0) * u_Src.w / u_Src.z);
    vec2 cellN = max(floor(lp / %(cell)s), vec2(1.0));
    vec3 own = vec3(%(dflt)s);
    vec3 tc = tintColour(u_Params.y, own);
    const float LIFE = %(life)s;
    vec4 outc = vec4(0.0);

    // the grains: look back along the path to the cell this pixel's grain left (two fixed-point steps)
    vec2 s = here;
    for (int i = 0; i < 2; i++) {
        vec2 g = floor(s * cellN);
        float hs = hashA(g + vec2(seed * 17.0, 3.0));
        float hs2 = hashB(g + vec2(seed * 5.0, 9.0));
        float a = clamp((p - dieAt(s, hs)) / LIFE, 0.0, 1.0);
        s = here - (velOf(s, hs, hs2, wind) * a + gravOf(s, hs, hs2) * a * a);
    }
    vec2 g = floor(s * cellN);
    float hs = hashA(g + vec2(seed * 17.0, 3.0));
    float hs2 = hashB(g + vec2(seed * 5.0, 9.0));
    float a = clamp((p - dieAt(s, hs)) / LIFE, 0.0, 1.0);
    vec4 cs = spriteAt(s, here);
    float pick = hashA(floor(here * cellN * 1.0) + vec2(seed * 29.0, 7.0));
    if (a > 0.0 && a < 1.0 && cs.a > 0.5 && pick < densAt(a)) {
        vec3 col = mix(cs.rgb, tc * (0.55 + 0.9 * dot(cs.rgb, vec3(0.30, 0.58, 0.12))), %(mix)s);
        outc = vec4(col, 1.0 - a);
    }

    // the body: the sprite itself while its cell has not left yet
    vec4 b = spriteAt(here, here);
    float hb = hashA(floor(here * cellN) + vec2(seed * 17.0, 3.0));
    float dieB = dieAt(here, hb);
    if (p < dieB && b.a > 0.02) {
        vec3 col = b.rgb;
%(bodyline)s%(glowline)s        outc = vec4(col, b.a);
    }
%(extra)s    if (outc.a < 0.01)
        discard;
    gl_FragColor = outc;
}
'''


def f(v):
    return repr(float(v))


def vec3s(c):
    return '%s, %s, %s' % (f(c[0]), f(c[1]), f(c[2]))


def render_glsl(mode):
    m = MODES[mode]
    body = ''
    if m['body']:
        k, a0, a1 = m['body']
        body = ('        float lum = dot(col, vec3(0.30, 0.58, 0.12));\n'
                '        col = mix(col, tc * (0.45 + 0.8 * lum), %s * smoothstep(%s, %s, p));\n' % (f(k), f(a0), f(a1)))
    glow = ''
    if m['glow']:
        w, gc = m['glow']
        glow = ('        col = mix(col, vec3(%s), smoothstep(%s, 0.0, dieB - p));\n' % (vec3s(gc), f(w)))
    return TEMPLATE % dict(name=m['name'], die=m['die'], vel=m['vel'], grav=m['grav'], dens=m['dens'],
                           cell=f(m['cell']), life=f(m['life']), mix=f(m['mix']), dflt=vec3s(m['dflt']),
                           bodyline=body, glowline=glow, extra=m.get('extra', ''))


# ---------------------------------------------------------------------------------------------------- numpy emulation
def hash_a(x, y):
    v = np.sin((x * 12.9898 + y * 78.233).astype(np.float64)) * 43758.5453
    return (v - np.floor(v)).astype(np.float32)


def hash_b(x, y):
    v = np.sin((x * 39.3468 + y * 11.135).astype(np.float64)) * 24634.6345
    return (v - np.floor(v)).astype(np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def sample_sprite(size=32):
    """A made-up creature (a hulking club-carrier) on a transparent size x size tile: RGBA float32, y down."""
    S = 4
    n = size * S
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n  # 0..1
    img = np.zeros((n, n, 4), np.float32)

    def ell(cx, cy, rx, ry):
        return ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0

    def paint(mask, base, shade):
        # light from the top left: darker to the bottom right
        t = np.clip(((xx - 0.2) * 0.6 + (yy - 0.1) * 0.9) / 1.2, 0, 1)
        col = np.array(base, np.float32)[None, None, :] * (1 - t[..., None] * shade)
        img[mask, :3] = col[mask]
        img[mask, 3] = 1.0

    # club, arms, legs, body, head
    club = ((np.abs(xx - 0.82 - (yy - 0.45) * 0.18) < 0.045) & (yy > 0.18) & (yy < 0.72)) | ell(0.84, 0.22, 0.09, 0.10)
    paint(club, (0.52, 0.36, 0.20), 0.45)
    paint(ell(0.33, 0.86, 0.09, 0.10) | ell(0.57, 0.86, 0.09, 0.10), (0.30, 0.46, 0.22), 0.5)
    paint(ell(0.46, 0.60, 0.25, 0.27), (0.38, 0.56, 0.27), 0.55)
    paint(ell(0.20, 0.55, 0.075, 0.17) | ell(0.72, 0.52, 0.075, 0.16), (0.40, 0.58, 0.28), 0.5)
    paint(ell(0.46, 0.60, 0.15, 0.17), (0.62, 0.50, 0.30), 0.35)  # belly cloth
    paint(ell(0.46, 0.27, 0.15, 0.15), (0.42, 0.62, 0.30), 0.5)
    eyes = ell(0.40, 0.25, 0.028, 0.03) | ell(0.52, 0.25, 0.028, 0.03)
    img[eyes, :3] = (1.0, 0.85, 0.2)
    img[ell(0.46, 0.33, 0.06, 0.02), :3] = (0.2, 0.1, 0.08)
    # a 1 sprite pixel dark outline, then down to size (box filter on alpha, colour weighted by alpha)
    a = img[..., 3]
    ring = (a < 0.5) & (np.maximum.reduce([np.roll(a, s, ax) for s in (S, -S) for ax in (0, 1)]) > 0.5)
    img[ring, :3] = (0.10, 0.12, 0.08)
    img[ring, 3] = 1.0
    out = np.zeros((size, size, 4), np.float32)
    blk = img.reshape(size, S, size, S, 4)
    al = blk[..., 3].mean(axis=(1, 3))
    col = (blk[..., :3] * blk[..., 3:4]).sum(axis=(1, 3)) / np.maximum(blk[..., 3].sum(axis=(1, 3)), 1e-6)[..., None]
    out[..., :3] = col
    out[..., 3] = (al > 0.5).astype(np.float32)  # hard edge like a sprite
    # a little noise so the grains read
    rng = np.random.RandomState(5)
    out[..., :3] = np.clip(out[..., :3] * (0.94 + 0.12 * rng.rand(size, size, 1)), 0, 1)
    return out


def render(sprite, mode, tint, p, seed=0.3, bg=None, timef=0.0):
    """One frame of the dissolve of `sprite` (h, w, 4) at progress p; tint 0..7. Returns RGBA float32."""
    m = MODES[mode]
    pyf = m['py']
    h_, w_ = sprite.shape[:2]
    ys, xs = np.mgrid[0:h_, 0:w_].astype(np.float32)
    hx = (xs + 0.5) / w_
    hy = (ys + 0.5) / h_
    wind = np.float32(-1.0 if seed > 0.5 else 1.0)
    cell = m['cell']
    cn = np.maximum(np.floor(np.array([w_, h_], np.float32) / cell), 1.0)
    own = np.array(m['dflt'], np.float32)
    tc = np.array(TINTS[tint] if TINTS[tint] else own, np.float32)
    life = m['life']

    def hashes(sx, sy):
        gx = np.floor(sx * cn[0])
        gy = np.floor(sy * cn[1])
        return hash_a(gx + seed * 17.0, gy + 3.0), hash_b(gx + seed * 5.0, gy + 9.0)

    def fetch(sx, sy):
        ix = np.floor(sx * w_).astype(np.int64)
        iy = np.floor(sy * h_).astype(np.int64)
        ok = (sx >= 0) & (sy >= 0) & (sx < 1) & (sy < 1)
        ixc = np.clip(ix, 0, w_ - 1)
        iyc = np.clip(iy, 0, h_ - 1)
        c = sprite[iyc, ixc].copy()
        c[~ok] = 0.0
        return c

    sx, sy = hx.copy(), hy.copy()
    for _ in range(2):
        hs, hs2 = hashes(sx, sy)
        a = np.clip((p - pyf['die'](sx, sy, hs, hs2, wind)) / life, 0.0, 1.0)
        vx, vy = pyf['vel'](sx, sy, hs, hs2, wind)
        gx_, gy_ = pyf['grav'](sx, sy, hs, hs2, wind)
        sx, sy = hx - (vx * a + gx_ * a * a), hy - (vy * a + gy_ * a * a)
    hs, hs2 = hashes(sx, sy)
    a = np.clip((p - pyf['die'](sx, sy, hs, hs2, wind)) / life, 0.0, 1.0)
    cs = fetch(sx, sy)
    pick = hash_a(np.floor(hx * cn[0]) + seed * 29.0, np.floor(hy * cn[1]) + 7.0)
    out = np.zeros((h_, w_, 4), np.float32)
    lum = (cs[..., :3] * np.array([0.30, 0.58, 0.12], np.float32)).sum(-1)
    gmask = (a > 0) & (a < 1) & (cs[..., 3] > 0.5) & (pick < pyf['dens'](a))
    gcol = cs[..., :3] * (1 - m['mix']) + (tc[None, None, :] * (0.55 + 0.9 * lum)[..., None]) * m['mix']
    out[gmask, :3] = gcol[gmask]
    out[gmask, 3] = (1.0 - a)[gmask]

    b = sprite
    hb, _ = hashes(hx, hy)
    dieb = pyf['die'](hx, hy, hb, hb * 0.0, wind)
    bmask = (p < dieb) & (b[..., 3] > 0.02)
    col = b[..., :3].copy()
    if m['body']:
        k, a0, a1 = m['body']
        lb = (col * np.array([0.30, 0.58, 0.12], np.float32)).sum(-1)
        col = col + (tc[None, None, :] * (0.45 + 0.8 * lb)[..., None] - col) * (k * smoothstep(a0, a1, p))
    if m['glow']:
        gw, gc = m['glow']
        gk = smoothstep(gw, 0.0, dieb - p)[..., None]
        col = col + (np.array(gc, np.float32)[None, None, :] - col) * gk
    out[bmask, :3] = col[bmask]
    out[bmask, 3] = b[..., 3][bmask]
    if mode == 'void':
        core_p = smoothstep(0.45, 0.80, p) * (1.0 - smoothstep(0.88, 1.0, p))
        cd = np.sqrt((hx - 0.5) ** 2 + ((hy - 0.56) * 0.9) ** 2)
        core = core_p * np.exp(-cd * cd * 90.0)
        k = np.clip(core, 0, 1)[..., None]
        out[..., :3] = out[..., :3] + (np.array([0.92, 0.80, 1.0], np.float32)[None, None, :] - out[..., :3]) * k
        out[..., 3] = np.maximum(out[..., 3], core * 0.9)
    out[out[..., 3] < 0.01] = 0.0
    return out


def composite(frame, bg=(0.10, 0.09, 0.11)):
    a = frame[..., 3:4]
    return frame[..., :3] * a + np.array(bg, np.float32)[None, None, :] * (1 - a)


def to_png(img, scale, bg=(0.10, 0.09, 0.11)):
    rgb = composite(img, bg)
    arr = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(arr, 'RGB')
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


# ---------------------------------------------------------------------------------------------------- files
def icon_image(mode, tint):
    """The tile picture: the creature at 42% of the dissolve on the window's dark, 64x64."""
    sp = sample_sprite(32)
    fr = render(sp, mode, tint, 0.42)
    # the creature itself, faintly, so the picture tells what dissolves
    rgb = composite(fr, (0.11, 0.10, 0.12))
    arr = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(arr, 'RGB').resize((64, 64), Image.NEAREST).convert('RGBA')
    return im


def generated():
    """{path: bytes or ('png', RGBA image)} of everything shipped"""
    files = {}
    for mode in ORDER:
        files[os.path.join(SHADERS, 'chaos_outfit_kd_%s.frag' % mode)] = render_glsl(mode).encode('utf-8')
    for mode, tint in ICONS:
        files[os.path.join(IMAGES, '%s_%d.png' % (mode, tint))] = icon_image(mode, tint)
    return files


def cosmetic_pairs():
    """(key, mode, tint) of the kill effects of the server config (a line of the cosmetics table with `dissolve =`)"""
    out = []
    src = open(COSMETICS, encoding='utf-8').read()
    for m in re.finditer(r'key = "(kill_[a-z_]+)"[^\n]*(?:\n\t\t\t[^\n{]*)*?dissolve = "(\w+)"(?:, tint = (\d))?', src):
        out.append((m.group(1), m.group(2), int(m.group(3) or 0)))
    return out or [('%s_%d' % (m, t), m, t) for m, t in ICONS]


def write(files):
    # a picture or shader of a pair that is not generated any more goes
    for d, pat in ((SHADERS, r'chaos_outfit_kd_\w+\.frag$'), (IMAGES, r'\w+_\d\.png$')):
        if os.path.isdir(d):
            for fn in sorted(os.listdir(d)):
                if re.match(pat, fn) and os.path.join(d, fn) not in files:
                    os.remove(os.path.join(d, fn))
    for path, data in files.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if isinstance(data, bytes):
            with open(path, 'wb') as fh:
                fh.write(data)
        else:
            data.save(path, optimize=True)


def check():
    bad = []
    files = generated()
    for path, data in files.items():
        rel = os.path.relpath(path, ROOT)
        if not os.path.exists(path):
            bad.append('%s is missing' % rel)
        elif isinstance(data, bytes):
            if open(path, 'rb').read() != data:
                bad.append('%s differs from what the generator writes' % rel)
        else:
            on = np.asarray(Image.open(path).convert('RGBA')).astype(int)
            new = np.asarray(data).astype(int)
            if on.shape != new.shape or np.abs(on - new).max() > 2:
                bad.append('%s differs from what the generator draws' % rel)
    # no stray generated file
    for d, pat in ((SHADERS, r'chaos_outfit_kd_\w+\.frag$'), (IMAGES, r'\w+_\d\.png$')):
        if os.path.isdir(d):
            for fn in sorted(os.listdir(d)):
                if re.match(pat, fn) and os.path.join(d, fn) not in files:
                    bad.append('%s is not generated (stray file)' % os.path.relpath(os.path.join(d, fn), ROOT))
    # the server's kill effects and ICONS agree
    pairs = {(m, t) for _, m, t in cosmetic_pairs()}
    for m, t in pairs:
        if m not in MODES:
            bad.append('server cosmetics_config.lua: unknown dissolve mode %s' % m)
        elif (m, t) not in ICONS:
            bad.append('server cosmetics_config.lua: dissolve %s tint %d has no tile picture (ICONS)' % (m, t))
    for pair in ICONS:
        if pair not in pairs:
            bad.append('ICONS %s is used by no kill effect of cosmetics_config.lua' % (pair,))
    return bad


def ffmpeg_pipe(path, w, h, fps):
    return subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h),
                             '-r', str(fps), '-i', '-', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18',
                             '-movflags', '+faststart', path], stdin=subprocess.PIPE)


def video(outdir):
    os.makedirs(outdir, exist_ok=True)
    sp = sample_sprite(32)
    scale, fps = 6, 30
    for key, mode, tint in cosmetic_pairs():
        ms = MODES[mode]['ms']
        n = int(ms * fps / 1000)
        w = h = 32 * scale
        pipe = ffmpeg_pipe(os.path.join(outdir, '%s.mp4' % key), w, h, fps)
        # standing 0.5 s, the dissolve, empty 0.4 s, the monster stands again (the window's loop)
        seq = [0.0] * (fps // 2) + [i / (n - 1) for i in range(n)] + [1.0] * int(fps * 0.4)
        for p in seq:
            if p >= 1.0:
                fr = np.zeros_like(sp)
            else:
                fr = render(sp, mode, tint, p)
            pipe.stdin.write(np.asarray(to_png(fr, scale).convert('RGB')).tobytes())
        pipe.stdin.close()
        pipe.wait()
        print('wrote', os.path.join(outdir, key + '.mp4'))


def sheet(outpath):
    pairs = cosmetic_pairs()
    sp = sample_sprite(32)
    moments = [0.0, 0.2, 0.35, 0.5, 0.65, 0.8]
    scale = 3
    cell = 32 * scale
    W = 140 + len(moments) * (cell + 4)
    H = len(pairs) * (cell + 4)
    im = Image.new('RGB', (W, H), (26, 24, 28))
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    for r, (key, mode, tint) in enumerate(pairs):
        d.text((4, r * (cell + 4) + 4), key, fill=(220, 200, 160))
        d.text((4, r * (cell + 4) + 18), '%s / %s' % (mode, TINT_NAMES[tint]), fill=(150, 150, 160))
        for c, p in enumerate(moments):
            fr = render(sp, mode, tint, p)
            im.paste(to_png(fr, scale), (140 + c * (cell + 4), r * (cell + 4)))
    im.save(outpath)
    print('wrote', outpath)


def main(argv):
    if argv[:1] == ['--check']:
        bad = check()
        for b in bad:
            print('FAIL', b)
        print('gen_kill_dissolve --check:', 'FAIL' if bad else 'ok')
        return 1 if bad else 0
    if argv[:1] == ['video'] and len(argv) == 2:
        video(argv[1])
        return 0
    if argv[:1] == ['sheet'] and len(argv) == 2:
        sheet(argv[1])
        return 0
    if argv:
        print(__doc__)
        return 2
    write(generated())
    print('wrote %d shaders and %d tile pictures' % (len(ORDER), len(ICONS)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
