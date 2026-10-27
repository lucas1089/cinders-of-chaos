"""Runs gen/generate.py without the render step (for md5 checks): python -B run.py tools/gen_norender.py <generate args>"""
import subprocess, sys, runpy
from pathlib import Path
real = subprocess.run
subprocess.run = lambda *a, **k: None
sys.argv = ["generate.py", *sys.argv[1:]]
sys.path[:0] = ["gen"]
runpy.run_path("gen/generate.py", run_name="__main__")
