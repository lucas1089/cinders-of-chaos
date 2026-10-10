#!/usr/bin/env python3
"""Alert sounds of the loot filter rules (game_lootfilter, Hunt > Loot Filter > Rule counters and sounds).
Every sound is synthesised here from sine waves and noise (no recorded audio): short, quiet at the start and the end
(no clicks), mono 22050 Hz, written as Ogg Vorbis (the only format the client's sound manager reads).
  chime.ogg    two bright notes a fifth apart
  bell.ogg     one struck bell (inharmonic partials, long tail)
  ping.ogg     one short high ping
  drum.ogg     a low thump with a falling pitch and a little noise
  fanfare.ogg  three rising notes, the last one held
python3 -I client/tools/gen_lootfilter_sounds.py   (needs numpy and ffmpeg with libvorbis; writes into
client/overlay/modules/game_lootfilter/sounds/). The output is the same on every run (fixed noise seed, bitexact)."""
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_lootfilter', 'sounds')
RATE = 22050


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def envelope(n, attack=0.004, decay=6.0):
    t = np.arange(n) / RATE
    env = np.exp(-decay * t)
    a = max(1, int(RATE * attack))
    env[:a] *= np.linspace(0, 1, a)
    tail = min(n, int(RATE * 0.02))
    env[-tail:] *= np.linspace(1, 0, tail)  # no click at the end
    return env


def note(freq, seconds, decay, partials=((1, 1.0), (2, 0.25), (3, 0.08))):
    t = t_axis(seconds)
    wave_ = sum(a * np.sin(2 * np.pi * freq * m * t) for m, a in partials)
    return wave_ * envelope(len(t), decay=decay)


def place(total, parts):
    out = np.zeros(int(RATE * total))
    for start, sig in parts:
        i = int(RATE * start)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out


def chime():
    return place(0.7, [(0.0, note(1318.5, 0.6, 7.0)), (0.09, note(1975.5, 0.6, 6.0))])


def bell():
    f = 660.0
    parts = ((1, 1.0), (2.76, 0.45), (5.40, 0.25), (8.93, 0.12))
    t = t_axis(1.1)
    sig = sum(a * np.sin(2 * np.pi * f * m * t) * np.exp(-(2.5 + m * 0.8) * t) for m, a in parts)
    return sig * envelope(len(t), attack=0.002, decay=0.0)


def ping():
    return note(1760.0, 0.28, 16.0, partials=((1, 1.0), (2, 0.1)))


def drum():
    t = t_axis(0.38)
    freq = 55 + 70 * np.exp(-18 * t)  # the pitch falls from 125 Hz to 55 Hz
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    body = np.sin(phase) * np.exp(-9 * t)
    rng = np.random.default_rng(1098)
    noise = rng.uniform(-1, 1, len(t)) * np.exp(-40 * t) * 0.35
    return (body + noise) * envelope(len(t), attack=0.002, decay=0.0)


def fanfare():
    tri = ((1, 1.0), (3, 0.11), (5, 0.04))
    return place(0.9, [(0.0, note(1046.5, 0.16, 8.0, tri)), (0.13, note(1318.5, 0.16, 8.0, tri)),
                       (0.26, note(1568.0, 0.6, 4.5, tri))])


SOUNDS = {'chime': chime, 'bell': bell, 'ping': ping, 'drum': drum, 'fanfare': fanfare}


def write_wav(path, sig):
    sig = sig / max(1e-9, np.max(np.abs(sig))) * 0.8
    data = (sig * 32767).astype('<i2').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        sys.exit('ffmpeg (with libvorbis) is needed to write the .ogg files')
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for key, fn in SOUNDS.items():
            wav = os.path.join(tmp, key + '.wav')
            write_wav(wav, fn())
            ogg = os.path.join(OUT, key + '.ogg')
            subprocess.run([ffmpeg, '-loglevel', 'error', '-y', '-i', wav, '-map_metadata', '-1', '-fflags', '+bitexact',
                            '-flags:a', '+bitexact', '-c:a', 'libvorbis', '-q:a', '4', ogg], check=True)
            print('wrote', os.path.relpath(ogg), os.path.getsize(ogg), 'bytes')


if __name__ == '__main__':
    main()
