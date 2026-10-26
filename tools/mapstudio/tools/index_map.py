"""Reads the reference map once into cache/map/ so every tool can read windows of it quickly.

python -B run.py tools/index_map.py [--map <other map file>]
Run it again whenever the map file changes. A large map (200+ MB) takes several minutes and needs a few GB of
memory while it runs.
"""
from __future__ import annotations

import argparse

from common import adapter


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--map", help="default: config.json's map")
    a = p.parse_args()
    adapter().index(a.map)


if __name__ == "__main__":
    main()
