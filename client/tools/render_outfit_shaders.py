#!/usr/bin/env python3
"""Headless render of the Chaos outfit shaders (client/overlay/data/shaders/chaos_outfit_*.frag) on a sample sprite.

usage:
  python3 -I client/tools/render_outfit_shaders.py sheet OUT.png [--shaders NAMES] [--times T,T,..] [--zoom N] [--pair DAT SPR] [--looks IDS]
  python3 -I client/tools/render_outfit_shaders.py video OUT.mp4 [--shaders NAMES] [--seconds S] [--fps N] [--zoom N] [--pair DAT SPR] [--looks IDS]
  python3 -I client/tools/render_outfit_shaders.py check [--shaders NAMES]       # every shader compiles and draws something

The engine's draw is rebuilt on a software GL context (EGL surfaceless, Mesa llvmpipe; no display, no GPU) through
ctypes: the outfit sprite and its colour template layer sit in one texture (the template at u_Offset from the
sprite, the way the client's atlas holds them), the vertex stage is chaos_outfit_vertex.frag, u_Time is seconds,
u_Color holds the four outfit colours, blending is the client's (SRC_ALPHA, ONE_MINUS_SRC_ALPHA). The sprite is drawn
at 1x into a small frame and zoomed by the sheet with nearest-neighbour, so what you see is what 1x shows.
Without --pair the sample is a small procedural figure (no sprite art is needed or committed); with --pair DAT SPR the
sample looks are outfits of that pair (client/tools/sprites/datspr.py; the pair is private, never commit pictures
made from it). `video` needs ffmpeg (libx264, yuv420p, even sizes). Needs numpy and Pillow.
"""
import argparse
import ctypes
import math
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SHADERS = os.path.join(os.path.dirname(HERE), 'overlay', 'data', 'shaders')
VERTEX = 'chaos_outfit_vertex'
GLES_HEAD = ''   # the client prepends "precision highp float;" only on GLES; desktop GLSL 1.10 here

ORDER = ['ember_glow', 'frost_rime', 'void_flicker', 'holy_radiance', 'blood_pulse', 'spectral_ghost', 'ash_drift',
         'cinder_crown']
CELL = 32                 # sprite cell, px
FRAME = 72                # one drawn frame, px (the sprite in the middle, room for what a shader draws round it)
GROUND = (46, 52, 46)     # a dark floor tile colour

# ------------------------------------------------------------------------------------------------ sample sprites
COLOURS = [(0.95, 0.80, 0.55, 1.0), (0.78, 0.18, 0.16, 1.0), (0.30, 0.34, 0.70, 1.0), (0.42, 0.28, 0.16, 1.0)]


def synthetic_look(variant=0):
    """-> (base RGBA uint8 32x32, template RGBA uint8 32x32): a hooded figure with head / body / legs / feet masks"""
    base = np.zeros((CELL, CELL, 4), np.uint8)
    mask = np.zeros((CELL, CELL, 4), np.uint8)

    def fill(x0, y0, x1, y1, rgb, m, shade=0):
        for y in range(y0, y1):
            for x in range(x0, x1):
                k = 1.0 - shade * (0.25 if (x + y) % 5 == 0 else 0.0)
                base[y, x] = (int(rgb[0] * k), int(rgb[1] * k), int(rgb[2] * k), 255)
                mask[y, x] = (m[0], m[1], m[2], 255)

    fill(12, 4, 20, 12, (210, 210, 210), (255, 255, 0))           # head (r+g)
    fill(10, 12, 22, 22, (210, 210, 210), (255, 0, 0), 1)          # body (r)
    fill(8, 13, 10, 21, (200, 200, 200), (255, 0, 0))              # arms
    fill(22, 13, 24, 21, (200, 200, 200), (255, 0, 0))
    fill(12, 22, 20, 28, (205, 205, 205), (0, 255, 0))             # legs (g)
    fill(12, 28, 20, 31, (205, 205, 205), (0, 0, 255))             # feet (b)
    if variant:
        fill(14, 1, 18, 4, (240, 240, 240), (255, 255, 0))         # a crest
    return base, mask


