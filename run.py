#!/usr/bin/env python3
"""Convenience entry point: delegates to debug/run.py."""
from __future__ import annotations
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.argv[0] = str(ROOT / "debug" / "run.py")
runpy.run_path(str(ROOT / "debug" / "run.py"), run_name="__main__")
