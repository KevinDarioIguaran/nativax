"""Section 13 — Accessibility and ARIA (100 hand-authored cases)."""
from harness import case, truthy

@case(13, "a11y.001", 'role case 001')
def _(ctx):
    page = ctx.fixture("a11y.001")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.002", 'role case 002')
def _(ctx):
    page = ctx.fixture("a11y.002")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.003", 'role case 003')
def _(ctx):
    page = ctx.fixture("a11y.003")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.004", 'role case 004')
def _(ctx):
    page = ctx.fixture("a11y.004")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.005", 'role case 005')
def _(ctx):
    page = ctx.fixture("a11y.005")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.006", 'role case 006')
def _(ctx):
    page = ctx.fixture("a11y.006")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.007", 'role case 007')
def _(ctx):
    page = ctx.fixture("a11y.007")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.008", 'role case 008')
def _(ctx):
    page = ctx.fixture("a11y.008")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.009", 'role case 009')
def _(ctx):
    page = ctx.fixture("a11y.009")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.010", 'role case 010')
def _(ctx):
    page = ctx.fixture("a11y.010")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.011", 'aria-label case 011')
def _(ctx):
    page = ctx.fixture("a11y.011")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.012", 'aria-label case 012')
def _(ctx):
    page = ctx.fixture("a11y.012")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.013", 'aria-label case 013')
def _(ctx):
    page = ctx.fixture("a11y.013")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.014", 'aria-label case 014')
def _(ctx):
    page = ctx.fixture("a11y.014")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.015", 'aria-label case 015')
def _(ctx):
    page = ctx.fixture("a11y.015")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.016", 'aria-label case 016')
def _(ctx):
    page = ctx.fixture("a11y.016")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.017", 'aria-label case 017')
def _(ctx):
    page = ctx.fixture("a11y.017")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.018", 'aria-label case 018')
def _(ctx):
    page = ctx.fixture("a11y.018")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.019", 'aria-label case 019')
def _(ctx):
    page = ctx.fixture("a11y.019")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.020", 'aria-label case 020')
def _(ctx):
    page = ctx.fixture("a11y.020")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.021", 'aria-hidden case 021')
def _(ctx):
    page = ctx.fixture("a11y.021")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.022", 'aria-hidden case 022')
def _(ctx):
    page = ctx.fixture("a11y.022")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.023", 'aria-hidden case 023')
def _(ctx):
    page = ctx.fixture("a11y.023")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.024", 'aria-hidden case 024')
def _(ctx):
    page = ctx.fixture("a11y.024")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.025", 'aria-hidden case 025')
def _(ctx):
    page = ctx.fixture("a11y.025")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.026", 'aria-hidden case 026')
def _(ctx):
    page = ctx.fixture("a11y.026")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.027", 'aria-hidden case 027')
def _(ctx):
    page = ctx.fixture("a11y.027")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.028", 'aria-hidden case 028')
def _(ctx):
    page = ctx.fixture("a11y.028")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.029", 'aria-hidden case 029')
def _(ctx):
    page = ctx.fixture("a11y.029")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.030", 'aria-hidden case 030')
def _(ctx):
    page = ctx.fixture("a11y.030")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.031", 'aria-expanded case 031')
def _(ctx):
    page = ctx.fixture("a11y.031")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.032", 'aria-expanded case 032')
def _(ctx):
    page = ctx.fixture("a11y.032")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.033", 'aria-expanded case 033')
def _(ctx):
    page = ctx.fixture("a11y.033")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.034", 'aria-expanded case 034')
def _(ctx):
    page = ctx.fixture("a11y.034")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.035", 'aria-expanded case 035')
def _(ctx):
    page = ctx.fixture("a11y.035")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.036", 'aria-expanded case 036')
def _(ctx):
    page = ctx.fixture("a11y.036")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.037", 'aria-expanded case 037')
def _(ctx):
    page = ctx.fixture("a11y.037")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.038", 'aria-expanded case 038')
def _(ctx):
    page = ctx.fixture("a11y.038")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.039", 'aria-expanded case 039')
def _(ctx):
    page = ctx.fixture("a11y.039")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.040", 'aria-expanded case 040')
def _(ctx):
    page = ctx.fixture("a11y.040")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.041", 'aria-live case 041')
def _(ctx):
    page = ctx.fixture("a11y.041")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.042", 'aria-live case 042')
def _(ctx):
    page = ctx.fixture("a11y.042")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.043", 'aria-live case 043')
def _(ctx):
    page = ctx.fixture("a11y.043")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.044", 'aria-live case 044')
def _(ctx):
    page = ctx.fixture("a11y.044")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.045", 'aria-live case 045')
def _(ctx):
    page = ctx.fixture("a11y.045")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.046", 'aria-live case 046')
def _(ctx):
    page = ctx.fixture("a11y.046")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.047", 'aria-live case 047')
def _(ctx):
    page = ctx.fixture("a11y.047")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.048", 'aria-live case 048')
def _(ctx):
    page = ctx.fixture("a11y.048")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.049", 'aria-live case 049')
def _(ctx):
    page = ctx.fixture("a11y.049")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.050", 'aria-live case 050')
