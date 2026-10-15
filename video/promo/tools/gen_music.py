"""Procedural score of the trailer: original music made from code, owned by the project.

Usage: python3 -I video/promo/tools/gen_music.py [--cut trailer|short] [--out FILE.wav] [--seed N]

Dark fantasy in D minor at the tempo of src/trailer_timing.json (120 BPM: a cut on the half-second grid falls on a
beat): low drones, a plucked minor-key ostinato (i - VI - VII - V), taiko-like drums, risers into booms, a pad, and a
quiet outro. Every scene cut of the chosen cut list gets a drum hit, `big` marks a boom, `act` a boom after a riser,
so the music follows the edit when the table changes. No samples, no third-party audio: every sound is synthesised
here with numpy (scipy for filters and the reverb when it is installed). Deterministic: the same table and seed give
the same file.

Default output: public/audio/<cut>_score.wav (48 kHz, 16-bit stereo; public/audio is git-ignored).
"""
import argparse
import json
import os
import wave

import numpy as np

try:
    from scipy.signal import butter, fftconvolve, sosfilt
except ImportError:  # the score still builds without scipy, with plainer filters
    butter = fftconvolve = sosfilt = None

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
TIMING = os.path.join(ROOT, 'src', 'trailer_timing.json')
SR = 48000

# D minor. MIDI numbers.
D2, A2, D3 = 38, 45, 50
# i - VI - VII - V, one chord per bar: root and the three ostinato tones
PROGRESSION = [
    (38, [50, 53, 57, 62]),  # Dm
    (34, [46, 50, 53, 58]),  # Bb
    (36, [48, 52, 55, 60]),  # C
    (33, [45, 49, 52, 57]),  # A (major V, the harmonic minor's leading tone)
]
# loudness of each layer per section (0..1)
SECTIONS = {
    #             drone ostin bass  drums pad
    'coldopen':  (0.70, 0.35, 0.00, 0.55, 0.00),
    'title':     (0.90, 0.00, 0.40, 0.00, 0.55),
    'world':     (0.75, 0.70, 0.45, 0.45, 0.30),
    'build':     (0.75, 0.80, 0.60, 0.65, 0.40),
    'instances': (0.85, 0.95, 0.80, 0.90, 0.55),
    'endgame':   (0.85, 1.00, 0.85, 0.95, 0.60),
    'finale':    (0.95, 1.00, 1.00, 1.00, 0.75),
    'outro':     (0.60, 0.00, 0.00, 0.00, 0.60),
}


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def lowpass(x, hz, order=2):
    if sosfilt is not None:
        return sosfilt(butter(order, hz, 'low', fs=SR, output='sos'), x)
    a = np.exp(-2 * np.pi * hz / SR)  # one-pole fallback
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    if sosfilt is not None:
        return sosfilt(butter(2, [lo, hi], 'band', fs=SR, output='sos'), x)
    return lowpass(x, hi) - lowpass(x, lo)


def saw(freq, t, harmonics=12):
    """Band-limited sawtooth from its first harmonics."""
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2.2:
            break
        out += np.sin(2 * np.pi * freq * k * t) / k
    return out


def load_cut(cut):
    with open(TIMING, encoding='utf-8') as f:
        table = json.load(f)
    by_id = {s['id']: s for s in table['scenes']}
    scenes, t = [], 0.0
    for e in table['cuts'][cut]:
        sid, dur = (e[0], e[1]) if isinstance(e, list) else (e, by_id[e]['dur'])
        s = dict(by_id[sid])
        s['start'], s['dur'] = t, dur
        scenes.append(s)
        t += dur
    return table, scenes, t


