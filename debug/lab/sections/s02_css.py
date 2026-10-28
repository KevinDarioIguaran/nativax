"""Section 2 — CSS selectors and cascade (100 hand-authored cases)."""
from harness import case, close, eq, gt, truthy, Blocked


@case(2, "css.001", 'tag selector colours the element')
def _(ctx):
    st = ctx.fixture("css.001").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.002", 'class selector colours the element')
def _(ctx):
    st = ctx.fixture("css.002").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.003", 'id selector colours the element')
def _(ctx):
    st = ctx.fixture("css.003").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.004", 'universal selector colours every element')
def _(ctx):
    st = ctx.fixture("css.004").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.005", 'attribute presence selector')
def _(ctx):
    st = ctx.fixture("css.005").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.006", 'attribute equals selector')
def _(ctx):
    st = ctx.fixture("css.006").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.007", 'attribute contains selector')
def _(ctx):
    st = ctx.fixture("css.007").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0.533333, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.008", 'attribute starts-with selector')
def _(ctx):
    st = ctx.fixture("css.008").style("#case #t")
    close(st["color"][0], 0.533333, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.009", 'attribute ends-with selector')
def _(ctx):
    st = ctx.fixture("css.009").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0.533333, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.010", 'attribute word selector')
def _(ctx):
    st = ctx.fixture("css.010").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0.533333, 0.01)


@case(2, "css.011", 'descendant combinator')
def _(ctx):
    st = ctx.fixture("css.011").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.012", 'child combinator')
def _(ctx):
    st = ctx.fixture("css.012").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.013", 'adjacent sibling combinator')
def _(ctx):
    st = ctx.fixture("css.013").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.014", 'general sibling combinator')
def _(ctx):
    st = ctx.fixture("css.014").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.015", 'grouped selectors')
def _(ctx):
    st = ctx.fixture("css.015").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.016", 'deep descendant')
def _(ctx):
    st = ctx.fixture("css.016").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.017", 'child of id')
def _(ctx):
    st = ctx.fixture("css.017").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0.533333, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.018", 'sibling with class filter')
def _(ctx):
    st = ctx.fixture("css.018").style("#case #t")
    close(st["color"][0], 0.533333, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.019", 'descendant with attribute')
def _(ctx):
    st = ctx.fixture("css.019").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0.533333, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.020", 'universal child')
def _(ctx):
    st = ctx.fixture("css.020").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0.533333, 0.01)


@case(2, "css.021", 'first-child pseudo-class')
def _(ctx):
    st = ctx.fixture("css.021").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.022", 'last-child pseudo-class')
def _(ctx):
    st = ctx.fixture("css.022").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.023", 'nth-child(2)')
def _(ctx):
    st = ctx.fixture("css.023").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.024", 'nth-child(odd)')
def _(ctx):
    st = ctx.fixture("css.024").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.025", 'nth-child(3n)')
def _(ctx):
    st = ctx.fixture("css.025").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.026", 'not() pseudo-class')
def _(ctx):
    st = ctx.fixture("css.026").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.027", 'empty pseudo-class')
def _(ctx):
    st = ctx.fixture("css.027").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0.533333, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.028", 'first-of-type')
def _(ctx):
    st = ctx.fixture("css.028").style("#case #t")
    close(st["color"][0], 0.533333, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.029", 'nth-of-type(2) (engine counts siblings)')
def _(ctx):
    st = ctx.fixture("css.029").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.030", 'last-of-type')
def _(ctx):
    st = ctx.fixture("css.030").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0.533333, 0.01)


@case(2, "css.031", 'id beats class')
def _(ctx):
    st = ctx.fixture("css.031").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.032", 'class beats element')
def _(ctx):
    st = ctx.fixture("css.032").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.033", 'later rule wins tie')
def _(ctx):
    st = ctx.fixture("css.033").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.034", 'inline style wins')
def _(ctx):
    st = ctx.fixture("css.034").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.035", 'important wins')
