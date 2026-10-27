#!/usr/bin/env python3
"""Game sounds of game_chaossound (O238): the short Ogg Vorbis files in client/overlay/modules/game_chaossound/sounds/.

The sounds are picks from four CC0 sound packs (docs/CREDITS.md, internal labels "sfx impact", "sfx rpg",
"sfx interface", "sfx scifi"; licence checked in each pack's own licence text: Creative Commons Zero). Each pick is cut,
turned to mono and set to a fixed level here with ffmpeg; client/tools/sfx_sources.csv records the pick, the cut, the
level (the peak, dBFS) and the sha256 of the file made.

  python3 -I client/tools/gen_sfx.py --check          # the committed files match the csv (no ffmpeg, no packs needed)
  python3 -I client/tools/gen_sfx.py --packs DIR      # build: DIR/impact, DIR/rpg, DIR/interface, DIR/scifi hold the
                                                      # unzipped packs (their Audio folders); writes the files and the
                                                      # sha256 column (needs ffmpeg with libvorbis)

--check fails when a csv row has no file, a file has no row, a hash differs, a file is not mono Ogg Vorbis at 44100 Hz,
a sound is longer than MAX_SECONDS (or decodes to more than the engine's 100000 byte cache), or the folder is over MAX_BYTES (the whole set must stay small: it ships in the
client). The files are not rebuilt in CI: another ffmpeg build gives other bytes; the hash pins what was reviewed."""
import csv
import hashlib
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, 'sfx_sources.csv')
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_chaossound', 'sounds')
RATE = 44100
MAX_SECONDS = 1.1
# The engine (SoundManager) keeps a sound in a preloaded buffer only when it is at most MAX_CACHE_SIZE = 100000 bytes decoded
# (16 bit PCM). A longer one is streamed through 4 refilled buffers per play, which failed in the field ("unable to refill
# audio buffer", OpenAL Invalid Name / Out of Memory, a source that never ended). Mono 44100 Hz is 88200 bytes a second.
MAX_CACHE_BYTES = 100000
MAX_BYTES = 1_000_000
FIELDS = ['file', 'pack', 'source', 'trim_ms', 'peak_db', 'lowpass_hz', 'sha256']
PACK_DIR = {'sfx impact': 'impact', 'sfx rpg': 'rpg', 'sfx interface': 'interface', 'sfx scifi': 'scifi'}


def read_rows():
    with open(CSV, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def write_rows(rows):
    with open(CSV, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def ogg_info(data):
    """(channels, rate, seconds) of an Ogg Vorbis stream, or None when it is not one."""
    if data[:4] != b'OggS' or b'\x01vorbis' not in data[:80]:
        return None
    i = data.index(b'\x01vorbis', 0, 80)
    channels = data[i + 11]
    rate = struct.unpack('<I', data[i + 12:i + 16])[0]
    last = data.rfind(b'OggS')
    granule = struct.unpack('<q', data[last + 6:last + 14])[0]
    return channels, rate, max(0, granule) / float(rate or 1)


def check():
    rows = read_rows()
    errs = []
    names = set()
    total = 0
    for r in rows:
        name = r['file']
        names.add(name + '.ogg')
        path = os.path.join(OUT, name + '.ogg')
        if not os.path.isfile(path):
            errs.append('%s: no file' % name)
            continue
        data = open(path, 'rb').read()
        total += len(data)
        if hashlib.sha256(data).hexdigest() != r['sha256']:
            errs.append('%s: sha256 differs from the csv' % name)
        info = ogg_info(data)
        if not info:
            errs.append('%s: not an Ogg Vorbis file' % name)
            continue
        ch, rate, secs = info
        if ch != 1 or rate != RATE:
            errs.append('%s: %d channel(s) at %d Hz (want mono, %d Hz)' % (name, ch, rate, RATE))
        if secs > MAX_SECONDS:
            errs.append('%s: %.2f s is over %.1f s' % (name, secs, MAX_SECONDS))
        if int(round(secs * rate)) * 2 * ch > MAX_CACHE_BYTES:
            errs.append('%s: decodes to %d bytes, over the engine cache of %d (it would be streamed)'
                        % (name, int(round(secs * rate)) * 2 * ch, MAX_CACHE_BYTES))
    for f in sorted(os.listdir(OUT)):
        if f.endswith('.ogg') and f not in names:
            errs.append('%s: file has no csv row' % f)
    if total > MAX_BYTES:
        errs.append('sounds are %d bytes, over %d' % (total, MAX_BYTES))
    if errs:
        print('\n'.join(errs))
        return 1
    print('gen_sfx: %d sounds, %d bytes: ok' % (len(rows), total))
    return 0


def build(packs):
    rows = read_rows()
    os.makedirs(OUT, exist_ok=True)
    for r in rows:
        d = PACK_DIR[r['pack']]
        src = os.path.join(packs, d, 'Audio', r['source'] + '.ogg')
        if not os.path.isfile(src):
            src = os.path.join(packs, d, r['source'] + '.ogg')
        out = os.path.join(OUT, r['file'] + '.ogg')
        chain = ['pan=mono|c0=0.5*c0+0.5*c1', 'aresample=%d' % RATE]
        low = int(r['lowpass_hz'] or 0)
        if low:
            chain.append('lowpass=f=%d' % low)
        trim = int(r['trim_ms'] or 0)
        cmd = ['-y', '-i', src]
        if trim:
            cmd += ['-t', '%.3f' % (trim / 1000.0)]
            chain.append('afade=t=out:st=%.3f:d=0.06' % max(0, trim / 1000.0 - 0.06))
        # level: measure the peak of the cut, then set it to the row's peak_db (dBFS)
        probe = subprocess.run(['ffmpeg', '-hide_banner', '-nostats'] + cmd + ['-af', ','.join(chain + ['volumedetect']), '-f', 'null', '-'],
                               capture_output=True, text=True, check=True).stderr
        peak = float(probe.split('max_volume:')[1].split('dB')[0])
        chain.append('volume=%.2fdB' % (float(r['peak_db']) - peak))
        cmd = ['ffmpeg', '-v', 'error'] + cmd + ['-af', ','.join(chain), '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact',
                '-c:a', 'libvorbis', '-q:a', '2', out]
        subprocess.run(cmd, check=True)
        r['sha256'] = hashlib.sha256(open(out, 'rb').read()).hexdigest()
    write_rows(rows)
    return check()


def main(argv):
    if '--check' in argv:
        return check()
    if '--packs' in argv:
        return build(argv[argv.index('--packs') + 1])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
