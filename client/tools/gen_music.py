#!/usr/bin/env python3
"""Region music of game_chaosmusic (O408): six loops synthesised here, our own work (no samples, no recorded audio).

  town     F major, 72 bpm: warm pad, harp arpeggios, a flute tune in the middle part
  hunt     E phrygian, 84 bpm: low drone with a slow filter, a muted pulse, sparse frame drums, a lonely lead
  dungeon  C, 64 bpm: dissonant clusters over a C pedal, bells on tritones, a noise wind, deep booms
  boss     D minor, 120 bpm: taiko pattern, bass ostinato in eighths, dark strings, a horn theme
  arena    A minor, 112 bpm: drums, claps and shakers, bass pulse, horn calls over i-VII-VI-V
  login    D minor, 66 bpm: the main theme over pad, harp and bells

Every track is a whole number of bars. Notes, reverb tails and the filter and compressor envelopes wrap around the
end (circular rendering and convolution), so the last sample flows into the first: the loop has no seam. Each track is
loudness-normalised (RMS of the loop to TARGET_RMS_DB, peaks under PEAK_DB after a soft compressor), stereo 44100 Hz,
Ogg Vorbis (ffmpeg with libvorbis, bitexact, quality QUALITY).

  python3 -I client/tools/gen_music.py --check     # the committed files match client/tools/music_sources.csv (no numpy,
                                                   # no ffmpeg): hash, stereo, rate, length, total size, recipe
  python3 -I client/tools/gen_music.py --build     # writes the .ogg files and the csv (needs numpy and ffmpeg)
  python3 -I client/tools/gen_music.py --build --only town --wav DIR   # one track, also the PCM as a .wav in DIR

The synthesis is deterministic (fixed seeds), but another ffmpeg or numpy build can give other bytes, so CI does not
rebuild: the csv pins the reviewed files and the recipe column (sha256 of this script) fails --check when the script
changed after the last build."""
import csv
import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, 'music_sources.csv')
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_chaosmusic', 'music')
RATE = 44100
QUALITY = '0'
MIN_SECONDS, MAX_SECONDS = 60.0, 120.0
MAX_BYTES = 6_000_000
TARGET_RMS_DB = -20.0
PEAK_DB = -1.5
FIELDS = ['file', 'region', 'key', 'bpm', 'bars', 'seconds', 'rms_db', 'peak_db', 'recipe', 'sha256']


def recipe():
    return hashlib.sha256(open(os.path.abspath(__file__), 'rb').read()).hexdigest()[:16]


