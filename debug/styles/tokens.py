"""Design tokens of the debug suite UI.

Components refer only to these semantic names; no component file contains a
hex color, a font family or a pixel size of its own (enforced by
debug/tests/ui/test_tokens.py). Two themes share the same token names.
"""
from __future__ import annotations

from dataclasses import dataclass, field

FONT_UI = "Noto Sans"
FONT_MONO = "DejaVu Sans Mono"


@dataclass(frozen=True)
class Theme:
    name: str
    color: dict = field(default_factory=dict)


_DARK = {
    "surface": "#0b0f14",           # page background
    "surface-raised": "#11161d",    # panels, cards
    "surface-sunken": "#070a0f",    # logs, code
    "surface-control": "#18202a",   # inputs, buttons
    "surface-hover": "#1f2a36",
    "surface-selected": "#1f3a5f",
    "surface-stripe": "#0f151d",    # alternate table rows
    "nav": "#0c1117",
    "border-subtle": "#212b36",
    "border-strong": "#3a4757",
    "text-primary": "#e6edf3",
    "text-secondary": "#9fb3c8",
    "text-disabled": "#6e7681",
    "text-inverse": "#07101f",
    "accent": "#7aa2ff",
    "status-ok": "#3fb950",
    "status-warning": "#d29922",
    "status-error": "#f85149",
    "status-critical": "#ff7b72",
    "status-info": "#39c5cf",
    "status-unknown": "#6e7681",    # unavailable / not measured
    "status-estimate": "#a371f7",   # hypotheses, estimates
    "diff-added": "#3fb950",
    "diff-removed": "#f85149",
    "diff-changed": "#d29922",
    "diff-moved": "#39c5cf",
    "syntax-key": "#7aa2ff",
    "syntax-string": "#a5d6ff",
    "syntax-number": "#ffa657",
    "syntax-literal": "#a371f7",
    "syntax-null": "#6e7681",
    "highlight": "#2d3f1f",
    "series-1": "#7aa2ff", "series-2": "#3fb950", "series-3": "#d29922", "series-4": "#f85149",
    "series-5": "#a371f7", "series-6": "#39c5cf", "series-7": "#f0883e", "series-8": "#db61a2",
    "reference": "#39c5cf",         # Chromium in overlays
    "actual": "#f0883e",            # NativaX in overlays
}

_LIGHT = {
    "surface": "#f6f8fa", "surface-raised": "#ffffff", "surface-sunken": "#eef1f4",
    "surface-control": "#eaeef2", "surface-hover": "#dde3ea", "surface-selected": "#cfe0ff",
    "surface-stripe": "#f3f5f7", "nav": "#eef1f4", "border-subtle": "#d0d7de", "border-strong": "#8c959f",
    "text-primary": "#1f2328", "text-secondary": "#57606a", "text-disabled": "#8c959f",
    "text-inverse": "#ffffff", "accent": "#0969da", "status-ok": "#1a7f37", "status-warning": "#9a6700",
    "status-error": "#cf222e", "status-critical": "#a40e26", "status-info": "#0a7f8f",
    "status-unknown": "#6e7781", "status-estimate": "#8250df", "diff-added": "#1a7f37",
    "diff-removed": "#cf222e", "diff-changed": "#9a6700", "diff-moved": "#0a7f8f",
    "syntax-key": "#0550ae", "syntax-string": "#0a3069", "syntax-number": "#953800",
    "syntax-literal": "#8250df", "syntax-null": "#6e7781", "highlight": "#fff8c5",
    "series-1": "#0969da", "series-2": "#1a7f37", "series-3": "#9a6700", "series-4": "#cf222e",
    "series-5": "#8250df", "series-6": "#0a7f8f", "series-7": "#bc4c00", "series-8": "#bf3989",
    "reference": "#0a7f8f", "actual": "#bc4c00",
}

THEMES = {"dark": Theme("dark", _DARK), "light": Theme("light", _LIGHT)}

TYPE = {  # role -> (family, size, weight)
    "title": (FONT_UI, 13, "bold"),
    "heading": (FONT_UI, 10, "bold"),
    "body": (FONT_UI, 9, "normal"),
    "label": (FONT_UI, 9, "bold"),
    "caption": (FONT_UI, 8, "normal"),
    "metric": (FONT_MONO, 12, "bold"),
    "code": (FONT_MONO, 9, "normal"),
    "code-small": (FONT_MONO, 8, "normal"),
}

SPACE = {"xxs": 1, "xs": 2, "sm": 4, "md": 8, "lg": 12, "xl": 16}
SIZE = {"row": 21, "nav-width": 280, "page-size": 200, "border": 1}

# Status vocabulary -> color token. Used for every badge, row tag and chart.
STATUS = {
    "completed": "status-ok", "complete": "status-ok", "passed": "status-ok", "pass": "status-ok",
    "ok": "status-ok", "improved": "status-ok", "no_leak": "status-ok",
    "warn": "status-warning", "warning": "status-warning", "partial": "status-warning",
    "medium": "status-warning", "suspected_leak": "status-warning", "bounded_high_usage": "status-warning",
    "failed": "status-error", "fail": "status-error", "error": "status-error", "regressed": "status-error",
    "high": "status-error", "proven_leak": "status-error",
    "critical": "status-critical", "aborted": "status-critical", "invalid": "status-critical",
    "info": "status-info", "new": "status-info",
    "unchanged": "text-secondary", "low": "text-secondary", "known": "text-secondary",
    "inconclusive": "status-unknown", "not_comparable": "status-unknown", "unknown": "status-unknown",
    "skip": "status-unknown", "running": "status-info", "incomplete": "status-warning",
    "oracle_conflict": "status-estimate", "unconfirmed": "status-estimate", "estimate": "status-estimate",
    "added": "diff-added", "removed": "diff-removed", "changed": "diff-changed", "moved": "diff-moved",
    "type_changed": "status-estimate",
}


def status_token(value) -> str:
    return STATUS.get(str(value or "unknown").lower(), "text-primary")
