#!/usr/bin/env python3
"""NativaX laboratory bootstrap: install everything the debug lab needs.

The lab must be runnable on a clean machine with a single command:

    python3 debug/bootstrap.py

What it does (idempotent, safe to re-run):

  1. Detects OS/architecture and the available package manager.
  2. Installs system build + runtime dependencies (compiler, CMake, Ninja,
     pkg-config, JavaScriptCoreGTK, GL/X11 headers, Xvfb, fonts).
  3. Creates ``debug/.venv`` and installs Python dependencies (Pillow,
     Playwright). Browser engines are optional; ``--with-browsers`` pulls
     Chromium for cross-browser reference comparisons.
  4. Configures and builds the native runtime into ``build/``.
  5. Verifies the toolchain by running a headless smoke test.
  6. Writes ``debug/lab/env.json`` with the detected versions.

Exit codes: 0 ready, 1 missing prerequisite that could not be installed,
2 build failure, 3 verification failure.

No network access is required after the one-time install; every lab run
afterwards is offline.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import sysconfig
import venv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEBUG = ROOT / "debug"
VENV = DEBUG / ".venv"
ENV_JSON = DEBUG / "lab" / "env.json"

# Debian/Ubuntu package names. Other distros map below.
APT_PACKAGES = [
    "build-essential",
    "cmake",
    "ninja-build",
    "pkg-config",
    "libjavascriptcoregtk-4.1-dev",
    "libgl1-mesa-dev",
    "libxcursor-dev",
    "libxi-dev",
    "xvfb",
    "fonts-dejavu-core",
    "python3",
    "python3-venv",
    "python3-pip",
    "python3-gi",
    "gir1.2-gtk-3.0",
    "gir1.2-webkit2-4.1",
    "file",
]
DNF_PACKAGES = [
    "gcc", "gcc-c++", "make", "cmake", "ninja-build", "pkgconf-pkg-config",
    "javascriptcoregtk4.1-devel", "mesa-libGL-devel", "libXcursor-devel",
    "libXi-devel", "xorg-x11-server-Xvfb", "dejavu-sans-fonts", "python3",
    "python3-pip", "python3-virtualenv", "python3-gobject",
    "webkit2gtk4.1", "file",
]
PACMAN_PACKAGES = [
    "base-devel", "cmake", "ninja", "pkgconf", "javascriptcoregtk-4.1",
    "mesa", "libxcursor", "libxi", "xorg-server-xvfb", "ttf-dejavu",
    "python", "python-pip", "python-gobject", "webkit2gtk-4.1", "file",
]
BREW_PACKAGES = [
    "cmake", "ninja", "pkg-config", "webkitgtk", "python", "pillow",
]

PIP_PACKAGES = ["pillow>=10.0", "pywebview>=5.0"]


def log(msg: str) -> None:
    print(f"[bootstrap] {msg}", flush=True)


def run(cmd: list[str], *, check: bool = False, sudo: bool = False,
        stdout=None) -> subprocess.CompletedProcess:
    if sudo and os.geteuid() != 0:
        cmd = ["sudo", *cmd]
    log("$ " + " ".join(cmd))
    return subprocess.run(cmd, check=check, stdout=stdout)


def which(name: str) -> str | None:
    return shutil.which(name)


def is_root() -> bool:
    return hasattr(os, "geteuid") and os.geteuid() == 0


def can_sudo() -> bool:
    if is_root():
        return True
    if not which("sudo"):
        return False
    probe = subprocess.run(["sudo", "-n", "true"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
    return probe.returncode == 0


def apt_install(packages: list[str]) -> bool:
    if not can_sudo():
        log("ERROR: apt needs root or passwordless sudo; run as root or install "
            "manually: " + " ".join(packages))
        return False
    env = dict(os.environ, DEBIAN_FRONTEND="noninteractive")
    log("$ apt-get update")
    subprocess.run(["sudo", "apt-get", "update", "-qq"], env=env)
    r = subprocess.run(["sudo", "apt-get", "install", "-y", "-qq", *packages],
                       env=env)
    return r.returncode == 0


def install_system_deps(with_browsers: bool) -> bool:
    system = platform.system()
    if system == "Linux":
        if which("apt-get"):
            if not apt_install(APT_PACKAGES):
                return False
        elif which("dnf"):
            if not can_sudo():
                return False
            subprocess.run(["sudo", "dnf", "install", "-y", *DNF_PACKAGES])
        elif which("pacman"):
            if not can_sudo():
                return False
            subprocess.run(["sudo", "pacman", "-Sy", "--needed", "--noconfirm",
                            *PACMAN_PACKAGES])
        else:
            log("ERROR: no supported package manager (apt/dnf/pacman)")
            return False
    elif system == "Darwin":
        if not which("brew"):
            log("ERROR: Homebrew is required on macOS: https://brew.sh")
            return False
        subprocess.run(["brew", "install", *BREW_PACKAGES])
    else:
        log(f"ERROR: unsupported OS {system}; install dependencies manually")
        return False
    return True


def ensure_venv() -> Path:
    if not VENV.exists():
        log(f"creating virtualenv {VENV}")
        venv.EnvBuilder(with_pip=True, clear=False).create(VENV)
    py = VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not py.exists():
        raise SystemExit(f"bootstrap: venv python missing at {py}")
    return py


def pip_install(py: Path, packages: list[str]) -> bool:
    r = subprocess.run([str(py), "-m", "pip", "install", "--upgrade", "pip"],
                       stdout=subprocess.DEVNULL)
    if r.returncode != 0:
        log("warning: pip self-upgrade failed; continuing")
    return subprocess.run([str(py), "-m", "pip", "install", *packages]).returncode == 0


def ensure_python_deps(with_browsers: bool) -> bool:
    py = ensure_venv()
    if not pip_install(py, PIP_PACKAGES):
        return False
    if with_browsers:
        if not pip_install(py, ["playwright>=1.40"]):
            return False
        r = subprocess.run([str(py), "-m", "playwright", "install", "chromium"])
        if r.returncode != 0:
            log("warning: Chromium download failed; browser comparisons will "
                "report blocked instead of failing")
    return True


def cmake_flags() -> list[str]:
    return ["-DCMAKE_BUILD_TYPE=RelWithDebInfo"]


def build_project() -> bool:
    build = ROOT / "build"
    gen = "Ninja" if which("ninja") else "Unix Makefiles"
    log(f"configuring {build} with {gen}")
    r = subprocess.run(["cmake", "-S", str(ROOT), "-B", str(build), "-G", gen,
                        *cmake_flags()])
    if r.returncode != 0:
        return False
    r = subprocess.run(["cmake", "--build", str(build), "-j",
                        str(max(1, (os.cpu_count() or 2)))])
    return r.returncode == 0


def pack_version(cmd: list[str]) -> str | None:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return (out.stdout or out.stderr).strip().splitlines()[0]
    except Exception:
        return None


def smoke_verify() -> bool:
    exe = ROOT / "build" / "nativax-debug"
    if not exe.exists():
        log(f"ERROR: {exe} was not produced")
        return False
    work = DEBUG / "artifacts" / "bootstrap-smoke"
    work.mkdir(parents=True, exist_ok=True)
    case = work / "case.html"
    case.write_text("<!doctype html><html><body><div id=x>ok</div></body></html>")
    r = subprocess.run([str(exe), "--html", str(case), "--out", str(work),
                        "--width", "320", "--height", "240"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        log("ERROR: headless smoke test failed:\n" + r.stderr[-2000:])
        return False
    dom = json.loads((work / "dom.json").read_text())
    def find(node):
        if node.get("id") == "x":
            return node
        for c in node.get("children", []):
            got = find(c)
            if got:
                return got
        return None
    if not find(dom):
        log("ERROR: smoke DOM dump did not contain #x")
        return False
    log("headless pipeline OK")
    return True


def collect_env(py: Path | None) -> dict:
    info = {
        "os": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python": sys.version.split()[0],
        "cpus": os.cpu_count(),
        "tools": {},
        "packages": {},
    }
    for tool, cmd in {
        "cc": ["cc", "--version"],
        "cmake": ["cmake", "--version"],
        "ninja": ["ninja", "--version"],
        "pkg-config": ["pkg-config", "--version"],
        "xvfb": ["Xvfb", "-help"],
        "git": ["git", "--version"],
    }.items():
        if which(cmd[0]):
            info["tools"][tool] = pack_version(cmd)
    for pkg in ("javascriptcoregtk-4.1", "gl", "xcursor", "xi", "x11"):
        r = subprocess.run(["pkg-config", "--modversion", pkg],
                           capture_output=True, text=True)
        info["packages"][pkg] = r.stdout.strip() if r.returncode == 0 else None
    if py:
        r = subprocess.run([str(py), "-c", "import PIL; print(PIL.__version__)"],
                           capture_output=True, text=True)
        info["packages"]["pillow"] = r.stdout.strip() if r.returncode == 0 else None
        r = subprocess.run([str(py), "-c", "import playwright; print('ok')"],
                           capture_output=True, text=True)
        info["packages"]["playwright"] = r.stdout.strip() if r.returncode == 0 else None
    return info


def check_only(py: Path | None) -> int:
    missing = []
    for tool in ("cc", "cmake", "ninja", "pkg-config"):
        if not which(tool):
            missing.append(tool)
    for pkg in ("javascriptcoregtk-4.1", "gl", "xcursor", "xi"):
        r = subprocess.run(["pkg-config", "--exists", pkg])
        if r.returncode != 0:
            missing.append(f"pkg:{pkg}")
    if py is None or not py.exists():
        missing.append("venv")
    if not (ROOT / "build" / "nativax-debug").exists():
        missing.append("build/nativax-debug")
    info = collect_env(py)
    print(json.dumps({"ready": not missing, "missing": missing, "env": info},
                     indent=2))
    return 0 if not missing else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="report readiness without installing anything")
    ap.add_argument("--with-browsers", action="store_true",
                    help="install Playwright + Chromium for reference comparisons")
    ap.add_argument("--skip-system", action="store_true",
                    help="do not touch system packages")
    ap.add_argument("--skip-build", action="store_true", help="do not build")
    ap.add_argument("--no-verify", action="store_true", help="skip smoke test")
    args = ap.parse_args()

    py = VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if args.check:
        return check_only(py if py.exists() else None)

    log(f"platform {platform.system()} {platform.machine()}, python {sys.version.split()[0]}")
    if not args.skip_system and not install_system_deps(args.with_browsers):
        return 1
    if not ensure_python_deps(args.with_browsers):
        return 1
    if not args.skip_build and not build_project():
        return 2
    if not args.no_verify and not smoke_verify():
        return 3
    ENV_JSON.parent.mkdir(parents=True, exist_ok=True)
    ENV_JSON.write_text(json.dumps(collect_env(py), indent=2) + "\n")
    log(f"wrote {ENV_JSON.relative_to(ROOT)}")
    log("laboratory ready: python3 debug/lab/run_lab.py --all")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