# ---------------------------------------------------------------- --check (standard library only)
def read_rows():
    with open(CSV, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


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
    want = recipe()
    for r in rows:
        name = r['file']
        names.add(name + '.ogg')
        if r['region'] not in TRACKS:
            errs.append('%s: region %r has no recipe here' % (name, r['region']))
        if r['recipe'] != want:
            errs.append('%s: built by another version of gen_music.py (recipe %s, now %s): run --build'
                        % (name, r['recipe'], want))
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
        if ch != 2 or rate != RATE:
            errs.append('%s: %d channel(s) at %d Hz (want stereo, %d Hz)' % (name, ch, rate, RATE))
        if not MIN_SECONDS <= secs <= MAX_SECONDS:
            errs.append('%s: %.2f s is outside %d-%d s' % (name, secs, MIN_SECONDS, MAX_SECONDS))
        if abs(secs - float(r['seconds'])) > 0.01:
            errs.append('%s: %.3f s in the file, %s s in the csv' % (name, secs, r['seconds']))
        if float(r['peak_db']) > PEAK_DB + 0.05:
            errs.append('%s: peak %s dBFS is over %.1f' % (name, r['peak_db'], PEAK_DB))
    for region in TRACKS:
        if region not in [r['region'] for r in rows]:
            errs.append('%s: recipe has no file' % region)
    if os.path.isdir(OUT):
        for f in sorted(os.listdir(OUT)):
            if f.endswith('.ogg') and f not in names:
                errs.append('%s: file has no csv row' % f)
    if total > MAX_BYTES:
        errs.append('music is %d bytes, over %d' % (total, MAX_BYTES))
    if errs:
        print('\n'.join(errs))
        return 1
    print('gen_music: %d tracks, %d bytes: ok' % (len(rows), total))
    return 0


# ---------------------------------------------------------------- music: notes and keys
NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def m(name):
    """'C#4' / 'Bb3' -> midi number (C4 = 60)."""
    n = NOTE[name[0]]
    i = 1
    while i < len(name) and name[i] in '#b':
        n += 1 if name[i] == '#' else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


CHORD = {'': (0, 4, 7), 'm': (0, 3, 7), 'maj7': (0, 4, 7, 11), 'm7': (0, 3, 7, 10), '7': (0, 4, 7, 10),
         'sus4': (0, 5, 7), 'sus2': (0, 2, 7), 'm9': (0, 3, 7, 10, 14), 'dim': (0, 3, 6), 'madd2': (0, 2, 3, 7),
         'mb2': (0, 1, 3, 7), 'maj7#11': (0, 4, 7, 11, 18), '7sus4': (0, 5, 7, 10), 'mb5': (0, 3, 6, 10)}


def chord(root, kind, octave=3):
    r = m(root + str(octave))
    return [r + i for i in CHORD[kind]]


# a track: TRACKS[region] = {key, bpm, bars, seed, reverb, build(score)}; build fills the score with events
TRACKS = {}


def track(region, key, bpm, bars, seed, reverb):
    def deco(fn):
        TRACKS[region] = {'key': key, 'bpm': bpm, 'bars': bars, 'seed': seed, 'reverb': reverb, 'build': fn}
        return fn
    return deco


class Score:
    """Events in beats. Each event goes to a bus: pad (filtered by the track's sweep), lead, perc, bass."""

    def __init__(self, bpm, bars, beats=4):
        self.bpm, self.bars, self.beats = bpm, bars, beats
        self.events = []

    def note(self, bus, inst, beat, dur, midi, vel=0.7, pan=0.0, **kw):
        self.events.append((bus, inst, beat, dur, midi, vel, pan, kw))

    def bar(self, b):
        return b * self.beats

    def phrase(self, bus, inst, start_bar, notes, octave=0, vel=0.6, pan=0.0, **kw):
        """notes: [(beat in the bar, length in beats, 'A4')], one list per bar from start_bar."""
        for i, bar in enumerate(notes):
            for beat, dur, name in bar:
                self.note(bus, inst, self.bar(start_bar + i) + beat, dur, m(name) + 12 * octave, vel, pan, **kw)


# ---------------------------------------------------------------- the tracks
@track('town', 'F major', 72, 24, 11, {'seconds': 3.2, 'mix': 0.32, 'damp': 4500})
def town(s):
    prog = [('F', 'maj7'), ('A', 'm7'), ('Bb', 'maj7'), ('C', 'sus4'), ('D', 'm7'), ('Bb', 'maj7'), ('F', 'maj7'), ('G', 'm7')]
    for b in range(24):
        root, kind = prog[b % 8]
        notes = chord(root, kind, 3)
        for i, n in enumerate(notes):
            s.note('pad', 'warm', s.bar(b), 4.0, n + (12 if i == 0 and n < m('E3') else 0), 0.22, pan=(i - 1.5) * 0.3)
        bass = m(root + '2')
        if b % 8 == 6:
            bass = m('A1')
        s.note('bass', 'sub', s.bar(b), 2.0, bass, 0.5)
        s.note('bass', 'sub', s.bar(b) + 2, 2.0, bass + (7 if b % 2 else 0), 0.4)
        if b % 8 == 3:  # the sus resolves on beat 3
            s.note('pad', 'warm', s.bar(b) + 2, 2.0, m('E4'), 0.16, pan=0.2)
        # harp: up the chord over two octaves in eighths, down on the last beat
        arp = sorted(set([n + 12 for n in notes] + [n + 24 for n in notes[:3]]))
        seq = arp[:6] + [arp[-1], arp[3]]
        for k in range(8):
            v = 0.32 if k % 2 == 0 else 0.22
            s.note('lead', 'pluck', s.bar(b) + k * 0.5, 1.5, seq[k % len(seq)], v, pan=-0.35 + 0.1 * (k % 8))
    tune = [
        [(0, 1.5, 'C5'), (1.5, 0.5, 'D5'), (2, 2, 'C5')],
        [(0, 1, 'A4'), (1, 1, 'G4'), (2, 2, 'E4')],
        [(0, 1.5, 'F4'), (1.5, 0.5, 'G4'), (2, 1, 'A4'), (3, 1, 'D5')],
        [(0, 2, 'C5'), (2, 2, 'E4')],
        [(0, 1.5, 'A4'), (1.5, 0.5, 'C5'), (2, 2, 'F5')],
        [(0, 1, 'D5'), (1, 1, 'C5'), (2, 2, 'A4')],
        [(0, 1.5, 'C5'), (1.5, 0.5, 'Bb4'), (2, 1, 'A4'), (3, 1, 'G4')],
        [(0, 3, 'F4'), (3, 1, 'G4')],
    ]
    s.phrase('lead', 'flute', 8, tune, vel=0.62, pan=0.1)
    s.phrase('lead', 'flute', 16, tune, vel=0.52, pan=0.1)
    s.phrase('lead', 'bell', 16, tune, octave=1, vel=0.16, pan=-0.3)


@track('hunt', 'E phrygian', 84, 32, 23, {'seconds': 3.6, 'mix': 0.36, 'damp': 3500})
def hunt(s):
    prog = [('E', 'm'), ('E', 'm'), ('F', ''), ('F', ''), ('E', 'm'), ('E', 'm'), ('D', 'm'), ('C', '')]
    for b in range(32):
        root, kind = prog[b % 8]
        if b % 4 == 0:  # the drone: E and B, re-struck every 4 bars, long
            s.note('pad', 'drone', s.bar(b), 16.0, m('E1'), 0.42)
            s.note('pad', 'drone', s.bar(b), 16.0, m('B1'), 0.26, pan=0.2)
        notes = chord(root, kind, 3)
        for i, n in enumerate(notes):
            s.note('pad', 'pad', s.bar(b), 4.0, n, 0.15, pan=(i - 1) * 0.4)
        # the muted pulse: eighths on the root, accent on 1 and the and of 2
        for k in range(8):
            v = 0.36 if k in (0, 3) else 0.18
            s.note('bass', 'mute', s.bar(b) + k * 0.5, 0.5, m(root + '2'), v, pan=-0.15)
        # sparse drums: a frame drum on 1, a low tom late in every other bar, a heartbeat every 4 bars
        s.note('perc', 'frame', s.bar(b), 1, 0, 0.55)
        if b % 2 == 1:
            s.note('perc', 'tom', s.bar(b) + 3.5, 1, 0, 0.4, pan=0.3)
        if b % 4 == 2:
            s.note('perc', 'kick', s.bar(b), 1, 0, 0.6)
            s.note('perc', 'kick', s.bar(b) + 0.5, 1, 0, 0.45)
        if b % 8 == 7:
            s.note('perc', 'metal', s.bar(b) + 2, 4, m('B5'), 0.22, pan=-0.4)
    lead = [
        [(0, 1, 'E4'), (1, 1, 'F4'), (2, 2, 'E4')], [],
        [(0, 1.5, 'G4'), (1.5, 0.5, 'F4'), (2, 2, 'E4')], [(0, 2, 'D4'), (2, 2, 'B3')],
        [(0, 1, 'E4'), (1, 1, 'G4'), (2, 2, 'B4')], [(0, 2, 'A4'), (2, 2, 'G4')],
        [(0, 1.5, 'F4'), (1.5, 0.5, 'G4'), (2, 2, 'F4')], [(0, 4, 'E4')],
    ]
    s.phrase('lead', 'flute', 8, lead, octave=0, vel=0.42, pan=0.15)
    s.phrase('lead', 'horn', 24, lead, octave=-1, vel=0.34, pan=-0.1)


@track('dungeon', 'C (dissonant)', 64, 24, 37, {'seconds': 5.5, 'mix': 0.48, 'damp': 2800})
def dungeon(s):
    clusters = [('C', 'mb2'), ('Ab', 'maj7#11'), ('F#', 'dim'), ('C', 'mb2'), ('Db', 'maj7'), ('G', 'mb5')]
    for i, (root, kind) in enumerate(clusters):
        b = i * 4
        s.note('pad', 'drone', s.bar(b), 16.0, m('C1'), 0.45)
        s.note('pad', 'drone', s.bar(b), 16.0, m('Gb1') if i % 2 else m('G1'), 0.2, pan=-0.2)
        notes = chord(root, kind, 3)
        for k, n in enumerate(notes):
            s.note('pad', 'dark', s.bar(b), 16.0, n, 0.14, pan=(k - 2) * 0.3)
        # a swell: one cluster tone fades in over two bars and stops
        s.note('pad', 'swell', s.bar(b + 2), 8.0, notes[-1] + 12, 0.2, pan=0.4 if i % 2 else -0.4)
        s.note('perc', 'boom', s.bar(b), 1, 0, 0.7)
        s.note('perc', 'wind', s.bar(b + 1), 12, 0, 0.32, pan=0.0)
    bells = [(1, 1.0, 'Db5'), (1, 3.0, 'C5'), (3, 0.5, 'Gb5'), (5, 2.0, 'G4'), (6, 1.0, 'Ab5'), (7, 3.5, 'D5'),
             (9, 0.0, 'F#5'), (10, 2.0, 'C6'), (13, 1.0, 'Db5'), (13, 2.5, 'G4'), (15, 0.0, 'E5'), (17, 2.0, 'Bb5'),
             (18, 3.0, 'A4'), (21, 1.0, 'Gb5'), (21, 1.5, 'F5'), (22, 3.0, 'C5'), (23, 2.0, 'B4')]
    for i, (b, beat, name) in enumerate(bells):
        s.note('lead', 'bell', s.bar(b) + beat, 6, m(name), 0.26 if i % 3 else 0.34, pan=-0.6 + (i * 0.37) % 1.2)
    for b in range(24):
        if b % 2 == 1:
            s.note('perc', 'metal', s.bar(b) + 2.5, 4, m('Gb6'), 0.08, pan=0.5)


@track('boss', 'D minor', 120, 32, 41, {'seconds': 2.0, 'mix': 0.22, 'damp': 6000})
def boss(s):
    prog = [('D', 'm'), ('D', 'm'), ('Bb', ''), ('C', ''), ('D', 'm'), ('D', 'm'), ('G', 'm'), ('A', '')]
    ost = [0, 0, 12, 0, 3, 0, 10, 0]
    for b in range(32):
        root, kind = prog[b % 8]
        r = m(root + '2')
        if root in ('Bb', 'C', 'A'):
            r -= 12 if r > m('F2') else 0
        notes = chord(root, kind, 3)
        sec = b // 8
        for i, n in enumerate(notes):
            s.note('pad', 'pad', s.bar(b), 4.0, n + 12, 0.15 if sec != 3 else 0.2, pan=(i - 1) * 0.5)
        for k in range(8):
            iv = ost[k] if kind == 'm' else [0, 0, 12, 0, 4, 0, 7, 0][k]
            s.note('bass', 'saw_bass', s.bar(b) + k * 0.5, 0.45, r + iv, 0.5 if k % 2 == 0 else 0.38)
        # taiko pattern: 1, 2+, 3, and a fill in the 4th bar of each 4
        for beat, v in ((0, 0.8), (1.5, 0.5), (2, 0.65)):
            s.note('perc', 'taiko', s.bar(b) + beat, 1, 0, v)
        for beat in (1, 3):
            s.note('perc', 'clap', s.bar(b) + beat, 1, 0, 0.42, pan=0.1)
        for k in range(8):
            s.note('perc', 'shaker', s.bar(b) + k * 0.5 + 0.25, 1, 0, 0.16 if k % 2 else 0.22, pan=0.4)
        if b % 4 == 3:
            for k, beat in enumerate((3.0, 3.25, 3.5, 3.75)):
                s.note('perc', 'tom', s.bar(b) + beat, 1, 0, 0.42 + 0.06 * k, pan=-0.3 + 0.2 * k)
    theme = [
        [(0, 1.5, 'D4'), (1.5, 0.5, 'E4'), (2, 2, 'F4')],
        [(0, 1, 'A4'), (1, 1, 'G4'), (2, 1, 'F4'), (3, 1, 'E4')],
        [(0, 3, 'D4'), (3, 1, 'F4')],
        [(0, 2, 'E4'), (2, 2, 'G4')],
        [(0, 1.5, 'A4'), (1.5, 0.5, 'Bb4'), (2, 2, 'A4')],
        [(0, 1, 'F4'), (1, 1, 'G4'), (2, 2, 'A4')],
        [(0, 2, 'Bb4'), (2, 1, 'A4'), (3, 1, 'G4')],
        [(0, 3, 'A4'), (3, 1, 'C#5')],
    ]
    s.phrase('lead', 'horn', 8, theme, vel=0.55, pan=-0.1)
    s.phrase('lead', 'horn', 16, theme, octave=1, vel=0.48, pan=0.1)
    s.phrase('lead', 'horn', 16, theme, octave=0, vel=0.3, pan=-0.2)


@track('arena', 'A minor', 112, 32, 53, {'seconds': 1.8, 'mix': 0.2, 'damp': 6500})
def arena(s):
    prog = [('A', 'm'), ('A', 'm'), ('G', ''), ('G', ''), ('F', ''), ('F', ''), ('E', ''), ('E', '7')]
    for b in range(32):
        root, kind = prog[b % 8]
        r = m(root + '1') if root in ('A', 'G') else m(root + '2')
        for k in range(4):
            s.note('bass', 'saw_bass', s.bar(b) + k + 0.0, 0.4, r, 0.5)
            s.note('bass', 'saw_bass', s.bar(b) + k + 0.75, 0.2, r + 12, 0.32)
        notes = chord(root, kind, 4)
        if b % 2 == 0:
            for i, n in enumerate(notes):
                s.note('pad', 'pad', s.bar(b), 8.0, n, 0.11, pan=(i - 1) * 0.5)
        # drums: kick 1 and 3, clap 2 and 4, toms on the and of 4, shakers in sixteenths
        for beat in (0, 2):
            s.note('perc', 'taiko', s.bar(b) + beat, 1, 0, 0.75)
        s.note('perc', 'kick', s.bar(b) + 2.5, 1, 0, 0.5)
        for beat in (1, 3):
            s.note('perc', 'clap', s.bar(b) + beat, 1, 0, 0.5, pan=-0.05)
        for k in range(16):
            s.note('perc', 'shaker', s.bar(b) + k * 0.25, 1, 0, 0.2 if k % 4 == 2 else 0.12, pan=0.35 if k % 2 else -0.35)
        s.note('perc', 'tom', s.bar(b) + 3.5, 1, 0, 0.45, pan=0.3)
        if b % 8 == 7:
            for k, beat in enumerate((2.0, 2.5, 3.0, 3.25)):
                s.note('perc', 'tom', s.bar(b) + beat, 1, 0, 0.5 + 0.05 * k, pan=-0.4 + 0.25 * k)
    calls = [
        [(0, 0.5, 'A4'), (0.5, 0.5, 'C5'), (1, 1, 'E5'), (2, 2, 'D5')],
        [(0, 1, 'C5'), (1, 1, 'B4'), (2, 2, 'A4')],
        [(0, 0.5, 'G4'), (0.5, 0.5, 'B4'), (1, 1, 'D5'), (2, 2, 'C5')],
        [(0, 4, 'B4')],
        [(0, 0.5, 'F4'), (0.5, 0.5, 'A4'), (1, 1, 'C5'), (2, 2, 'A4')],
        [(0, 1, 'C5'), (1, 1, 'D5'), (2, 2, 'C5')],
        [(0, 1.5, 'B4'), (1.5, 0.5, 'C5'), (2, 2, 'D5')],
        [(0, 3, 'E5'), (3, 1, 'G#4')],
    ]
    s.phrase('lead', 'horn', 8, calls, vel=0.5)
    s.phrase('lead', 'horn', 24, calls, vel=0.46, pan=0.15)
    s.phrase('lead', 'horn', 24, calls, octave=-1, vel=0.3, pan=-0.15)


@track('login', 'D minor', 66, 24, 67, {'seconds': 4.2, 'mix': 0.4, 'damp': 4200})
def login(s):
    prog = [('D', 'm'), ('Bb', ''), ('F', ''), ('C', ''), ('D', 'm'), ('G', 'm'), ('Bb', 'maj7'), ('A', 'sus4')]
    for b in range(24):
        root, kind = prog[b % 8]
        notes = chord(root, kind, 3)
        for i, n in enumerate(notes):
            s.note('pad', 'pad', s.bar(b), 4.0, n, 0.17, pan=(i - 1.5) * 0.3)
        if b % 8 == 7:  # the sus4 resolves to A major on beat 3
            s.note('pad', 'pad', s.bar(b) + 2, 2.0, m('C#4'), 0.16, pan=0.2)
        lo = m(root + '2') if m(root + '2') <= m('C3') else m(root + '1')
        s.note('bass', 'sub', s.bar(b), 4.0, lo, 0.5)
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24, notes[2] + 12, notes[1] + 12]
        for k in range(6):
            s.note('lead', 'pluck', s.bar(b) + k * (4 / 6), 1.5, arp[k], 0.22 if k else 0.3, pan=0.3 - 0.12 * k)
        if b % 4 == 0:
            s.note('lead', 'bell', s.bar(b), 6, notes[0] + 24, 0.18, pan=-0.4)
    theme = [
        [(0, 1, 'A4'), (1, 1, 'D5'), (2, 1.5, 'E5'), (3.5, 0.5, 'F5')],
        [(0, 2, 'D5'), (2, 1, 'F4'), (3, 1, 'Bb4')],
        [(0, 1, 'A4'), (1, 1, 'C5'), (2, 1.5, 'F5'), (3.5, 0.5, 'E5')],
        [(0, 1.5, 'E5'), (1.5, 0.5, 'D5'), (2, 2, 'C5')],
        [(0, 1, 'D5'), (1, 1, 'F5'), (2, 1.5, 'A5'), (3.5, 0.5, 'G5')],
        [(0, 2, 'G5'), (2, 1, 'F5'), (3, 1, 'D5')],
        [(0, 1.5, 'D5'), (1.5, 0.5, 'C5'), (2, 2, 'A4')],
        [(0, 4, 'C#5')],
    ]
    s.phrase('lead', 'flute', 8, theme, vel=0.6, pan=0.05)
    s.phrase('lead', 'horn', 16, theme, octave=-1, vel=0.4, pan=-0.1)
    s.phrase('lead', 'flute', 16, theme, vel=0.36, pan=0.15)