def pair_looks(dat_path, spr_path, ids):
    sys.path.insert(0, os.path.join(HERE, 'sprites'))
    import datspr as D
    dat, spr = D.Dat(dat_path), D.Spr(spr_path)
    out = []
    for lid in ids:
        t = dat.outfit(lid)
        if t is None:
            raise SystemExit('look %d is not in the pair' % lid)
        layers = []
        for layer in range(min(2, t.layers)):
            im = np.zeros((t.h * CELL, t.w * CELL, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    sid = t.sprites[D.sprite_index(t, 2 if t.px >= 4 else 0, 0, 0, layer, 0, ww, hh)]
                    a = spr.sprite(sid)
                    if a is not None:
                        y, x = (t.h - 1 - hh) * CELL, (t.w - 1 - ww) * CELL
                        im[y:y + CELL, x:x + CELL] = a
            layers.append(im)
        if len(layers) < 2:
            layers.append(np.zeros_like(layers[0]))
        out.append((layers[0], layers[1]))
    return out


# ------------------------------------------------------------------------------------------------ software GL
class GL:
    """a tiny GL 2.x on an EGL surfaceless context; every function through eglGetProcAddress"""

    def __init__(self):
        os.environ.setdefault('EGL_PLATFORM', 'surfaceless')
        self.egl = egl = ctypes.CDLL('libEGL.so.1')
        vp, ci = ctypes.c_void_p, ctypes.c_int
        egl.eglGetDisplay.restype = vp
        egl.eglGetDisplay.argtypes = [vp]
        egl.eglInitialize.argtypes = [vp, vp, vp]
        egl.eglBindAPI.argtypes = [ci]
        egl.eglChooseConfig.argtypes = [vp, vp, vp, ci, vp]
        egl.eglCreateContext.restype = vp
        egl.eglCreateContext.argtypes = [vp, vp, vp, vp]
        egl.eglMakeCurrent.argtypes = [vp, vp, vp, vp]
        egl.eglGetProcAddress.restype = vp
        egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]
        self.dpy = egl.eglGetDisplay(None)
        a, b = ci(), ci()
        if not egl.eglInitialize(self.dpy, ctypes.byref(a), ctypes.byref(b)):
            raise SystemExit('no EGL display (this tool needs Mesa llvmpipe)')
        egl.eglBindAPI(0x30A2)  # EGL_OPENGL_API
        attrs = (ci * 5)(0x3033, 0x1, 0x3040, 0x8, 0x3038)  # surface type pbuffer, renderable type opengl, none
        cfg, n = vp(), ci()
        egl.eglChooseConfig(self.dpy, attrs, ctypes.byref(cfg), 1, ctypes.byref(n))
        if n.value < 1:
            raise SystemExit('no EGL config')
        self.ctx = egl.eglCreateContext(self.dpy, cfg, None, None)
        if not egl.eglMakeCurrent(self.dpy, None, None, self.ctx):
            raise SystemExit('eglMakeCurrent failed')
        self._fn = {}

    def f(self, name, restype=None, *argtypes):
        key = name
        if key not in self._fn:
            addr = self.egl.eglGetProcAddress(name.encode())
            if not addr:
                raise SystemExit('GL function %s missing' % name)
            self._fn[key] = ctypes.CFUNCTYPE(restype, *argtypes)(addr)
        return self._fn[key]


GL_TEXTURE_2D, GL_RGBA, GL_UNSIGNED_BYTE, GL_NEAREST, GL_CLAMP_TO_EDGE = 0x0DE1, 0x1908, 0x1401, 0x2600, 0x812F
GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAGMENT_SHADER, GL_VERTEX_SHADER = 0x8D40, 0x8CE0, 0x8B30, 0x8B31
GL_COMPILE_STATUS, GL_LINK_STATUS, GL_FLOAT, GL_ARRAY_BUFFER, GL_STATIC_DRAW = 0x8B81, 0x8B82, 0x1406, 0x8892, 0x88E4
GL_BLEND, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_TRIANGLE_STRIP, GL_COLOR_BUFFER_BIT = 0x0BE2, 0x0302, 0x0303, 0x5, 0x4000
GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER, GL_TEXTURE_WRAP_S, GL_TEXTURE_WRAP_T = 0x2801, 0x2800, 0x2802, 0x2803
GL_INFO_LOG_LENGTH = 0x8B84


class Renderer:
    def __init__(self, width=FRAME, height=FRAME):
        self.gl = gl = GL()
        c = ctypes
        self.W, self.H = width, height
        f = gl.f
        self.glGenTextures = f('glGenTextures', None, c.c_int, c.c_void_p)
        self.glBindTexture = f('glBindTexture', None, c.c_uint, c.c_uint)
        self.glTexImage2D = f('glTexImage2D', None, c.c_uint, c.c_int, c.c_int, c.c_int, c.c_int, c.c_int, c.c_uint,
                              c.c_uint, c.c_void_p)
        self.glTexParameteri = f('glTexParameteri', None, c.c_uint, c.c_uint, c.c_int)
        self.glActiveTexture = f('glActiveTexture', None, c.c_uint)
        self.glGenFramebuffers = f('glGenFramebuffers', None, c.c_int, c.c_void_p)
        self.glBindFramebuffer = f('glBindFramebuffer', None, c.c_uint, c.c_uint)
        self.glFramebufferTexture2D = f('glFramebufferTexture2D', None, c.c_uint, c.c_uint, c.c_uint, c.c_uint, c.c_int)
        self.glViewport = f('glViewport', None, c.c_int, c.c_int, c.c_int, c.c_int)
        self.glClearColor = f('glClearColor', None, c.c_float, c.c_float, c.c_float, c.c_float)
        self.glClear = f('glClear', None, c.c_uint)
        self.glEnable = f('glEnable', None, c.c_uint)
        self.glBlendFunc = f('glBlendFunc', None, c.c_uint, c.c_uint)
        self.glReadPixels = f('glReadPixels', None, c.c_int, c.c_int, c.c_int, c.c_int, c.c_uint, c.c_uint, c.c_void_p)
        self.glCreateShader = f('glCreateShader', c.c_uint, c.c_uint)
        self.glShaderSource = f('glShaderSource', None, c.c_uint, c.c_int, c.c_void_p, c.c_void_p)
        self.glCompileShader = f('glCompileShader', None, c.c_uint)
        self.glGetShaderiv = f('glGetShaderiv', None, c.c_uint, c.c_uint, c.c_void_p)
        self.glGetShaderInfoLog = f('glGetShaderInfoLog', None, c.c_uint, c.c_int, c.c_void_p, c.c_char_p)
        self.glCreateProgram = f('glCreateProgram', c.c_uint)
        self.glAttachShader = f('glAttachShader', None, c.c_uint, c.c_uint)
        self.glBindAttribLocation = f('glBindAttribLocation', None, c.c_uint, c.c_uint, c.c_char_p)
        self.glLinkProgram = f('glLinkProgram', None, c.c_uint)
        self.glGetProgramiv = f('glGetProgramiv', None, c.c_uint, c.c_uint, c.c_void_p)
        self.glGetProgramInfoLog = f('glGetProgramInfoLog', None, c.c_uint, c.c_int, c.c_void_p, c.c_char_p)
        self.glUseProgram = f('glUseProgram', None, c.c_uint)
        self.glGetUniformLocation = f('glGetUniformLocation', c.c_int, c.c_uint, c.c_char_p)
        self.glUniform1i = f('glUniform1i', None, c.c_int, c.c_int)
        self.glUniform1f = f('glUniform1f', None, c.c_int, c.c_float)
        self.glUniform2f = f('glUniform2f', None, c.c_int, c.c_float, c.c_float)
        self.glUniformMatrix3fv = f('glUniformMatrix3fv', None, c.c_int, c.c_int, c.c_ubyte, c.c_void_p)
        self.glUniformMatrix4fv = f('glUniformMatrix4fv', None, c.c_int, c.c_int, c.c_ubyte, c.c_void_p)
        self.glEnableVertexAttribArray = f('glEnableVertexAttribArray', None, c.c_uint)
        self.glVertexAttribPointer = f('glVertexAttribPointer', None, c.c_uint, c.c_int, c.c_uint, c.c_ubyte, c.c_int,
                                       c.c_void_p)
        self.glDrawArrays = f('glDrawArrays', None, c.c_uint, c.c_int, c.c_int)
        self.glGenBuffers = f('glGenBuffers', None, c.c_int, c.c_void_p)
        self.glBindBuffer = f('glBindBuffer', None, c.c_uint, c.c_uint)
        self.glBufferData = f('glBufferData', None, c.c_uint, c.c_ssize_t, c.c_void_p, c.c_uint)
        self.glGetString = f('glGetString', c.c_char_p, c.c_uint)
        # the target
        tex = c.c_uint()
        self.glGenTextures(1, c.byref(tex))
        self.target = tex.value
        self.glBindTexture(GL_TEXTURE_2D, self.target)
        self.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, None)
        for p, v in ((GL_TEXTURE_MIN_FILTER, GL_NEAREST), (GL_TEXTURE_MAG_FILTER, GL_NEAREST)):
            self.glTexParameteri(GL_TEXTURE_2D, p, v)
        fbo = c.c_uint()
        self.glGenFramebuffers(1, c.byref(fbo))
        self.glBindFramebuffer(GL_FRAMEBUFFER, fbo.value)
        self.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.target, 0)
        self.glViewport(0, 0, width, height)
        self.glEnable(GL_BLEND)
        self.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        vb = c.c_uint()
        self.glGenBuffers(1, c.byref(vb))
        self.vbo = vb.value
        self.programs = {}

    def renderer_name(self):
        return self.glGetString(0x1F01).decode()

    def _shader(self, kind, src):
        c = ctypes
        sh = self.glCreateShader(kind)
        arr = c.c_char_p(src.encode())
        self.glShaderSource(sh, 1, c.byref(arr), None)
        self.glCompileShader(sh)
        ok = c.c_int()
        self.glGetShaderiv(sh, GL_COMPILE_STATUS, c.byref(ok))
        if not ok.value:
            log = c.create_string_buffer(4096)
            self.glGetShaderInfoLog(sh, 4096, None, log)
            raise RuntimeError(log.value.decode())
        return sh

    def program(self, name):
        if name in self.programs:
            return self.programs[name]
        c = ctypes
        vs = open(os.path.join(SHADERS, VERTEX + '.frag')).read()
        fs = open(os.path.join(SHADERS, 'chaos_outfit_%s.frag' % name)).read()
        p = self.glCreateProgram()
        self.glAttachShader(p, self._shader(GL_VERTEX_SHADER, vs))
        self.glAttachShader(p, self._shader(GL_FRAGMENT_SHADER, fs))
        self.glBindAttribLocation(p, 0, b'a_Vertex')
        self.glBindAttribLocation(p, 1, b'a_TexCoord')
        self.glLinkProgram(p)
        ok = c.c_int()
        self.glGetProgramiv(p, GL_LINK_STATUS, c.byref(ok))
        if not ok.value:
            log = c.create_string_buffer(4096)
            self.glGetProgramInfoLog(p, 4096, None, log)
            raise RuntimeError(log.value.decode())
        self.programs[name] = p
        return p

    def texture(self, rgba):
        c = ctypes
        t = c.c_uint()
        self.glGenTextures(1, c.byref(t))
        self.glBindTexture(GL_TEXTURE_2D, t.value)
        h, w = rgba.shape[:2]
        data = np.ascontiguousarray(rgba)
        self.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data.ctypes.data)
        for p, v in ((GL_TEXTURE_MIN_FILTER, GL_NEAREST), (GL_TEXTURE_MAG_FILTER, GL_NEAREST),
                     (GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE), (GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)):
            self.glTexParameteri(GL_TEXTURE_2D, p, v)
        return t.value

    def draw(self, name, atlas, colours, t, ground=GROUND):
        """one frame: every 32 px tile of the sprite is its own quad from its own atlas (as the engine draws an outfit
        bigger than one tile), the whole sprite centred in the target; -> RGBA uint8 (H, W, 4) over the ground colour"""
        c = ctypes
        prog = self.program(name)
        self.glBindFramebuffer(GL_FRAMEBUFFER, self._fbo_id())
        self.glClearColor(ground[0] / 255.0, ground[1] / 255.0, ground[2] / 255.0, 1.0)
        self.glClear(GL_COLOR_BUFFER_BIT)
        self.glUseProgram(prog)
        sw, sh = atlas['sprite']
        ox, oy = (self.W - sw) // 2, (self.H - sh) // 2 + 4

        def loc(n):
            return self.glGetUniformLocation(prog, n.encode())
        proj = np.array([[2.0 / self.W, 0, 0], [0, -2.0 / self.H, 0], [-1.0, 1.0, 1.0]], np.float32)
        ident = np.eye(3, dtype=np.float32)
        m = np.zeros((4, 4), np.float32)
        for i, col in enumerate(colours):
            m[i] = col
        self.glUniformMatrix3fv(loc('u_ProjectionMatrix'), 1, 0, np.ascontiguousarray(proj).ctypes.data)
        self.glUniformMatrix3fv(loc('u_TransformMatrix'), 1, 0, ident.ctypes.data)
        self.glUniformMatrix4fv(loc('u_Color'), 1, 0, m.ctypes.data)
        self.glUniform1f(loc('u_Time'), float(t))
        self.glActiveTexture(0x84C0)
        self.glUniform1i(loc('u_Tex0'), 0)
        self.glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        self.glEnableVertexAttribArray(0)
        self.glEnableVertexAttribArray(1)
        self.glVertexAttribPointer(0, 2, GL_FLOAT, 0, 16, None)
        self.glVertexAttribPointer(1, 2, GL_FLOAT, 0, 16, c.c_void_p(8))
        for tile in atlas['tiles']:
            aw, ah = tile['size']
            sx, sy = tile['xy']
            x0, y0 = ox + tile['dx'], oy + tile['dy']
            tw = th = CELL
            verts = np.array([x0, y0, sx, sy, x0 + tw, y0, sx + tw, sy, x0, y0 + th, sx, sy + th, x0 + tw, y0 + th,
                              sx + tw, sy + th], np.float32)
            self.glBufferData(GL_ARRAY_BUFFER, verts.nbytes, verts.ctypes.data, GL_STATIC_DRAW)
            tex = np.array([[1.0 / aw, 0, 0], [0, 1.0 / ah, 0], [0, 0, 1.0]], np.float32)
            self.glUniformMatrix3fv(loc('u_TextureMatrix'), 1, 0, np.ascontiguousarray(tex).ctypes.data)
            self.glUniform2f(loc('u_Offset'), float(tile['offset'][0]), float(tile['offset'][1]))
            self.glBindTexture(GL_TEXTURE_2D, tile['id'])
            self.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        buf = np.zeros((self.H, self.W, 4), np.uint8)
        self.glReadPixels(0, 0, self.W, self.H, GL_RGBA, GL_UNSIGNED_BYTE, buf.ctypes.data)
        return buf[::-1].copy()

    def _fbo_id(self):
        if not hasattr(self, '_fbo'):
            c = ctypes
            v = c.c_uint()
            self.glGenFramebuffers(1, c.byref(v))
            self._fbo = v.value
            self.glBindFramebuffer(GL_FRAMEBUFFER, self._fbo)
            self.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.target, 0)
        return self._fbo

    def atlas(self, base, mask):
        """base and mask RGBA (h, w, 4). The engine draws an outfit bigger than 32 px as one quad per 32 px tile, each
        from its own place in a texture atlas, the colour template of the tile at a fixed offset from it. So every tile
        gets an atlas of its own, at a different place in it (a shader that reads v_Px rows sees no neighbour tile)"""
        h, w = base.shape[:2]
        tiles = []
        n = 0
        for ty in range(0, h, CELL):
            for tx in range(0, w, CELL):
                bx, by = 32 + 32 * ((n * 2) % 3), 32 + 32 * ((n * 5) % 4)
                img = np.zeros((224, 224, 4), np.uint8)
                img[by:by + CELL, bx:bx + CELL] = base[ty:ty + CELL, tx:tx + CELL]
                img[by:by + CELL, bx + 64:bx + 64 + CELL] = mask[ty:ty + CELL, tx:tx + CELL]
                tiles.append({'id': self.texture(img), 'size': (224, 224), 'xy': (bx, by), 'offset': (64, 0),
                              'dx': tx, 'dy': ty})
                n += 1
        return {'tiles': tiles, 'sprite': (w, h)}


