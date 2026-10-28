#!/usr/bin/env python3
"""Collect machine/environment info for the debug matrix."""
import json, platform, subprocess, os
from pathlib import Path

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return None

info = {
    "os": platform.platform(),
    "machine": platform.machine(),
    "processor": platform.processor(),
    "python": platform.python_version(),
    "cpu_count": os.cpu_count(),
    "memory_kb": None,
}
# RAM
try:
    mem = Path("/proc/meminfo").read_text()
    for line in mem.splitlines():
        if line.startswith("MemTotal:"):
            info["memory_kb"] = int(line.split()[1])
except Exception:
    pass
# GPU
info["gpu"] = run(["lspci"]) 
# filter VGA
if info["gpu"]:
    lines = [l for l in info["gpu"].splitlines() if "VGA" in l or "3D" in l or "Display" in l]
    info["gpu"] = "; ".join(lines) if lines else info["gpu"][:200]
# compiler
info["compiler"] = run(["gcc", "--version"])
if info["compiler"]:
    info["compiler"] = info["compiler"].splitlines()[0]
# git commit
info["git_commit"] = run(["git", "rev-parse", "HEAD"])
info["git_branch"] = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])

print(json.dumps(info, indent=2))
