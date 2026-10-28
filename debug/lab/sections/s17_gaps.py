"""Section 17 — capability gaps (reported as blocked, never faked)."""
from harness import case, Blocked, close, truthy

@case(17, "gap.001", 'var() custom properties')
def _(ctx):
    raise Blocked('CSS var() is not evaluated by the engine.')

@case(17, "gap.002", 'hsl() colour values')
def _(ctx):
    page = ctx.page("<div id=t>x</div>", "#t { color: hsl(120, 100%, 50%); }")
    st = page.style("#t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)

@case(17, "gap.003", 'calc() in lengths')
def _(ctx):
    page = ctx.page("<div id=t>x</div>", "#t { width: calc(100% - 20px); }")
    b = page.box("#t")
    truthy(b is not None, "box missing")
    close(b.get("w", 0), 1004, 1.0)

@case(17, "gap.004", 'position: absolute/fixed layout')
def _(ctx):
    raise Blocked('Absolute/fixed positioning is not applied in layout.')

@case(17, "gap.005", 'float/clear layout')
def _(ctx):
    raise Blocked('Float layout is not implemented.')

@case(17, "gap.006", 'display: grid')
def _(ctx):
    raise Blocked('Grid layout is not implemented.')

@case(17, "gap.007", 'display: contents')
def _(ctx):
    raise Blocked('display: contents is not implemented.')

@case(17, "gap.008", 'display: list-item')
def _(ctx):
    raise Blocked('List-item marker layout is not implemented.')

@case(17, "gap.009", 'display: inline-block metrics')
def _(ctx):
    raise Blocked('Inline-block shrink-to-fit is approximate.')

@case(17, "gap.010", 'img paint wiring')
def _(ctx):
    raise Blocked('img/src background-image paint wiring is missing.')

@case(17, "gap.011", 'inline SVG')
def _(ctx):
    raise Blocked('SVG rendering is not wired.')

@case(17, "gap.012", 'canvas element')
def _(ctx):
    raise Blocked('Canvas 2D context is not implemented.')

@case(17, "gap.013", 'WebGL/Three.js')
def _(ctx):
    raise Blocked('WebGL is not available.')

@case(17, "gap.014", 'innerHTML getter')
def _(ctx):
    raise Blocked('innerHTML getter is broken.')

@case(17, "gap.015", 'font-weight application')
def _(ctx):
    raise Blocked('font-weight is parsed but not applied in text metrics.')

@case(17, "gap.016", 'flex item coordinates')
def _(ctx):
    raise Blocked('Flex item coordinate computation has a known bug.')

@case(17, "gap.017", 'Windows platform')
def _(ctx):
    raise Blocked('Windows backend is not available in this environment.')

@case(17, "gap.018", 'macOS platform')
def _(ctx):
    raise Blocked('macOS backend is not available in this environment.')

@case(17, "gap.019", 'iOS platform')
def _(ctx):
    raise Blocked('iOS backend is not available in this environment.')

@case(17, "gap.020", 'Chromium comparison')
def _(ctx):
    raise Blocked('Chromium comparison tooling is not available.')

@case(17, "gap.021", 'animation frame timing')
def _(ctx):
    raise Blocked('Animation timing is not measured.')

@case(17, "gap.022", 'prefers-reduced-motion runtime')
def _(ctx):
    raise Blocked('Reduced-motion switching is not tested at runtime.')

@case(17, "gap.023", 'requestAnimationFrame')
def _(ctx):
    raise Blocked('requestAnimationFrame is not implemented.')

@case(17, "gap.024", '@supports evaluation')
def _(ctx):
    raise Blocked('@supports blocks are skipped, not evaluated.')

@case(17, "gap.025", '@layer cascade')
def _(ctx):
    raise Blocked('@layer is skipped, not cascaded.')

@case(17, "gap.026", '@import resolution')
def _(ctx):
    raise Blocked('@import is not resolved.')

@case(17, "gap.027", 'accessibility tree')
def _(ctx):
    raise Blocked('No accessibility tree is exposed.')

@case(17, "gap.028", 'RTL/bidi text')
def _(ctx):
    raise Blocked('RTL/bidi text is not handled.')

@case(17, "gap.029", 'localStorage')
def _(ctx):
    raise Blocked('localStorage is not implemented.')

@case(17, "gap.030", 'IndexedDB')
def _(ctx):
    raise Blocked('IndexedDB is not implemented.')


@case(17, "gap.031", 'video playback')
def _(ctx):
    raise Blocked('Video playback/decoding is not implemented (no decoder available).')


@case(17, "gap.032", 'scroll support')
def _(ctx):
    raise Blocked('Scroll/overflow scrolling is not implemented.')
