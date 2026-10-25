#!/usr/bin/env python3
"""Runs the 25 video contract tests and records the result in the manifest."""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / "video_profiles.json"


def main() -> int:
    manifest = json.loads(MANIFEST.read_text())
    result = subprocess.run(
        ["flutter", "test", "test/video_quality_test.dart"],
        cwd=ROOT / "packages" / "nativa_render",
        text=True,
    )
    manifest["last_run"] = {
        "status": "PASS" if result.returncode == 0 else "FAIL",
        "tests": len(manifest.get("profiles", [])),
        "date": datetime.now().isoformat(timespec="seconds"),
        "command": "cd packages/nativa_render && flutter test test/video_quality_test.dart",
        "exit_code": result.returncode,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"video contract: {manifest['last_run']['status']}")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