class Score:
    def __init__(self, length, seed):
        self.n = int(length * SR)
        self.dry = np.zeros((2, self.n))
        self.wet = np.zeros((2, self.n))  # reverb send
        self.rng = np.random.default_rng(seed)

    def add(self, at, sig, gain=1.0, pan=0.0, send=0.3):
        i = int(at * SR)
        if i >= self.n:
            return
        sig = sig[: self.n - i] * gain
        left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        for ch, g in ((0, left), (1, right)):
            self.dry[ch, i:i + len(sig)] += sig * g * (1 - send * 0.5)
            self.wet[ch, i:i + len(sig)] += sig * g * send

    # ------------------------------------------------------------------ instruments
    def taiko(self, at, gain=1.0, pitch=1.0, pan=0.0):
        d = 0.9
        t = np.arange(int(d * SR)) / SR
        f = (55 + 95 * np.exp(-t * 28)) * pitch
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6.5)
        skin = bandpass(self.rng.standard_normal(len(t)), 180, 2400) * np.exp(-t * 38) * 0.45
        self.add(at, np.tanh((body + skin) * 1.6), gain * 0.55, pan, send=0.25)

    def boom(self, at, gain=1.0):
        d = 3.2
        t = np.arange(int(d * SR)) / SR
        f = 32 + 70 * np.exp(-t * 9)
        sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
        crack = lowpass(self.rng.standard_normal(len(t)), 3500) * np.exp(-t * 14) * 0.6
        tail = lowpass(self.rng.standard_normal(len(t)), 500) * np.exp(-t * 2.2) * 0.25
        self.add(at, np.tanh((sub + crack + tail) * 1.4), gain * 0.8, 0.0, send=0.45)

    def riser(self, end, length=2.0, gain=1.0):
        t = np.arange(int(length * SR)) / SR
        k = t / length
        noise = self.rng.standard_normal(len(t))
        # a band of noise that climbs, plus a rising tone, swelling into the hit
        bands = [bandpass(noise, 300 + 2500 * a, 600 + 5000 * a) * ((k >= a) & (k < a + 0.25))
                 for a in np.linspace(0, 0.75, 4)]
        swept = sum(bands) * (k ** 2.2)
        f = 110 * 2 ** (k * 2.5)
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * (k ** 3) * 0.35
        self.add(max(0.0, end - length), swept * 0.5 + tone, gain * 0.5, 0.0, send=0.6)

    def pluck(self, at, note, gain, dur=0.45, pan=0.0):
        t = np.arange(int(dur * SR)) / SR
        f = midi_hz(note)
        tone = (saw(f, t, 10) + 0.5 * saw(f * 1.004, t, 10)) * np.exp(-t * 7.5)
        tone = lowpass(tone, 1400 + 1800 * gain)
        att = np.minimum(1, t / 0.004)
        self.add(at, tone * att, gain * 0.16, pan, send=0.35)

    def drone(self, start, end, notes, level_fn):
        t = np.arange(int((end - start) * SR)) / SR
        sig = np.zeros_like(t)
        for i, n in enumerate(notes):
            f = midi_hz(n)
            sig += saw(f * (1 + 0.0015 * i), t, 18) + saw(f * (1 - 0.0021 * i), t, 18)
        wob = 0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t)
        sig = lowpass(sig, 260 + 140 * wob.mean()) * level_fn(start + t)
        self.add(start, sig, 0.06, 0.0, send=0.2)

    def pad(self, at, notes, dur, gain):
        t = np.arange(int(dur * SR)) / SR
        sig = np.zeros_like(t)
        for i, n in enumerate(notes):
            f = midi_hz(n)
            vib = 1 + 0.003 * np.sin(2 * np.pi * (4.6 + 0.3 * i) * t)
            ph = 2 * np.pi * np.cumsum(f * vib) / SR
            sig += np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
        env = np.minimum(1, t / 0.6) * np.minimum(1, (dur - t) / 0.5).clip(0)
        sig = bandpass(sig, 250, 2600) * env
        self.add(at, sig, gain * 0.05, 0.0, send=0.7)

    def bass(self, at, note, dur, gain):
        t = np.arange(int(dur * SR)) / SR
        f = midi_hz(note)
        sig = lowpass(saw(f, t, 8), 180) + 0.6 * np.sin(2 * np.pi * f * t)
        env = np.minimum(1, t / 0.02) * np.exp(-t * 0.9) * np.minimum(1, (dur - t) / 0.08).clip(0)
        self.add(at, sig * env, gain * 0.22, 0.0, send=0.1)

    # ------------------------------------------------------------------ mix
    def render(self):
        ir_len = int(2.6 * SR)
        t = np.arange(ir_len) / SR
        out = self.dry.copy()
        for ch in range(2):
            ir = self.rng.standard_normal(ir_len) * np.exp(-t * 2.4)
            ir = lowpass(ir, 4500)
            ir /= np.sqrt(np.sum(ir ** 2))
            if fftconvolve is not None:
                rev = fftconvolve(self.wet[ch], ir)[: self.n]
            else:  # without scipy: a few feedback echoes instead of a convolution reverb
                rev = np.zeros(self.n)
                for k, d in enumerate((0.031, 0.047, 0.071, 0.113, 0.173)):
                    s = int(d * SR)
                    rev[s:] += self.wet[ch][:-s] * 0.5 ** (k + 1)
            out[ch] += rev * 0.9
        out = np.tanh(out * 1.2)
        peak = np.max(np.abs(out)) or 1.0
        return out / peak * 0.89  # about -1 dBFS