# ------------------------------------------------------------------------------------------------ sheets and video
def sample_atlases(rd, pair, looks):
    if pair:
        pairs = pair_looks(pair[0], pair[1], looks)
    else:
        pairs = [synthetic_look(0), synthetic_look(1)]
    return [rd.atlas(b, m) for b, m in pairs]


def frame(rd, name, atlas, t, colours=None):
    return rd.draw(name, atlas, colours or COLOURS, t)


def names_arg(arg):
    names = [n.strip() for n in arg.split(',')] if arg else list(ORDER)
    for n in names:
        if not os.path.isfile(os.path.join(SHADERS, 'chaos_outfit_%s.frag' % n)):
            raise SystemExit('no shader chaos_outfit_%s.frag' % n)
    return names


def make_sheet(path, names, times, zoom, pair, looks):
    rd = Renderer()
    atlases = sample_atlases(rd, pair, looks)
    cols = [(a, t) for a in atlases[:2] for t in times]
    label_w = 112
    W = label_w + len(cols) * FRAME * zoom
    H = len(names) * FRAME * zoom
    sheet = Image.new('RGB', (W, H), (20, 20, 22))
    d = ImageDraw.Draw(sheet)
    for r, name in enumerate(names):
        d.text((6, r * FRAME * zoom + 6), name, fill=(235, 220, 170))
        for c, (a, t) in enumerate(cols):
            im = Image.fromarray(frame(rd, name, a, t), 'RGBA').convert('RGB')
            im = im.resize((FRAME * zoom, FRAME * zoom), Image.NEAREST)
            sheet.paste(im, (label_w + c * FRAME * zoom, r * FRAME * zoom))
    sheet.save(path)
    print('sheet %s (%dx%d, %s)' % (path, W, H, rd.renderer_name()))