# ---------------------------------------------------------------- synthesis (numpy, --build only)
def synth_module():
    import numpy as np

    TABLE = 4096
    tables = {}

    def table(kind, harmonics):
        key = (kind, harmonics)
        if key not in tables:
            x = np.arange(TABLE) / TABLE
            w = np.zeros(TABLE)
            for k in range(1, harmonics + 1):
                if kind == 'saw':
                    w += np.sin(2 * np.pi * k * x) / k
                elif kind == 'tri' and k % 2 == 1:
                    w += ((-1) ** ((k - 1) // 2)) * np.sin(2 * np.pi * k * x) / (k * k)
                elif kind == 'square' and k % 2 == 1:
                    w += np.sin(2 * np.pi * k * x) / k
            tables[key] = w / (np.max(np.abs(w)) or 1.0)
        return tables[key]

    def hz(midi):
        return 440.0 * 2 ** ((midi - 69) / 12.0)

    def osc(kind, freq, n, phase0=0.0, vib=None, limit=9000.0):
        """band-limited wavetable oscillator; freq in Hz (scalar), vib: array of cents or None"""
        f = np.full(n, freq) if vib is None else freq * 2 ** (vib / 1200.0)
        ph = (phase0 + np.cumsum(f) / RATE) % 1.0
        harm = max(1, min(48, int(limit / max(freq, 1.0))))
        w = table(kind, harm)
        idx = ph * TABLE
        i0 = idx.astype(np.int64) % TABLE
        frac = idx - np.floor(idx)
        return w[i0] * (1 - frac) + w[(i0 + 1) % TABLE] * frac

    def adsr(n, a, d, s_lvl, r, hold):
        """n samples: attack a, decay d to s_lvl, sustain until hold (s), release r (s); smooth curves"""
        t = np.arange(n) / RATE
        env = np.where(t < a, (t / max(a, 1e-4)) ** 1.5, 1.0)
        dec = s_lvl + (1 - s_lvl) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))
        env = np.where(t >= a, dec, env)
        rel = np.clip(1 - (t - hold) / max(r, 1e-4), 0, 1) ** 2
        return env * np.where(t > hold, rel, 1.0)

    def filt(x, lo=None, hi=None):
        """zero-phase brick-free mask: smooth lowpass at hi, highpass at lo (Hz)"""
        spec = np.fft.rfft(x)
        f = np.fft.rfftfreq(len(x), 1.0 / RATE)
        g = np.ones_like(f)
        if hi:
            g /= np.sqrt(1 + (f / hi) ** 4)
        if lo:
            g *= 1 - 1 / np.sqrt(1 + (f / lo) ** 4)
        return np.fft.irfft(spec * g, len(x))

    def instrument(inst, midi, dur, vel, rng, kw):
        """mono samples of one note (dur in seconds, the release is added)"""
        f = hz(midi) if midi else 0.0
        if inst in ('warm', 'pad', 'dark'):
            rel = 2.6 if inst != 'dark' else 4.0
            n = int((dur + rel) * RATE)
            cents = {'warm': 5.0, 'pad': 7.0, 'dark': 16.0}[inst]
            kind = 'tri' if inst == 'warm' else 'saw'
            sig = np.zeros(n)
            for j, c in enumerate((-cents, 0.0, cents)):
                sig += osc(kind, f * 2 ** (c / 1200.0), n, phase0=rng.random(), limit=4500.0 if kind == 'saw' else 8000.0)
            if inst == 'warm':
                sig += 0.8 * osc('saw', f, n, rng.random(), limit=1800.0)
            sig *= adsr(n, 1.4 if inst != 'dark' else 3.0, 1.0, 0.85, rel, dur) / 3.0
            return sig
        if inst == 'drone':
            n = int((dur + 3.0) * RATE)
            vib = 6.0 * np.sin(2 * np.pi * 0.11 * np.arange(n) / RATE + rng.random() * 6)
            sig = osc('saw', f, n, rng.random(), vib=vib, limit=1400.0) + 0.6 * osc('saw', f * 1.003, n, rng.random(), limit=1400.0)
            sig += 0.8 * np.sin(2 * np.pi * f * np.arange(n) / RATE)
            return sig * adsr(n, 2.5, 1.0, 1.0, 3.0, dur) / 2.0
        if inst == 'swell':
            n = int((dur + 0.6) * RATE)
            sig = osc('saw', f, n, rng.random(), limit=3000.0) + osc('saw', f * 1.006, n, rng.random(), limit=3000.0)
            t = np.arange(n) / RATE
            env = np.clip(t / dur, 0, 1) ** 3 * np.clip(1 - (t - dur) / 0.6, 0, 1)
            return sig * env / 2.0
        if inst == 'sub':
            n = int((dur + 1.2) * RATE)
            t = np.arange(n) / RATE
            sig = np.sin(2 * np.pi * f * t) + 0.25 * osc('tri', f * 2, n, 0.0)
            return sig * adsr(n, 0.08, 0.8, 0.8, 1.2, dur)
        if inst == 'mute':
            n = int((dur + 0.25) * RATE)
            sig = osc('saw', f, n, rng.random(), limit=900.0) + 0.6 * np.sin(2 * np.pi * f * np.arange(n) / RATE)
            return sig * adsr(n, 0.005, 0.12, 0.0, 0.1, dur) * 0.7
        if inst == 'saw_bass':
            n = int((dur + 0.15) * RATE)
            t = np.arange(n) / RATE
            sig = osc('saw', f, n, 0.0, limit=1600.0) + np.sin(2 * np.pi * f * t) + 0.4 * osc('square', f * 0.5, n, 0.0, limit=600.0)
            return sig * adsr(n, 0.004, 0.18, 0.55, 0.08, dur) * 0.5
        if inst == 'pluck':
            n = int((dur + 1.5) * RATE)
            t = np.arange(n) / RATE
            sig = np.zeros(n)
            for k in range(1, 13):
                if f * k > 12000:
                    break
                sig += np.sin(2 * np.pi * f * k * t + rng.random()) * np.exp(-t * (1.4 + 0.9 * k)) / k ** 1.1
            att = np.clip(t / 0.003, 0, 1)
            return sig * att * 0.8
        if inst == 'bell':
            n = int((dur + 1.0) * RATE)
            t = np.arange(n) / RATE
            sig = np.zeros(n)
            for ratio, amp, dec in ((1.0, 1.0, 0.9), (2.0, 0.5, 1.4), (2.76, 0.4, 2.2), (5.4, 0.25, 3.5), (8.93, 0.12, 5.0)):
                if f * ratio < 14000:
                    sig += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * dec)
            return sig * np.clip(t / 0.002, 0, 1) * 0.5
        if inst in ('flute', 'horn'):
            n = int((dur + 0.35) * RATE)
            t = np.arange(n) / RATE
            depth = np.clip((t - 0.35) / 0.4, 0, 1) * (14.0 if inst == 'flute' else 8.0)
            vib = depth * np.sin(2 * np.pi * (5.2 if inst == 'flute' else 4.6) * t)
            if inst == 'flute':
                sig = osc('tri', f, n, 0.0, vib=vib, limit=6000.0) * 0.6 + np.sin(2 * np.pi * np.cumsum(f * 2 ** (vib / 1200)) / RATE) * 0.6
                breath = filt(rng.standard_normal(n), lo=f, hi=f * 3) * 0.05
                sig = sig + breath
                env = adsr(n, 0.09, 0.3, 0.85, 0.3, dur)
            else:
                # brass: the bright harmonics come in slower than the low ones
                bright = osc('saw', f, n, 0.0, vib=vib, limit=min(5000.0, f * 14))
                dull = osc('saw', f, n, 0.0, vib=vib, limit=f * 3.5)
                mixb = np.clip(t / 0.12, 0, 1) * (0.55 + 0.45 * vel)
                sig = dull * (1 - mixb) + bright * mixb
                env = adsr(n, 0.06, 0.4, 0.8, 0.3, dur)
            return sig * env * 0.6
        # drums (midi is ignored); the noise is seeded per hit
        if inst in ('kick', 'taiko', 'tom', 'frame', 'boom'):
            p = {'kick': (110, 44, 0.35, 0.05), 'taiko': (140, 58, 0.55, 0.25), 'tom': (190, 120, 0.35, 0.12),
                 'frame': (95, 62, 0.45, 0.18), 'boom': (70, 32, 2.6, 0.12)}[inst]
            hi_f, lo_f, dec, noise = p
            n = int((dec * 3 + 0.05) * RATE)
            t = np.arange(n) / RATE
            fr = lo_f + (hi_f - lo_f) * np.exp(-t / 0.045)
            body = np.sin(2 * np.pi * np.cumsum(fr) / RATE) * np.exp(-t / dec)
            hit = filt(rng.standard_normal(n), lo=60, hi=1800 if inst != 'frame' else 900) * np.exp(-t / 0.03) * noise
            return (body + hit) * np.clip(t / 0.001, 0, 1)
        if inst == 'clap':
            n = int(0.5 * RATE)
            t = np.arange(n) / RATE
            env = np.exp(-t / 0.09) + 0.6 * np.exp(-np.abs(t - 0.012) / 0.004) + 0.5 * np.exp(-np.abs(t - 0.024) / 0.004)
            return filt(rng.standard_normal(n), lo=900, hi=5000) * env * 0.55
        if inst == 'shaker':
            n = int(0.18 * RATE)
            t = np.arange(n) / RATE
            env = np.clip(t / 0.012, 0, 1) * np.exp(-t / 0.035)
            return filt(rng.standard_normal(n), lo=5000, hi=11000) * env * 0.5
        if inst == 'metal':
            n = int((dur + 0.5) * RATE)
            t = np.arange(n) / RATE
            sig = np.zeros(n)
            for ratio, amp in ((1.0, 1.0), (1.47, 0.7), (2.09, 0.5), (2.56, 0.4), (3.43, 0.3)):
                sig += amp * np.sin(2 * np.pi * f * ratio * t + rng.random() * 6) * np.exp(-t * (0.8 + ratio * 0.5))
            return sig * np.clip(t / 0.001, 0, 1) * 0.3
        if inst == 'wind':
            n = int((dur + 1.0) * RATE)
            t = np.arange(n) / RATE
            noise = rng.standard_normal(n)
            sig = stft_sweep(noise, lambda u: 500 + 900 * (0.5 - 0.5 * np.cos(2 * np.pi * u)), band=True)
            env = np.sin(np.pi * np.clip(t / (dur + 1.0), 0, 1)) ** 2
            return sig * env * 0.6
        raise ValueError(inst)

    def stft_sweep(x, cutoff, band=False, frame=2048, hop=512, circular=False):
        """time-varying filter by STFT: cutoff(u) in Hz for u = 0..1 over x; circular: x is one loop period"""
        n = len(x)
        if circular:
            ext = np.concatenate([x[-frame:], x, x[:frame]])
        else:
            ext = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
        win = np.hanning(frame + 1)[:-1]
        f = np.fft.rfftfreq(frame, 1.0 / RATE)
        out = np.zeros(len(ext) + frame)
        norm = np.zeros(len(ext) + frame)
        for start in range(0, len(ext) - frame + 1, hop):
            u = ((start + frame / 2 - frame) % n) / n
            fc = cutoff(u)
            spec = np.fft.rfft(ext[start:start + frame] * win)
            if band:
                g = np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / 0.5) ** 2)
            else:
                g = 1 / np.sqrt(1 + (f / fc) ** 4) * (1 + 0.5 * np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / 0.25) ** 2))
            out[start:start + frame] += np.fft.irfft(spec * g, frame) * win
            norm[start:start + frame] += win * win
        out = out[:len(ext)] / np.maximum(norm[:len(ext)], 1e-3)
        return out[frame:frame + n]

    def fast_len(n):
        best = None
        for a in range(0, 40):
            p2 = 2 ** a
            if p2 >= n * 2:
                break
            for b in range(0, 25):
                p3 = p2 * 3 ** b
                if p3 >= n * 2:
                    break
                v = p3
                while v < n:
                    v *= 5
                if best is None or v < best:
                    best = v
        return best

    def reverb_ir(seconds, damp, rng):
        n = int(seconds * RATE)
        t = np.arange(n) / RATE
        irs = []
        for ch in range(2):
            noise = rng.standard_normal(n)
            dark = filt(noise, hi=damp * 0.35) * np.exp(-t / (seconds / 4.2))
            bright = filt(noise, lo=200, hi=damp) * np.exp(-t / (seconds / 7.0))
            ir = dark * 1.4 + bright
            ir *= np.clip(t / 0.02, 0, 1)  # pre-delay softening
            for k in range(6):  # a few early reflections
                d = int((0.011 + 0.017 * k + 0.004 * ch) * RATE)
                ir[d] += (0.5 - 0.06 * k) * (1 if (k + ch) % 2 else -1)
            irs.append(ir / np.sqrt(np.sum(ir * ir)))
        return irs

    def circular_convolve(x, ir):
        n = len(x)
        size = fast_len(n + len(ir))
        y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n + len(ir) - 1]
        out = y[:n].copy()
        tail = y[n:]
        while len(tail):
            k = min(n, len(tail))
            out[:k] += tail[:k]
            tail = tail[k:]
        return out

    def compress(x, threshold_db, ratio, block=512):
        """soft compressor on the stereo sum, periodic (the loop): block peaks smoothed circularly"""
        n = x.shape[1]
        peak = np.max(np.abs(x), axis=0)
        nb = n // block + 1
        pad = np.zeros(nb * block)
        pad[:n] = peak
        pad[n:] = peak[:nb * block - n]
        bp = pad.reshape(nb, block).max(axis=1)
        k = np.exp(-np.arange(8) / 2.5)  # ~ 60 ms release, circular
        sm = np.zeros(nb)
        for i, w in enumerate(k):
            sm = np.maximum(sm, np.roll(bp, i) * w)
        db = 20 * np.log10(np.maximum(sm, 1e-6))
        over = np.maximum(db - threshold_db, 0)
        gain_db = -over * (1 - 1 / ratio)
        g = 10 ** (gain_db / 20)
        g = np.convolve(np.concatenate([g[-4:], g, g[:4]]), np.ones(5) / 5, mode='same')[4:-4]
        pos = (np.arange(n) + 0.5) / block - 0.5
        gs = np.interp(pos, np.arange(nb), g, period=nb)
        return x * gs

    def render(region):
        spec = TRACKS[region]
        sc = Score(spec['bpm'], spec['bars'])
        spec['build'](sc)
        rng = np.random.default_rng(spec['seed'])
        beat_s = 60.0 / sc.bpm
        n = int(round(sc.bars * sc.beats * beat_s * RATE))
        buses = {b: np.zeros((2, n)) for b in ('pad', 'lead', 'perc', 'bass')}
        cache = {}
        for bus, inst, beat, dur, midi, vel, pan, kw in sc.events:
            start = int(round(beat * beat_s * RATE)) % n
            key = (inst, midi, round(dur, 3)) if inst in ('kick', 'taiko', 'tom', 'frame', 'boom', 'clap') else None
            if key and key in cache:
                sig = cache[key]
            else:
                sig = instrument(inst, midi, dur * beat_s, vel, rng, kw)
                if key:
                    cache[key] = sig
            ang = (pan + 1) * np.pi / 4
            gl, gr = np.cos(ang) * vel, np.sin(ang) * vel
            idx = (start + np.arange(len(sig))) % n
            np.add.at(buses[bus][0], idx, sig * gl)
            np.add.at(buses[bus][1], idx, sig * gr)
        # the pad's filter breathes over the whole loop (two slow cycles), the bass is kept clean
        lo, hi = {'town': (900, 3200), 'hunt': (350, 1600), 'dungeon': (300, 1300), 'boss': (700, 2600),
                  'arena': (800, 2600), 'login': (700, 2800)}[region]
        sweep = lambda u: lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * 2 * u))
        for c in range(2):
            buses['pad'][c] = stft_sweep(buses['pad'][c], sweep, circular=True)
            buses['bass'][c] = filt(buses['bass'][c], lo=30)
            buses['perc'][c] = filt(buses['perc'][c], lo=35)
        rv = spec['reverb']
        irs = reverb_ir(rv['seconds'], rv['damp'], np.random.default_rng(spec['seed'] + 1000))
        send = {'pad': 1.0, 'lead': 0.9, 'perc': 0.45, 'bass': 0.15}
        level = {'pad': 1.0, 'lead': 0.9, 'perc': 0.9, 'bass': 0.85}
        dry = sum(buses[b] * level[b] for b in buses)
        wet_in = sum(buses[b] * send[b] for b in buses)
        wet = np.vstack([circular_convolve(wet_in[c], irs[c]) for c in range(2)])
        mix = dry * (1 - rv['mix']) + wet * rv['mix'] * 1.6
        mix -= mix.mean(axis=1, keepdims=True)
        # loudness: RMS to the target, a soft compressor above it, then the peak ceiling
        rms = np.sqrt(np.mean(mix ** 2))
        mix *= 10 ** (TARGET_RMS_DB / 20) / max(rms, 1e-9)
        mix = compress(mix, TARGET_RMS_DB + 9, 3.0)
        rms = np.sqrt(np.mean(mix ** 2))
        mix *= 10 ** (TARGET_RMS_DB / 20) / max(rms, 1e-9)
        peak = np.max(np.abs(mix))
        ceiling = 10 ** (PEAK_DB / 20) * 0.97  # headroom for the encoder's overshoot
        if peak > ceiling:
            mix *= ceiling / peak
        return mix, sc

    return np, render


