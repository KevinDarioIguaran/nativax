#!/usr/bin/env python3
"""Run the native test suite inside a Docker container."""
import subprocess
import sys

IMAGE = "nativax-native-lab"

def main() -> int:
    cmd = [
        "docker", "run", "--rm",
        "--cpus=1", "--memory=512m",
        IMAGE,
        "ctest", "--test-dir", "/src/build", "--output-on-failure",
    ]
    return subprocess.run(cmd).returncode

if __name__ == "__main__":
    raise SystemExit(main())