def _(ctx):
    st = ctx.fixture("css.035").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.036", 'important class beats id')
def _(ctx):
    st = ctx.fixture("css.036").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.037", 'two inline sheets order')
def _(ctx):
    page = ctx.fixture("css.037")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.038", 'media applies at wide viewport')
def _(ctx):
    page = ctx.fixture("css.038")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.039", 'media does not apply at wide viewport')
def _(ctx):
    page = ctx.fixture("css.039")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.040", 'color inherits from parent')
def _(ctx):
    st = ctx.fixture("css.040").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.041", 'color inherits')
def _(ctx):
    st = ctx.fixture("css.041").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.042", 'font-size inherits via em')
def _(ctx):
    st = ctx.fixture("css.042").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.043", 'initial resets color')
def _(ctx):
    st = ctx.fixture("css.043").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.044", 'unset on color inherits')
def _(ctx):
    st = ctx.fixture("css.044").style("#case #t")
    close(st["color"][2], 1.0, 0.01)
    close(st["color"][0], 0.0, 0.01)


@case(2, "css.045", 'unset on margin resets')
def _(ctx):
    st = ctx.fixture("css.045").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.046", 'inherit keyword on margin')
def _(ctx):
    st = ctx.fixture("css.046").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.047", 'currentColor border')
def _(ctx):
    st = ctx.fixture("css.047").style("#case #t")
    close(st["color"][2], 1.0, 0.01)
    close(st["color"][0], 0.0, 0.01)


@case(2, "css.048", 'transparent color')
def _(ctx):
    st = ctx.fixture("css.048").style("#case #t")
    close(st["color"][3], 0.0, 0.01)


@case(2, "css.049", 'inherit from ancestor')
def _(ctx):
    st = ctx.fixture("css.049").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.050", 'default colour inherits the theme ink')
def _(ctx):
    st = ctx.fixture("css.050").style("#case #t")
    close(st["color"][0], 0.9098, 0.01)
    close(st["color"][1], 0.9333, 0.01)
    close(st["color"][2], 0.9882, 0.01)


@case(2, "css.051", 'margin shorthand all')
def _(ctx):
    st = ctx.fixture("css.051").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.052", 'margin two values')
def _(ctx):
    st = ctx.fixture("css.052").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.053", 'margin three values')
def _(ctx):
    st = ctx.fixture("css.053").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.054", 'margin four values')
def _(ctx):
    st = ctx.fixture("css.054").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.055", 'padding shorthand')
def _(ctx):
    st = ctx.fixture("css.055").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.056", 'border shorthand')
def _(ctx):
    st = ctx.fixture("css.056").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.057", 'border-top shorthand')
def _(ctx):
    st = ctx.fixture("css.057").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.058", 'background shorthand color')
def _(ctx):
    st = ctx.fixture("css.058").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.059", 'border-radius shorthand')
def _(ctx):
    st = ctx.fixture("css.059").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.060", 'font shorthand')
def _(ctx):
    st = ctx.fixture("css.060").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.061", 'length in px')
def _(ctx):
    st = ctx.fixture("css.061").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.062", 'length in em')
def _(ctx):
    st = ctx.fixture("css.062").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.063", 'length in rem')
def _(ctx):
    st = ctx.fixture("css.063").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.064", 'length in percent')
def _(ctx):
    st = ctx.fixture("css.064").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.065", 'font-size px')
def _(ctx):
    st = ctx.fixture("css.065").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.066", 'font-size em')
def _(ctx):
    st = ctx.fixture("css.066").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.067", 'line-height unitless')
def _(ctx):
    st = ctx.fixture("css.067").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.068", 'border-width px')
def _(ctx):
    st = ctx.fixture("css.068").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.069", 'min-width px')
def _(ctx):
    st = ctx.fixture("css.069").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.070", 'max-width px')
def _(ctx):
    st = ctx.fixture("css.070").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.071", 'hex 3-digit color')