def build(only=None, wav_dir=None):
    np, render = synth_module()
    os.makedirs(OUT, exist_ok=True)
    old = {r['region']: r for r in read_rows()} if os.path.isfile(CSV) else {}
    rows = []
    rec = recipe()
    for region, spec in TRACKS.items():
        if only and region not in only:
            if region in old:
                rows.append(old[region])
            continue
        mix, sc = render(region)
        pcm = np.round(np.clip(mix, -1, 1) * 32767).astype('<i2').T.copy()
        seam = np.max(np.abs(pcm[0].astype(int) - pcm[-1].astype(int)))
        step = np.percentile(np.abs(np.diff(pcm[:, 0].astype(int))), 99.9)
        name = 'music_' + region
        out = os.path.join(OUT, name + '.ogg')
        with tempfile.TemporaryDirectory() as tmp:
            wav_path = os.path.join(wav_dir or tmp, name + '.wav')
            with wave.open(wav_path, 'wb') as w:
                w.setnchannels(2)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(pcm.tobytes())
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav_path, '-map_metadata', '-1', '-fflags', '+bitexact',
                            '-flags:a', '+bitexact', '-c:a', 'libvorbis', '-q:a', QUALITY, out], check=True)
        rms_db = 20 * np.log10(np.sqrt(np.mean(mix ** 2)))
        peak_db = 20 * np.log10(np.max(np.abs(mix)))
        secs = len(pcm) / RATE
        data = open(out, 'rb').read()
        print('%-8s %6.2f s  rms %.1f dB  peak %.1f dB  seam step %d (99.9%% step %d)  %d bytes'
              % (region, secs, rms_db, peak_db, seam, step, len(data)))
        rows.append({'file': name, 'region': region, 'key': spec['key'], 'bpm': spec['bpm'], 'bars': spec['bars'],
                     'seconds': '%.3f' % secs, 'rms_db': '%.1f' % rms_db, 'peak_db': '%.1f' % peak_db, 'recipe': rec,
                     'sha256': hashlib.sha256(data).hexdigest()})
    with open(CSV, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
    return check()


def main(argv):
    if '--check' in argv:
        return check()
    if '--build' in argv:
        only = argv[argv.index('--only') + 1].split(',') if '--only' in argv else None
        wav_dir = argv[argv.index('--wav') + 1] if '--wav' in argv else None
        return build(only, wav_dir)
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