def make_video(path, names, seconds, fps, zoom, pair, looks):
    if not shutil.which('ffmpeg'):
        raise SystemExit('ffmpeg is needed for the video')
    rd = Renderer()
    atlases = sample_atlases(rd, pair, looks)
    n = int(seconds * fps)
    cell = FRAME * zoom
    per_row = min(len(names), 4)
    rows = (len(names) + per_row - 1) // per_row
    W, H = per_row * cell, rows * cell
    W, H = W + W % 2, H + H % 2
    tmp = tempfile.mkdtemp(prefix='shaders_')
    try:
        for i in range(n):
            t = i / float(fps)
            sheet = Image.new('RGB', (W, H), (20, 20, 22))
            for k, name in enumerate(names):
                a = atlases[(k) % len(atlases)] if len(atlases) < 3 else atlases[k % 2]
                im = Image.fromarray(frame(rd, name, a, t), 'RGBA').convert('RGB').resize((cell, cell), Image.NEAREST)
                sheet.paste(im, ((k % per_row) * cell, (k // per_row) * cell))
                ImageDraw.Draw(sheet).text(((k % per_row) * cell + 4, (k // per_row) * cell + 4), name, fill=(235, 220, 170))
            sheet.save(os.path.join(tmp, 'f%04d.png' % i))
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', os.path.join(tmp, 'f%04d.png'),
                        '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18', '-movflags', '+faststart', path], check=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('video %s (%dx%d, %d frames at %d fps)' % (path, W, H, n, fps))


def check(names):
    rd = Renderer()
    atlases = sample_atlases(rd, None, [])
    bad = 0
    for name in names:
        try:
            frames = [frame(rd, name, atlases[0], t) for t in (0.0, 0.37, 1.1, 2.9)]
        except RuntimeError as e:
            print('FAIL %s: %s' % (name, e))
            bad += 1
            continue
        plain = np.array(Image.new('RGBA', (FRAME, FRAME), GROUND + (255,)))
        drawn = sum(int((np.abs(f[..., :3].astype(int) - plain[..., :3].astype(int)).sum(2) > 24).sum()) for f in frames)
        alpha_leak = 0
        # the ground behind a fully transparent corner must stay the ground: nothing is drawn outside the sprite box
        for f in frames:
            alpha_leak += int((np.abs(f[:4, :4, :3].astype(int) - np.array(GROUND)).sum(2) > 0).sum())
        if drawn == 0:
            print('FAIL %s: draws nothing' % name)
            bad += 1
        elif alpha_leak:
            print('FAIL %s: paints outside the sprite box (%d px)' % (name, alpha_leak))
            bad += 1
        else:
            print('ok   %s (%d px differ from the ground over 4 frames)' % (name, drawn))
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('mode', choices=['sheet', 'video', 'check'])
    ap.add_argument('out', nargs='?')
    ap.add_argument('--shaders')
    ap.add_argument('--times', default='0,0.5,1.0,1.5')
    ap.add_argument('--zoom', type=int, default=4)
    ap.add_argument('--seconds', type=float, default=4.0)
    ap.add_argument('--fps', type=int, default=20)
    ap.add_argument('--pair', nargs=2, metavar=('DAT', 'SPR'))
    ap.add_argument('--looks', default='128,129')
    a = ap.parse_args()
    names = names_arg(a.shaders)
    looks = [int(x) for x in a.looks.split(',')]
    if a.mode == 'check':
        sys.exit(1 if check(names) else 0)
    if not a.out:
        ap.error('an output path is needed')
    if a.mode == 'sheet':
        make_sheet(a.out, names, [float(x) for x in a.times.split(',')], a.zoom, a.pair, looks)
    else:
        make_video(a.out, names, a.seconds, a.fps, a.zoom, a.pair, looks)


if __name__ == '__main__':
    main()