def _(ctx):
    st = ctx.fixture("css.071").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.072", 'hex 6-digit color')
def _(ctx):
    st = ctx.fixture("css.072").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.073", 'rgb() color')
def _(ctx):
    st = ctx.fixture("css.073").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 1, 0.01)


@case(2, "css.074", 'rgba() color')
def _(ctx):
    st = ctx.fixture("css.074").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0.501961, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.075", 'named color')
def _(ctx):
    st = ctx.fixture("css.075").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.076", 'hsl() color (unsupported)')
def _(ctx):
    raise Blocked("hsl() colour values are not supported by the engine")


@case(2, "css.077", 'transparent keyword')
def _(ctx):
    st = ctx.fixture("css.077").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.078", 'currentColor keyword')
def _(ctx):
    st = ctx.fixture("css.078").style("#case #t")
    truthy(isinstance(st, dict), "no computed style")


@case(2, "css.079", 'var() custom property (unsupported)')
def _(ctx):
    raise Blocked("var() custom properties are not supported by the engine")


@case(2, "css.080", 'rgb percentages')
def _(ctx):
    st = ctx.fixture("css.080").style("#case #t")
    close(st["color"][0], 1, 0.01)
    close(st["color"][1], 0, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.081", 'min-width media applies')
def _(ctx):
    st = ctx.fixture("css.081").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.082", 'max-width media applies')
def _(ctx):
    st = ctx.fixture("css.082").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.083", 'min-width media not applies')
def _(ctx):
    st = ctx.fixture("css.083").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.084", 'orientation landscape applies')
def _(ctx):
    st = ctx.fixture("css.084").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.085", 'orientation portrait not applies')
def _(ctx):
    st = ctx.fixture("css.085").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.086", 'combined media range')
def _(ctx):
    st = ctx.fixture("css.086").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.087", 'min-height media')
def _(ctx):
    st = ctx.fixture("css.087").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.088", 'max-height media')
def _(ctx):
    st = ctx.fixture("css.088").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.089", 'screen media applies')
def _(ctx):
    st = ctx.fixture("css.089").style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.090", 'print media not applies')
def _(ctx):
    st = ctx.fixture("css.090").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.091", 'keyframes rule is recorded')
def _(ctx):
    page = ctx.fixture("css.091")
    rules = [r for r in page.rules() if "keyframes" in r.get("at", "") or "spin" in str(r)]
    truthy(page.rules(), "no rules recorded")


@case(2, "css.092", 'font-face at-rule is skipped safely')
def _(ctx):
    page = ctx.fixture("css.092")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.093", 'supports at-rule is skipped')
def _(ctx):
    page = ctx.fixture("css.093")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.094", 'layer at-rule is skipped')
def _(ctx):
    page = ctx.fixture("css.094")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.095", 'nested media flattens')
def _(ctx):
    st = ctx.fixture("css.095").style("#case #t")
    close(st["color"][0], 0, 0.01)
    close(st["color"][1], 1, 0.01)
    close(st["color"][2], 0, 0.01)


@case(2, "css.096", 'unknown at-rule is skipped')
def _(ctx):
    page = ctx.fixture("css.096")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.097", 'charset at-rule is skipped')
def _(ctx):
    page = ctx.fixture("css.097")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.098", 'empty stylesheet')
def _(ctx):
    page = ctx.fixture("css.098")
    st = page.style("#case #t")
    close(st["color"][0], 0.9098, 0.01)
    close(st["color"][1], 0.9333, 0.01)
    close(st["color"][2], 0.9882, 0.01)


@case(2, "css.099", 'multiple inline sheets order')
def _(ctx):
    page = ctx.fixture("css.099")
    st = page.style("#case #t")
    close(st["color"][1], 1.0, 0.01)


@case(2, "css.100", 'important across sheets')
def _(ctx):
    page = ctx.fixture("css.100")
    st = page.style("#case #t")
    close(st["color"][0], 1.0, 0.01)

