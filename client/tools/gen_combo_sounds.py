#!/usr/bin/env python3
"""Chimes of the spell combos (game_spellranks, O686 phase 6; docs/SPELL_UPGRADES.md 4.4). Two short sounds, synthesised from sine
waves (no recorded audio, no pack audio), built from the helpers of gen_lootfilter_sounds.py: mono 22050 Hz, quiet at the start and the
end, written as Ogg Vorbis (the only format the client's sound manager reads), peak 0.5 so a combo in a long fight is a soft touch:
  combo_a.ogg   an element reaction: two bright notes a fourth apart, fast
  combo_b.ogg   a signature combo: a lower pair with a bell partial, a little longer
usage: python3 -I client/tools/gen_combo_sounds.py          write client/overlay/modules/game_spellranks/sounds/ (needs numpy and ffmpeg with libvorbis)
       python3 -I client/tools/gen_combo_sounds.py --check  exit 1 when a file is missing, is no Ogg file or has an odd size (no numpy, no ffmpeg)
The output is the same on every run (no noise, bitexact encoder flags)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_spellranks', 'sounds')
NAMES = ('combo_a', 'combo_b')
MIN_BYTES, MAX_BYTES = 1500, 20000
PEAK = 0.5


def synth():
    """name -> samples (needs numpy)"""
    sys.path.insert(0, HERE)  # python -I leaves the script's folder out of sys.path
    import gen_lootfilter_sounds as G
    glassy = ((1, 1.0), (2, 0.18), (3, 0.05))
    belly = ((1, 1.0), (2.76, 0.22), (4.0, 0.10))
    return {
        'combo_a': G.place(0.42, [(0.0, G.note(1568.0, 0.3, 11.0, glassy)), (0.06, G.note(2093.0, 0.34, 9.0, glassy))]),
        'combo_b': G.place(0.55, [(0.0, G.note(659.3, 0.4, 7.0, belly)), (0.08, G.note(987.8, 0.46, 6.0, belly))]),
    }


def write_wav(path, sig):
    import wave
    import numpy as np
    sig = sig / max(1e-9, np.max(np.abs(sig))) * PEAK
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes((sig * 32767).astype('<i2').tobytes())


def check():
    bad = []
    for name in NAMES:
        path = os.path.join(OUT, name + '.ogg')
        if not os.path.isfile(path):
            bad.append(name + '.ogg is missing')
            continue
        with open(path, 'rb') as f:
            head = f.read(4)
        size = os.path.getsize(path)
        if head != b'OggS':
            bad.append(name + '.ogg is not an Ogg file')
        if not MIN_BYTES <= size <= MAX_BYTES:
            bad.append('%s.ogg has %d bytes, expected %d to %d' % (name, size, MIN_BYTES, MAX_BYTES))
    for line in bad:
        print('FAIL ' + line)
    if not bad:
        print('combo sounds ok (%s)' % ', '.join(NAMES))
    return 1 if bad else 0


def main(argv):
    if '--check' in argv:
        return check()
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        sys.exit('ffmpeg (with libvorbis) is needed to write the .ogg files')
    os.makedirs(OUT, exist_ok=True)
    sounds = synth()
    with tempfile.TemporaryDirectory() as tmp:
        for name in NAMES:
            wav = os.path.join(tmp, name + '.wav')
            write_wav(wav, sounds[name])
            ogg = os.path.join(OUT, name + '.ogg')
            subprocess.run([ffmpeg, '-loglevel', 'error', '-y', '-i', wav, '-map_metadata', '-1', '-fflags', '+bitexact',
                            '-flags:a', '+bitexact', '-c:a', 'libvorbis', '-q:a', '4', ogg], check=True)
            print('wrote', os.path.relpath(ogg), os.path.getsize(ogg), 'bytes')
    return check()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