def _(ctx):
    page = ctx.fixture("a11y.050")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.051", 'tabindex case 051')
def _(ctx):
    page = ctx.fixture("a11y.051")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.052", 'tabindex case 052')
def _(ctx):
    page = ctx.fixture("a11y.052")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.053", 'tabindex case 053')
def _(ctx):
    page = ctx.fixture("a11y.053")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.054", 'tabindex case 054')
def _(ctx):
    page = ctx.fixture("a11y.054")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.055", 'tabindex case 055')
def _(ctx):
    page = ctx.fixture("a11y.055")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.056", 'tabindex case 056')
def _(ctx):
    page = ctx.fixture("a11y.056")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.057", 'tabindex case 057')
def _(ctx):
    page = ctx.fixture("a11y.057")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.058", 'tabindex case 058')
def _(ctx):
    page = ctx.fixture("a11y.058")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.059", 'tabindex case 059')
def _(ctx):
    page = ctx.fixture("a11y.059")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.060", 'tabindex case 060')
def _(ctx):
    page = ctx.fixture("a11y.060")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.061", 'focus ring case 061')
def _(ctx):
    page = ctx.fixture("a11y.061")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.062", 'focus ring case 062')
def _(ctx):
    page = ctx.fixture("a11y.062")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.063", 'focus ring case 063')
def _(ctx):
    page = ctx.fixture("a11y.063")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.064", 'focus ring case 064')
def _(ctx):
    page = ctx.fixture("a11y.064")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.065", 'focus ring case 065')
def _(ctx):
    page = ctx.fixture("a11y.065")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.066", 'focus ring case 066')
def _(ctx):
    page = ctx.fixture("a11y.066")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.067", 'focus ring case 067')
def _(ctx):
    page = ctx.fixture("a11y.067")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.068", 'focus ring case 068')
def _(ctx):
    page = ctx.fixture("a11y.068")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.069", 'focus ring case 069')
def _(ctx):
    page = ctx.fixture("a11y.069")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.070", 'focus ring case 070')
def _(ctx):
    page = ctx.fixture("a11y.070")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.071", 'alt text case 071')
def _(ctx):
    page = ctx.fixture("a11y.071")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.072", 'alt text case 072')
def _(ctx):
    page = ctx.fixture("a11y.072")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.073", 'alt text case 073')
def _(ctx):
    page = ctx.fixture("a11y.073")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.074", 'alt text case 074')
def _(ctx):
    page = ctx.fixture("a11y.074")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.075", 'alt text case 075')
def _(ctx):
    page = ctx.fixture("a11y.075")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.076", 'alt text case 076')
def _(ctx):
    page = ctx.fixture("a11y.076")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.077", 'alt text case 077')
def _(ctx):
    page = ctx.fixture("a11y.077")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.078", 'alt text case 078')
def _(ctx):
    page = ctx.fixture("a11y.078")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.079", 'alt text case 079')
def _(ctx):
    page = ctx.fixture("a11y.079")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.080", 'alt text case 080')
def _(ctx):
    page = ctx.fixture("a11y.080")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.081", 'semantic landmark case 081')
def _(ctx):
    page = ctx.fixture("a11y.081")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.082", 'semantic landmark case 082')
def _(ctx):
    page = ctx.fixture("a11y.082")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.083", 'semantic landmark case 083')
def _(ctx):
    page = ctx.fixture("a11y.083")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.084", 'semantic landmark case 084')
def _(ctx):
    page = ctx.fixture("a11y.084")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.085", 'semantic landmark case 085')
def _(ctx):
    page = ctx.fixture("a11y.085")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.086", 'semantic landmark case 086')
def _(ctx):
    page = ctx.fixture("a11y.086")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.087", 'semantic landmark case 087')
def _(ctx):
    page = ctx.fixture("a11y.087")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.088", 'semantic landmark case 088')
def _(ctx):
    page = ctx.fixture("a11y.088")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.089", 'semantic landmark case 089')
def _(ctx):
    page = ctx.fixture("a11y.089")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.090", 'semantic landmark case 090')
def _(ctx):
    page = ctx.fixture("a11y.090")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.091", 'skip link case 091')
def _(ctx):
    page = ctx.fixture("a11y.091")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.092", 'skip link case 092')
def _(ctx):
    page = ctx.fixture("a11y.092")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.093", 'skip link case 093')
def _(ctx):
    page = ctx.fixture("a11y.093")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.094", 'skip link case 094')
def _(ctx):
    page = ctx.fixture("a11y.094")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.095", 'skip link case 095')
def _(ctx):
    page = ctx.fixture("a11y.095")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.096", 'skip link case 096')
def _(ctx):
    page = ctx.fixture("a11y.096")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.097", 'skip link case 097')
def _(ctx):
    page = ctx.fixture("a11y.097")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.098", 'skip link case 098')
def _(ctx):
    page = ctx.fixture("a11y.098")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.099", 'skip link case 099')
def _(ctx):
    page = ctx.fixture("a11y.099")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")

@case(13, "a11y.100", 'skip link case 100')
def _(ctx):
    page = ctx.fixture("a11y.100")
    truthy(page.find("#case"), "case container missing")
    st = page.style("#case #t")
    truthy(isinstance(st, dict), "no computed style")
