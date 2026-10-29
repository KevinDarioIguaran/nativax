#!/usr/bin/env python3
"""Chrome vs NativaX pixel comparison for real laboratory cases.

For every selected case the script renders the *same* entry document twice:

* Chrome (Playwright Chromium, headless shell) at 1x device scale factor.
* NativaX (``build/nativax-runtime --headless --deterministic``).

Both captures are then compared pixel by pixel.  The artifacts and a JSON
report are written so the dashboard can show Chrome, NativaX and the diff
image side by side.

Examples::

    python3 debug/judges/visual/chrome_compare.py --case css.001
    python3 debug/judges/visual/chrome_compare.py --section 1 --widths 320,768,1024
    python3 debug/judges/visual/chrome_compare.py --all --limit 10

The comparison is a *design audit*, not a pass/fail oracle: NativaX implements
a documented subset of CSS, so a large diff can be an expected gap.  The
status (pass/warn/fail) is derived from measurable thresholds and every number
comes from the two real screenshots.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
DEBUG = HERE.parents[1]
ROOT = DEBUG.parent
LAB = DEBUG / "lab"
for path in (str(DEBUG), str(LAB)):
    if path not in sys.path:
        sys.path.insert(0, path)

import harness  # noqa: E402

DEFAULT_OUT = DEBUG / "artifacts" / "visual"
DEFAULT_REPORT = DEBUG / "reports" / "visual" / "latest.json"

# Chrome and NativaX render text with different rasterizers; a few anti-aliased
# pixels are unavoidable.  The defaults are intentionally conservative.
DEFAULT_TOLERANCE = 4           # per-channel delta ignored as anti-aliasing
DEFAULT_MAX_CHANGED = 2.0       # % of pixels that may differ for a "pass"
DEFAULT_WARN_CHANGED = 8.0      # % above which the comparison is a "fail"
DEFAULT_MAX_MAE = 6.0           # mean absolute error (0..255)
DEFAULT_MIN_SSIM = 0.90         # structural similarity


def _require_deps():
    missing = []
    try:
        import numpy  # noqa: F401
    except Exception:
        missing.append("numpy")
    try:
        from playwright.sync_api import sync_playwright  # noqa: F401
    except Exception:
        missing.append("playwright")
    try:
        from PIL import Image  # noqa: F401
    except Exception:
        missing.append("pillow")
    if missing:
        raise SystemExit(
            "missing visual dependencies: " + ", ".join(missing) +
            "\nInstall them with: python3 debug/bootstrap.py --with-browsers")


def self_check() -> int:
    """Verify dependencies and that Chromium can actually be launched."""
    _require_deps()
    import tempfile

    from PIL import Image
    from playwright.sync_api import sync_playwright

    with tempfile.TemporaryDirectory() as td:
        shot = Path(td) / "self-check.png"
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 32, "height": 32},
                                    device_scale_factor=1)
            page.set_content(
                "<body style='margin:0;background:#123456'>"
                "<div style='width:32px;height:32px;background:#abcdef'></div>"
                "</body>")
            page.screenshot(path=str(shot))
            browser.close()
        pixel = Image.open(shot).convert("RGB").getpixel((16, 16))
        if pixel != (0xAB, 0xCD, 0xEF):
            print(f"self-check failed: unexpected pixel {pixel}", file=sys.stderr)
            return 1
    print("visual comparison self-check: OK (numpy, pillow, playwright, chromium)")
    return 0


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def _url(path: Path) -> str:
    return path.resolve().as_uri()


def render_chrome(case_dir: Path, entry: str, width: int, height: int,
                  out: Path, *, frames: int = 8, freeze_animations: bool = True,
                  allow_remote: bool = False, timeout_ms: int = 45000) -> dict:
    """Render the entry document with headless Chromium."""
    from playwright.sync_api import sync_playwright

    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)  # never compare a stale capture
    info: dict[str, Any] = {
        "width": width, "height": height, "entry": entry, "ok": False,
        "blocked_requests": [], "console_errors": [], "page_errors": [],
    }
    with sync_playwright() as p:
        browser = p.chromium.launch(args=[
            "--allow-file-access-from-files",
            "--disable-web-security",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--font-render-hinting=none",
        ])
        context = browser.new_context(
            viewport={"width": width, "height": height},
            device_scale_factor=1,
            locale="en-US",
            timezone_id="UTC",
        )
        page = context.new_page()

        def route(r):
            url = r.request.url
            if not allow_remote and (url.startswith("http://") or
                                     url.startswith("https://")):
                info["blocked_requests"].append(url)
                r.abort()
            else:
                r.continue_()

        page.route("**/*", route)
        page.on("console", lambda msg: info["console_errors"].append(msg.text)
                if msg.type == "error" else None)
        page.on("pageerror", lambda exc: info["page_errors"].append(str(exc)))

        uri = (case_dir / entry).resolve().as_uri()
        page.goto(uri, wait_until="domcontentloaded", timeout=timeout_ms)
        try:
            page.wait_for_load_state("load", timeout=10000)
        except Exception:
            pass  # slow/remote assets: compare what the page produced
        page.wait_for_timeout(350)
        try:  # webfonts must be settled or text metrics drift between runs
            page.evaluate("() => (document.fonts ? document.fonts.ready : true)")
        except Exception:
            pass
        if freeze_animations:
            page.add_style_tag(content=(
                "*,*::before,*::after{"
                "animation:none!important;transition:none!important;"
                "caret-color:transparent!important}"))
            page.wait_for_timeout(50)
        page.screenshot(path=str(out), full_page=False,
                        animations="disabled" if freeze_animations else "allow")
        info["title"] = page.title()
        info["ok"] = out.exists()
        context.close()
        browser.close()
    info["path"] = _rel(out)
    info["url"] = _url(out)
    return info


def render_nativax(lab: harness.Lab, case_dir: Path, entry: str, width: int,
                   height: int, out: Path, *, frames: int = 8,
                   timeout: float = 90.0) -> dict:
    """Render the entry document with the real NativaX runtime."""
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)  # never compare a stale capture
    args = [
        str(lab.runtime_bin), "--headless", "--deterministic",
        "--root", str(case_dir), "--entry", entry,
        "--frames", str(frames), "--size", str(width), str(height),
        "--screenshot", str(out),
    ]
    started = time.time()
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        rc, stdout, stderr = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired as exc:
        rc = -9
        stdout = (exc.stdout or "")
        stderr = (exc.stderr or "") + f"\ntimeout after {timeout:.0f}s"
    return {
        "width": width, "height": height, "entry": entry,
        "returncode": rc,
        "seconds": round(time.time() - started, 3),
        "stdout": stdout[-3000:], "stderr": stderr[-3000:],
        "ok": rc == 0 and out.exists(),
        "path": _rel(out), "url": _url(out) if out.exists() else None,
    }


def _box_filter(channel, radius: int):
    import numpy as np
    pad = radius
    padded = np.pad(channel, ((pad, pad), (pad, pad)), mode="edge")
    integral = padded.cumsum(0).cumsum(1)
    integral = np.pad(integral, ((1, 0), (1, 0)), mode="constant")
    size = 2 * radius + 1
    total = (integral[size:, size:] - integral[:-size, size:]
             - integral[size:, :-size] + integral[:-size, :-size])
    return total / float(size * size)


def _ssim(ref_img, actual_img) -> float:
    """Global SSIM on downscaled luminance (no scipy dependency)."""
    import numpy as np
    from PIL import Image

    # Downscale to keep the measurement fast and insensitive to single pixels.
    w = min(512, ref_img.width)
    h = max(1, int(round(ref_img.height * (w / max(1, ref_img.width)))))
    a = np.asarray(ref_img.convert("L").resize((w, h), Image.Resampling.BILINEAR),
                   dtype=np.float64)
    b = np.asarray(actual_img.convert("L").resize((w, h), Image.Resampling.BILINEAR),
                   dtype=np.float64)
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    mu_a = _box_filter(a, 3)
    mu_b = _box_filter(b, 3)
    va = _box_filter(a * a, 3) - mu_a * mu_a
    vb = _box_filter(b * b, 3) - mu_b * mu_b
    cov = _box_filter(a * b, 3) - mu_a * mu_b
    num = (2 * mu_a * mu_b + c1) * (2 * cov + c2)
    den = (mu_a * mu_a + mu_b * mu_b + c1) * (va + vb + c2)
    return float(np.mean(num / den))


def compare_images(ref_path: Path, actual_path: Path, diff_path: Path,
                   *, tolerance: int = DEFAULT_TOLERANCE) -> dict:
    """Compare two PNGs and write a red-on-grey difference image."""
    import numpy as np
    from PIL import Image, ImageDraw

    ref = Image.open(ref_path).convert("RGBA")
    actual = Image.open(actual_path).convert("RGBA")
    size_mismatch = ref.size != actual.size
    if size_mismatch:
        w = min(ref.size[0], actual.size[0])
        h = min(ref.size[1], actual.size[1])
        ref = ref.crop((0, 0, w, h))
        actual = actual.crop((0, 0, w, h))

    a = np.asarray(ref, dtype=np.int16)
    b = np.asarray(actual, dtype=np.int16)
    delta = np.abs(a - b)
    max_delta = delta.max(axis=2)
    changed = max_delta > tolerance
    changed_pixels = int(changed.sum())
    total = int(changed.size)
    pct = (100.0 * changed_pixels / total) if total else 0.0

    # Metrics on RGB only (alpha is opaque in both captures).
    rgb_delta = delta[:, :, :3].astype(np.float64)
    mae = float(rgb_delta.mean()) if rgb_delta.size else 0.0
    rmse = float(math.sqrt(float((rgb_delta ** 2).mean()))) if rgb_delta.size else 0.0

    bbox = None
    ys, xs = np.where(changed)
    if len(xs):
        bbox = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]

    # Diff image: faded reference with changed pixels painted red.
    grey = ref.convert("RGB").point(lambda v: int(v * 0.30))
    out = np.asarray(grey).copy()
    out[changed] = (255, 32, 32)
    diff = Image.fromarray(out, mode="RGB")
    draw = ImageDraw.Draw(diff)
    if bbox:
        draw.rectangle(bbox, outline=(255, 220, 0), width=2)
    diff_path.parent.mkdir(parents=True, exist_ok=True)
    diff.save(diff_path)

    return {
        "width": ref.width,
        "height": ref.height,
        "size_mismatch": size_mismatch,
        "changed_pixels": changed_pixels,
        "total_pixels": total,
        "changed_percent": round(pct, 4),
        "max_channel_delta": int(max_delta.max()) if max_delta.size else 0,
        "mae": round(mae, 4),
        "rmse": round(rmse, 4),
        "ssim": round(_ssim(ref, actual), 5),
        "bbox": bbox,
        "tolerance": tolerance,
        "diff": _rel(diff_path),
        "diff_url": _url(diff_path),
    }


def classify(metrics: dict, *, max_changed: float, warn_changed: float,
             max_mae: float, min_ssim: float) -> str:
    if metrics["size_mismatch"]:
        return "fail"
    if (metrics["changed_percent"] <= max_changed and
            metrics["mae"] <= max_mae and metrics["ssim"] >= min_ssim):
        return "pass"
    if metrics["changed_percent"] <= warn_changed:
        return "warn"
    return "fail"


def select_cases(lab: harness.Lab, *, cases: list[str], sections: list[int],
                 all_cases: bool, limit: int) -> list[harness.Case]:
    if cases:
        wanted = set(cases)
        found = [c for c in harness.registered() if c.cid in wanted]
        missing = wanted - {c.cid for c in found}
        if missing:
            raise SystemExit("unknown case id(s): " + ", ".join(sorted(missing)))
        return found
    if all_cases:
        found = list(harness.registered())
    else:
        found = [c for c in harness.registered() if c.section in set(sections)]
    if not found:
        raise SystemExit("no cases selected")
    return found[:limit] if limit > 0 else found


def run(args) -> int:
    _require_deps()
    harness.load_sections()
    lab = harness.Lab(responsive=False)
    widths = [int(w) for w in args.widths.split(",") if w.strip()]
    out_root = Path(args.out)
    out_root.mkdir(parents=True, exist_ok=True)

    chosen = select_cases(lab, cases=args.case, sections=args.section,
                          all_cases=args.all, limit=args.limit)
    started = time.time()
    report_path = Path(args.report)

    # Keep the last comparison for every case. Running one case must not erase
    # the other cases from the dashboard; --fresh starts a clean report.
    previous: dict[str, Any] = {}
    if not args.fresh and report_path.exists():
        try:
            payload = json.loads(report_path.read_text())
            if isinstance(payload.get("cases"), dict):
                previous = payload["cases"]
        except Exception:
            previous = {}

    report: dict[str, Any] = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "command": " ".join(sys.argv),
        "height": args.height,
        "widths": widths,
        "thresholds": {
            "tolerance": args.tolerance,
            "max_changed_percent": args.max_changed,
            "warn_changed_percent": args.warn_changed,
            "max_mae": args.max_mae,
            "min_ssim": args.min_ssim,
        },
        "cases": dict(previous),
        "summary": {},
    }

    for index, c in enumerate(chosen, 1):
        case_dir = lab.case_dir(c.cid)
        entry = lab.case_meta(c.cid).get("entry", "index.html")
        print(f"[visual] {index}/{len(chosen)} {c.cid} {c.name}", flush=True)
        case_row: dict[str, Any] = {
            "id": c.cid, "section": c.section, "name": c.name,
            "entry": entry, "results": [],
        }
        for width in widths:
            work = out_root / c.cid / f"{width}x{args.height}"
            work.mkdir(parents=True, exist_ok=True)
            chrome_png = work / "chrome.png"
            nativax_png = work / "nativax.png"
            diff_png = work / "diff.png"
            for stale in (chrome_png, nativax_png, diff_png):
                stale.unlink(missing_ok=True)

            row: dict[str, Any] = {"width": width, "height": args.height}
            try:
                row["chrome"] = render_chrome(
                    case_dir, entry, width, args.height, chrome_png,
                    frames=args.frames,
                    freeze_animations=not args.no_freeze_animations,
                    allow_remote=args.allow_remote,
                    timeout_ms=args.chrome_timeout * 1000)
            except Exception as exc:  # noqa: BLE001 - report, never crash the run
                row["chrome"] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
            row["nativax"] = render_nativax(
                lab, case_dir, entry, width, args.height, nativax_png,
                frames=args.frames, timeout=args.nativax_timeout)

            chrome_ok = chrome_png.exists() and row["chrome"].get("ok", True)
            nativax_ok = bool(row["nativax"].get("ok"))
            if not chrome_ok or not nativax_ok:
                status = "error"
                row["status"] = status
                row["error"] = ("chrome render failed" if not chrome_ok
                                else "nativax render failed")
            else:
                try:
                    metrics = compare_images(chrome_png, nativax_png, diff_png,
                                             tolerance=args.tolerance)
                    row["metrics"] = metrics
                    row["status"] = classify(
                        metrics,
                        max_changed=args.max_changed,
                        warn_changed=args.warn_changed,
                        max_mae=args.max_mae,
                        min_ssim=args.min_ssim)
                except Exception as exc:  # noqa: BLE001
                    row["status"] = "error"
                    row["error"] = f"{type(exc).__name__}: {exc}"

            if row["status"] != "pass":
                metric = row.get("metrics", {})
                print(f"  {row['status'].upper():5s} {width}px "
                      f"changed={metric.get('changed_percent', '?')}% "
                      f"mae={metric.get('mae', '?')} ssim={metric.get('ssim', '?')}",
                      flush=True)
            case_row["results"].append(row)

        statuses = [r["status"] for r in case_row["results"]]
        case_row["status"] = ("fail" if "fail" in statuses else
                              "error" if "error" in statuses else
                              "warn" if "warn" in statuses else "pass")
        pct = [r["metrics"]["changed_percent"] for r in case_row["results"]
               if r.get("metrics")]
        ssim = [r["metrics"]["ssim"] for r in case_row["results"]
                if r.get("metrics")]
        case_row["mean_changed_percent"] = round(sum(pct) / len(pct), 3) if pct else None
        case_row["mean_ssim"] = round(sum(ssim) / len(ssim), 5) if ssim else None
        report["cases"][c.cid] = case_row

    report["elapsed_seconds"] = round(time.time() - started, 2)
    final_results = [r for c in report["cases"].values()
                     for r in c.get("results", [])]
    counts: dict[str, int] = {}
    for r in final_results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    changed_values = [r["metrics"]["changed_percent"] for r in final_results
                      if r.get("metrics")]
    ssim_values = [r["metrics"]["ssim"] for r in final_results
                   if r.get("metrics")]
    report["summary"] = {
        "cases": len(report["cases"]),
        "comparisons": len(final_results),
        "pass": counts.get("pass", 0),
        "warn": counts.get("warn", 0),
        "fail": counts.get("fail", 0),
        "error": counts.get("error", 0),
        "mean_changed_percent": round(sum(changed_values) / len(changed_values), 3)
        if changed_values else None,
        "mean_ssim": round(sum(ssim_values) / len(ssim_values), 5)
        if ssim_values else None,
        "worst": sorted(
            ({"id": cid, "status": c["status"],
              "mean_changed_percent": c.get("mean_changed_percent")}
             for cid, c in report["cases"].items()
             if c.get("mean_changed_percent") is not None),
            key=lambda item: item["mean_changed_percent"], reverse=True)[:10],
    }

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    # Local run history: keeps evidence even when latest.json is replaced.
    runs_dir = report_path.parent / "runs"
    runs_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    (runs_dir / f"{stamp}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"[visual] report: {_rel(report_path)}", flush=True)
    print(json.dumps(report["summary"], indent=2))

    if args.json:
        print(json.dumps(report, indent=2))
    return 0 if report["summary"]["fail"] == 0 and report["summary"]["error"] == 0 else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sel = ap.add_argument_group("case selection")
    sel.add_argument("--case", action="append", default=[],
                     help="case id, repeatable (e.g. --case css.001)")
    sel.add_argument("--section", type=int, action="append", default=[],
                     help="section number, repeatable")
    sel.add_argument("--all", action="store_true", help="every registered case")
    sel.add_argument("--limit", type=int, default=0, help="maximum cases to run")
    ap.add_argument("--widths", default="1024", help="comma list, default 1024")
    ap.add_argument("--height", type=int, default=768)
    ap.add_argument("--frames", type=int, default=8,
                    help="NativaX frames before the screenshot")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--report", default=str(DEFAULT_REPORT))
    ap.add_argument("--json", action="store_true", help="print the full report")
    ap.add_argument("--fresh", action="store_true",
                    help="drop previously compared cases instead of merging")
    ap.add_argument("--self-check", action="store_true",
                    help="verify numpy/pillow/playwright/Chromium and exit")
    ap.add_argument("--allow-remote", action="store_true",
                    help="let Chrome load http(s) assets (default: block)")
    ap.add_argument("--no-freeze-animations", action="store_true",
                    help="keep CSS animations/transitions in the Chrome capture")
    ap.add_argument("--chrome-timeout", type=float, default=45.0)
    ap.add_argument("--nativax-timeout", type=float, default=90.0)
    ap.add_argument("--tolerance", type=int, default=DEFAULT_TOLERANCE,
                    help="per-channel delta treated as equal (default 4)")
    ap.add_argument("--max-changed", type=float, default=DEFAULT_MAX_CHANGED,
                    help="max changed %% for pass (default 2.0)")
    ap.add_argument("--warn-changed", type=float, default=DEFAULT_WARN_CHANGED,
                    help="changed %% above which the result fails (default 8.0)")
    ap.add_argument("--max-mae", type=float, default=DEFAULT_MAX_MAE,
                    help="max mean absolute error for pass (default 6.0)")
    ap.add_argument("--min-ssim", type=float, default=DEFAULT_MIN_SSIM,
                    help="min structural similarity for pass (default 0.90)")
    args = ap.parse_args(argv)
    if args.self_check:
        return self_check()
    if not (args.case or args.section or args.all):
        ap.error("choose --case ID, --section N or --all")
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
