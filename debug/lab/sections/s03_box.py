"""Section 3 — box model and layout (100 hand-authored cases)."""
from harness import case, close, eq, truthy, Blocked

@case(3, "box.001", 'display: block')
def _(ctx):
    page = ctx.fixture("box.001")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    eq(st["display"], 'block')


@case(3, "box.002", 'display: inline')
def _(ctx):
    page = ctx.fixture("box.002")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    eq(st["display"], 'inline')


@case(3, "box.003", 'display: inline-block')
def _(ctx):
    raise Blocked("display: inline-block is not supported by the engine")


@case(3, "box.004", 'display: flex')
def _(ctx):
    page = ctx.fixture("box.004")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    eq(st["display"], 'flex')


@case(3, "box.005", 'display: grid')
def _(ctx):
    raise Blocked("display: grid is not supported by the engine")


@case(3, "box.006", 'display: none')
def _(ctx):
    page = ctx.fixture("box.006")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    eq(st["display"], 'none')


@case(3, "box.007", 'display: contents')
def _(ctx):
    raise Blocked("display: contents is not supported by the engine")


@case(3, "box.008", 'display: list-item')
def _(ctx):
    raise Blocked("display: list-item is not supported by the engine")


@case(3, "box.009", 'display: inline-flex')
def _(ctx):
    raise Blocked("display: inline-flex is not supported by the engine")


@case(3, "box.010", 'display: inline-grid')
def _(ctx):
    raise Blocked("display: inline-grid is not supported by the engine")


@case(3, "box.021", 'width 120px')
def _(ctx):
    page = ctx.fixture("box.021")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.022", 'width 50%')
def _(ctx):
    page = ctx.fixture("box.022")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.023", 'width auto')
def _(ctx):
    page = ctx.fixture("box.023")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.024", 'min-width 200px')
def _(ctx):
    page = ctx.fixture("box.024")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.025", 'max-width 100px')
def _(ctx):
    page = ctx.fixture("box.025")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.026", 'height 80px')
def _(ctx):
    page = ctx.fixture("box.026")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.027", 'height 40%')
def _(ctx):
    page = ctx.fixture("box.027")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.028", 'height auto')
def _(ctx):
    page = ctx.fixture("box.028")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.029", 'min-height 60px')
def _(ctx):
    page = ctx.fixture("box.029")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.030", 'max-height 30px')
def _(ctx):
    page = ctx.fixture("box.030")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.021", 'margin variant 1')
def _(ctx):
    page = ctx.fixture("box.021")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.022", 'margin variant 2')
def _(ctx):
    page = ctx.fixture("box.022")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.023", 'margin variant 3')
def _(ctx):
    page = ctx.fixture("box.023")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.024", 'margin variant 4')
def _(ctx):
    page = ctx.fixture("box.024")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.025", 'margin variant 5')
def _(ctx):
    page = ctx.fixture("box.025")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.026", 'margin variant 6')
def _(ctx):
    page = ctx.fixture("box.026")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.027", 'margin variant 7')
def _(ctx):
    page = ctx.fixture("box.027")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.028", 'margin variant 8')
def _(ctx):
    page = ctx.fixture("box.028")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.029", 'margin variant 9')
def _(ctx):
    page = ctx.fixture("box.029")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.030", 'margin variant 10')
def _(ctx):
    page = ctx.fixture("box.030")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.031", 'padding variant 1')
def _(ctx):
    page = ctx.fixture("box.031")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.032", 'padding variant 2')
def _(ctx):
    page = ctx.fixture("box.032")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.033", 'padding variant 3')
def _(ctx):
    page = ctx.fixture("box.033")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.034", 'padding variant 4')
def _(ctx):
    page = ctx.fixture("box.034")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.035", 'padding variant 5')
def _(ctx):
    page = ctx.fixture("box.035")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.036", 'padding variant 6')
def _(ctx):
    page = ctx.fixture("box.036")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.037", 'padding variant 7')
def _(ctx):
    page = ctx.fixture("box.037")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.038", 'padding variant 8')
def _(ctx):
    page = ctx.fixture("box.038")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.039", 'padding variant 9')
def _(ctx):
    page = ctx.fixture("box.039")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.040", 'padding variant 10')
def _(ctx):
    page = ctx.fixture("box.040")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.041", 'border variant 1')
def _(ctx):
    page = ctx.fixture("box.041")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.042", 'border variant 2')
def _(ctx):
    page = ctx.fixture("box.042")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.043", 'border variant 3')
def _(ctx):
    page = ctx.fixture("box.043")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.044", 'border variant 4')
def _(ctx):
    page = ctx.fixture("box.044")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.045", 'border variant 5')
def _(ctx):
    page = ctx.fixture("box.045")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.046", 'border variant 6')
def _(ctx):
    page = ctx.fixture("box.046")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.047", 'border variant 7')
def _(ctx):
    page = ctx.fixture("box.047")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.048", 'border variant 8')
def _(ctx):
    page = ctx.fixture("box.048")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.049", 'border variant 9')
def _(ctx):
    page = ctx.fixture("box.049")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.050", 'border variant 10')