def compose(scenes, length, seed, bpm):
    sc = Score(length, seed)
    beat = 60.0 / bpm
    bar = beat * 4

    def section_at(x):
        for s in scenes:
            if s['start'] <= x < s['start'] + s['dur']:
                return s['section']
        return scenes[-1]['section']

    def level(layer):
        idx = ['drone', 'ostinato', 'bass', 'drums', 'pad'].index(layer)
        return lambda x: SECTIONS[section_at(x)][idx]

    outro = next(s['start'] for s in scenes if s['section'] == 'outro')

    # drones: D and A, the whole piece, swelling with the sections (vectorised level per sample)
    lv = np.vectorize(lambda x: SECTIONS[section_at(x)][0])
    sc.drone(0.0, length, [D2 - 12, D2, A2], lambda tt: np.interp(tt, np.arange(0, length + 0.5, 0.25),
                                                                     lv(np.arange(0, length + 0.5, 0.25))))

    # ostinato: eighth notes over the progression; an octave up from the third act
    steps = int(length / (beat / 2))
    pattern = [0, 1, 2, 1, 3, 2, 1, 2]
    for i in range(steps):
        x = i * beat / 2
        g = level('ostinato')(x)
        if g <= 0 or x >= outro:
            continue
        root, tones = PROGRESSION[int(x // bar) % 4]
        note = tones[pattern[i % 8]] + (12 if section_at(x) in ('instances', 'endgame', 'finale') and i % 2 else 0)
        accent = 1.0 if i % 4 == 0 else 0.7
        sc.pluck(x, note, g * accent, pan=-0.35 if i % 2 else 0.35)

    # bass and pad: one chord per bar
    for b in range(int(length // bar) + 1):
        x = b * bar
        if x >= outro:
            break
        root, tones = PROGRESSION[b % 4]
        gb, gp = level('bass')(x), level('pad')(x)
        if gb > 0:
            sc.bass(x, root, bar, gb)
        if gp > 0:
            sc.pad(x, [tones[0] + 12, tones[1] + 12, tones[2] + 12], bar + 0.4, gp)

    # drums: a groove per section, plus a hit on every cut
    for i in range(int(length / (beat / 2))):
        x = i * beat / 2
        sec = section_at(x)
        g = SECTIONS[sec][3]
        if g <= 0 or x >= outro:
            continue
        pos = i % 8  # eighths in the bar
        if sec == 'coldopen':
            hits = {0: 1.0, 4: 0.7}
        elif sec in ('world', 'build'):
            hits = {0: 1.0, 3: 0.5, 4: 0.8, 6: 0.4}
        else:
            hits = {0: 1.0, 2: 0.55, 3: 0.45, 4: 0.85, 6: 0.6, 7: 0.4}
        if pos in hits:
            sc.taiko(x, g * hits[pos] * 0.8, pitch=1.0 if pos in (0, 4) else 1.35, pan=0.15 * ((pos % 3) - 1))
    for s in scenes:
        x = s['start']
        mark = s.get('mark')
        if mark in ('big', 'act'):
            sc.boom(x, 1.0 if mark == 'act' else 0.8)
        if mark == 'act' and x >= 1.5:
            sc.riser(x, 2.0 if x >= 2.0 else x)
        if mark in ('hit', 'big', 'act'):
            sc.taiko(x, 0.9, pitch=0.9)
            if s['section'] in ('finale', 'coldopen'):
                sc.taiko(x + beat / 4, 0.45, pitch=1.5)

    # outro: the last chord held on the pad, the drone dying away
    sc.pad(outro + 0.2, [D3, D3 + 3, D3 + 7, D3 + 12], length - outro, 0.9)
    sc.pluck(outro + 1.0, D3 + 12, 0.5, dur=1.6)
    sc.pluck(outro + 2.0, D3 + 15, 0.35, dur=1.6)
    out = sc.render()

    # fades: in over 0.4 s, out over the last 1.8 s
    n = out.shape[1]
    fade_in = np.minimum(1, np.arange(n) / (0.4 * SR))
    fade_out = np.minimum(1, (n - np.arange(n)) / (1.8 * SR))
    return out * fade_in * fade_out


def write_wav(path, stereo):
    pcm = (np.clip(stereo.T, -1, 1) * 32767).astype('<i2')
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--cut', default='trailer')
    ap.add_argument('--out')
    ap.add_argument('--seed', type=int, default=1098)
    a = ap.parse_args()
    table, scenes, length = load_cut(a.cut)
    out = a.out or os.path.join(ROOT, 'public', 'audio', '%s_score.wav' % a.cut)
    write_wav(out, compose(scenes, length, a.seed, table.get('bpm', 120)))
    print('%s: %.1f s, %d cuts' % (os.path.relpath(out, ROOT) if out.startswith(ROOT) else out, length, len(scenes)))


if __name__ == '__main__':
    main()
