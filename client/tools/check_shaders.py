#!/usr/bin/env python3
"""Compile check of the Cinders of Chaos GLSL (client/MANIFEST.md "game_shaderfx", client/BASE.md patch 0044).

Checks
- every client/overlay/data/shaders/chaos_*.frag (a file named *_vertex.frag is a vertex stage, the rest fragment
  stages; chaos_ui_* pair with chaos_ui_vertex.frag, chaos_outfit_* with chaos_outfit_vertex.frag, chaos_map_* with
  chaos_map_vertex.frag, chaos_liquid_* with chaos_liquid_vertex.frag, chaos_bloom_* with chaos_bloom_vertex.frag),
- the programs written inside base patches as C++ strings (const std::string glsl...Shader = "...";, the creature
  outline of 0038 and the item outline of 0044), taken from the added lines of the patch.

With glslangValidator (on PATH, or --glslang PATH) each stage is compiled twice, the way the client hands it to the
driver: desktop GLSL 1.10 (no #version in the file, so 1.10) and OpenGL ES GLSL 1.00 with the
"precision highp float;" line the client puts in front on GLES / ANGLE (framework/graphics/shader.cpp). Without it a
smoke test runs instead (a main(), balanced brackets, no #version, nothing of GLSL 1.30+). Both also check that every
varying a fragment stage reads is written by its vertex stage.

Usage: python3 -I client/tools/check_shaders.py [--glslang PATH] [--require-glslang]
Exit 0 when everything passes.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.dirname(HERE)
SHADERS = os.path.join(CLIENT, 'overlay', 'data', 'shaders')
PATCHES = os.path.join(CLIENT, 'base-patches')
# base patches whose added lines hold GLSL programs as C++ strings
EMBEDDED = ['0038-outfit-silhouette-outline.patch', '0044-item-rarity-outline-ui-shaders.patch']

NEWER_GLSL = re.compile(r'\b(texture|in|out|layout|uniform\s+\w+\s*\{|flat|smooth|noperspective)\s*\(|'
                        r'^\s*(in|out)\s+\w+\s+\w+\s*;', re.M)


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return re.sub(r'//[^\n]*', '', src)


def varyings(src):
    return set(re.findall(r'^\s*varying\s+\w+\s+(\w+)\s*;', strip_comments(src), re.M))


def smoke(name, src):
    """problems of a stage found without a compiler"""
    out = []
    code = strip_comments(src)
    if '#version' in code:
        out.append('%s: no #version (the client compiles it as 1.10 / ES 1.00)' % name)
    if not re.search(r'\bvoid\s+main\s*\(\s*\)', code):
        out.append('%s: no void main()' % name)
    for a, b in ('()', '{}', '[]'):
        if code.count(a) != code.count(b):
            out.append('%s: unbalanced %s%s' % (name, a, b))
    if NEWER_GLSL.search(code):
        out.append('%s: GLSL 1.30+ syntax (texture(), in / out); use texture2D, attribute and varying' % name)
    if re.search(r'\bpow\s*\(\s*\(?\s*-', code):
        out.append('%s: pow() of a negative base is undefined' % name)
    return out


def embedded_programs(patch_path):
    """[(name, stage, source)] of the C++ string programs added by a patch"""
    if not os.path.exists(patch_path):
        return []
    added = [l[1:] for l in open(patch_path, encoding='utf-8').read().split('\n') if l.startswith('+') and not l.startswith('+++')]
    text = '\n'.join(added)
    out = []
    for m in re.finditer(r'const std::string (glsl\w*?(Vertex|Fragment)Shader) = "(.*?)";', text, re.S):
        body = m.group(3)
        lines = []
        for line in body.split('\n'):
            line = line.rstrip()
            if line.endswith('\\'):
                line = line[:-1]
            lines.append(line.replace('\\n', '').replace('\\"', '"').replace('\\\\', '\\'))
        out.append((os.path.basename(patch_path) + ':' + m.group(1), 'vert' if m.group(2) == 'Vertex' else 'frag',
                    '\n'.join(lines) + '\n'))
    return out


def file_stages():
    """[(name, stage, source, vertex name or None)]"""
    out = []
    if not os.path.isdir(SHADERS):
        return out
    for fn in sorted(os.listdir(SHADERS)):
        if not (fn.startswith('chaos_') and fn.endswith('.frag')):
            continue
        src = open(os.path.join(SHADERS, fn), encoding='utf-8').read()
        if fn.endswith('_vertex.frag'):
            out.append((fn, 'vert', src, None))
        else:
            prefix = ('chaos_ui_' if fn.startswith('chaos_ui_') else 'chaos_outfit_' if fn.startswith('chaos_outfit_')
                      else 'chaos_map_' if fn.startswith('chaos_map_')
                      else 'chaos_liquid_' if fn.startswith('chaos_liquid_')
                      else 'chaos_bloom_' if fn.startswith('chaos_bloom_') else None)
            out.append((fn, 'frag', src, (prefix + 'vertex.frag') if prefix else None))
    return out


def compile_with(glslang, name, stage, src):
    problems = []
    variants = [('desktop GLSL 1.10', '#version 110\n'), ('GLSL ES 1.00', '#version 100\nprecision highp float;\n')]
    with tempfile.TemporaryDirectory() as d:
        for label, header in variants:
            path = os.path.join(d, 'shader.' + stage)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(header + src)
            r = subprocess.run([glslang, path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
            if r.returncode != 0:
                msg = ' | '.join(l.strip() for l in r.stdout.splitlines() if 'ERROR' in l)[:600]
                problems.append('%s (%s): %s' % (name, label, msg or r.stdout.strip()[:600]))
    return problems


def main(argv):
    glslang = None
    require = '--require-glslang' in argv
    if '--glslang' in argv:
        glslang = argv[argv.index('--glslang') + 1]
    else:
        glslang = shutil.which('glslangValidator')
    stages = file_stages()
    sources = {name: src for name, _, src, _ in stages}
    for p in EMBEDDED:
        for name, stage, src in embedded_programs(os.path.join(PATCHES, p)):
            stages.append((name, stage, src, name.replace('Fragment', 'Vertex') if stage == 'frag' else None))
            sources[name] = src
    if not stages:
        print('check_shaders: no shaders found')
        return 1
    problems = []
    for name, stage, src, vert in stages:
        problems += smoke(name, src)
        if glslang:
            problems += compile_with(glslang, name, stage, src)
        if vert:
            if vert not in sources:
                problems.append('%s: its vertex stage %s is missing' % (name, vert))
            else:
                missing = varyings(src) - varyings(sources[vert])
                if missing:
                    problems.append('%s: varying(s) %s not written by %s' % (name, ', '.join(sorted(missing)), vert))
    if not glslang:
        if require:
            problems.append('glslangValidator not found (--require-glslang)')
        else:
            print('check_shaders: glslangValidator not found, smoke test only')
    for p in problems:
        print('FAIL ' + p)
    print('check_shaders: %d stage(s), %s, %d problem(s)' % (len(stages), 'compiled (desktop 1.10 and ES 1.00)' if glslang else 'smoke test', len(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