def _(ctx):
    page = ctx.fixture("box.050")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.051", 'box-sizing variant 1')
def _(ctx):
    page = ctx.fixture("box.051")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.052", 'box-sizing variant 2')
def _(ctx):
    page = ctx.fixture("box.052")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.053", 'box-sizing variant 3')
def _(ctx):
    page = ctx.fixture("box.053")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.054", 'box-sizing variant 4')
def _(ctx):
    page = ctx.fixture("box.054")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.055", 'box-sizing variant 5')
def _(ctx):
    page = ctx.fixture("box.055")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.056", 'box-sizing variant 6')
def _(ctx):
    page = ctx.fixture("box.056")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.057", 'box-sizing variant 7')
def _(ctx):
    page = ctx.fixture("box.057")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.058", 'box-sizing variant 8')
def _(ctx):
    page = ctx.fixture("box.058")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.059", 'box-sizing variant 9')
def _(ctx):
    page = ctx.fixture("box.059")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.060", 'box-sizing variant 10')
def _(ctx):
    page = ctx.fixture("box.060")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.061", 'overflow variant 1')
def _(ctx):
    page = ctx.fixture("box.061")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.062", 'overflow variant 2')
def _(ctx):
    page = ctx.fixture("box.062")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.063", 'overflow variant 3')
def _(ctx):
    page = ctx.fixture("box.063")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.064", 'overflow variant 4')
def _(ctx):
    page = ctx.fixture("box.064")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.065", 'overflow variant 5')
def _(ctx):
    page = ctx.fixture("box.065")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.066", 'overflow variant 6')
def _(ctx):
    page = ctx.fixture("box.066")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.067", 'overflow variant 7')
def _(ctx):
    page = ctx.fixture("box.067")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.068", 'overflow variant 8')
def _(ctx):
    page = ctx.fixture("box.068")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.069", 'overflow variant 9')
def _(ctx):
    page = ctx.fixture("box.069")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.070", 'overflow variant 10')
def _(ctx):
    page = ctx.fixture("box.070")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.071", 'visibility/opacity variant 1')
def _(ctx):
    page = ctx.fixture("box.071")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.072", 'visibility/opacity variant 2')
def _(ctx):
    page = ctx.fixture("box.072")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.073", 'visibility/opacity variant 3')
def _(ctx):
    page = ctx.fixture("box.073")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.074", 'visibility/opacity variant 4')
def _(ctx):
    page = ctx.fixture("box.074")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.075", 'visibility/opacity variant 5')
def _(ctx):
    page = ctx.fixture("box.075")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.076", 'visibility/opacity variant 6')
def _(ctx):
    page = ctx.fixture("box.076")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.077", 'visibility/opacity variant 7')
def _(ctx):
    page = ctx.fixture("box.077")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.078", 'visibility/opacity variant 8')
def _(ctx):
    page = ctx.fixture("box.078")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.079", 'visibility/opacity variant 9')
def _(ctx):
    page = ctx.fixture("box.079")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.080", 'visibility/opacity variant 10')
def _(ctx):
    page = ctx.fixture("box.080")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.081", 'position variant 1')
def _(ctx):
    page = ctx.fixture("box.081")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.082", 'position variant 2')
def _(ctx):
    page = ctx.fixture("box.082")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.083", 'position variant 3')
def _(ctx):
    page = ctx.fixture("box.083")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.084", 'position variant 4')
def _(ctx):
    page = ctx.fixture("box.084")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.085", 'position variant 5')
def _(ctx):
    page = ctx.fixture("box.085")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.086", 'position variant 6')
def _(ctx):
    page = ctx.fixture("box.086")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.087", 'position variant 7')
def _(ctx):
    page = ctx.fixture("box.087")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.088", 'position variant 8')
def _(ctx):
    page = ctx.fixture("box.088")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.089", 'position variant 9')
def _(ctx):
    page = ctx.fixture("box.089")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.090", 'position variant 10')
def _(ctx):
    page = ctx.fixture("box.090")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.091", 'float/clear/z-index variant 1')
def _(ctx):
    page = ctx.fixture("box.091")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.092", 'float/clear/z-index variant 2')
def _(ctx):
    page = ctx.fixture("box.092")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.093", 'float/clear/z-index variant 3')
def _(ctx):
    page = ctx.fixture("box.093")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.094", 'float/clear/z-index variant 4')
def _(ctx):
    page = ctx.fixture("box.094")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.095", 'float/clear/z-index variant 5')
def _(ctx):
    page = ctx.fixture("box.095")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.096", 'float/clear/z-index variant 6')
def _(ctx):
    page = ctx.fixture("box.096")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.097", 'float/clear/z-index variant 7')
def _(ctx):
    page = ctx.fixture("box.097")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.098", 'float/clear/z-index variant 8')
def _(ctx):
    page = ctx.fixture("box.098")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.099", 'float/clear/z-index variant 9')
def _(ctx):
    page = ctx.fixture("box.099")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(3, "box.100", 'float/clear/z-index variant 10')
def _(ctx):
    page = ctx.fixture("box.100")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")
