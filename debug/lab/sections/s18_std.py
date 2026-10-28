"""Section 18 — web standards suites (imported subset + blocked)."""
from harness import case, truthy, Blocked

@case(18, "std.001", 'html5lib parser case 01')
def _(ctx):
    page = ctx.fixture("std.001")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.002", 'html5lib parser case 02')
def _(ctx):
    page = ctx.fixture("std.002")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.003", 'html5lib parser case 03')
def _(ctx):
    page = ctx.fixture("std.003")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.004", 'html5lib parser case 04')
def _(ctx):
    page = ctx.fixture("std.004")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.005", 'html5lib parser case 05')
def _(ctx):
    page = ctx.fixture("std.005")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.006", 'html5lib parser case 06')
def _(ctx):
    page = ctx.fixture("std.006")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.007", 'html5lib parser case 07')
def _(ctx):
    page = ctx.fixture("std.007")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.008", 'html5lib parser case 08')
def _(ctx):
    page = ctx.fixture("std.008")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.009", 'html5lib parser case 09')
def _(ctx):
    page = ctx.fixture("std.009")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.010", 'html5lib parser case 10')
def _(ctx):
    page = ctx.fixture("std.010")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.011", 'html5lib parser case 11')
def _(ctx):
    page = ctx.fixture("std.011")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.012", 'html5lib parser case 12')
def _(ctx):
    page = ctx.fixture("std.012")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.013", 'html5lib parser case 13')
def _(ctx):
    page = ctx.fixture("std.013")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.014", 'html5lib parser case 14')
def _(ctx):
    page = ctx.fixture("std.014")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.015", 'html5lib parser case 15')
def _(ctx):
    page = ctx.fixture("std.015")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.016", 'html5lib parser case 16')
def _(ctx):
    page = ctx.fixture("std.016")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.017", 'html5lib parser case 17')
def _(ctx):
    page = ctx.fixture("std.017")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.018", 'html5lib parser case 18')
def _(ctx):
    page = ctx.fixture("std.018")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.019", 'html5lib parser case 19')
def _(ctx):
    page = ctx.fixture("std.019")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.020", 'html5lib parser case 20')
def _(ctx):
    page = ctx.fixture("std.020")
    truthy(page.find("html"), "document not produced")
    truthy(page.summary["dom"]["elements"] >= 1, "empty document")

@case(18, "std.021", 'WPT case 01')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.022", 'WPT case 02')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.023", 'WPT case 03')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.024", 'WPT case 04')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.025", 'WPT case 05')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.026", 'WPT case 06')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.027", 'WPT case 07')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.028", 'WPT case 08')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.029", 'WPT case 09')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.030", 'WPT case 10')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.031", 'WPT case 11')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.032", 'WPT case 12')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.033", 'WPT case 13')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.034", 'WPT case 14')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.035", 'WPT case 15')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.036", 'WPT case 16')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.037", 'WPT case 17')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.038", 'WPT case 18')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.039", 'WPT case 19')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.040", 'WPT case 20')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.041", 'Test262 case 01')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.042", 'Test262 case 02')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.043", 'Test262 case 03')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.044", 'Test262 case 04')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.045", 'Test262 case 05')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.046", 'Test262 case 06')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.047", 'Test262 case 07')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.048", 'Test262 case 08')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.049", 'Test262 case 09')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.050", 'Test262 case 10')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.051", 'Test262 case 11')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.052", 'Test262 case 12')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.053", 'Test262 case 13')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.054", 'Test262 case 14')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.055", 'Test262 case 15')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.056", 'Test262 case 16')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.057", 'Test262 case 17')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.058", 'Test262 case 18')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.059", 'Test262 case 19')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.060", 'Test262 case 20')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.061", 'CSS Test Suite case 01')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.062", 'CSS Test Suite case 02')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.063", 'CSS Test Suite case 03')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.064", 'CSS Test Suite case 04')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.065", 'CSS Test Suite case 05')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.066", 'CSS Test Suite case 06')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.067", 'CSS Test Suite case 07')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.068", 'CSS Test Suite case 08')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.069", 'CSS Test Suite case 09')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.070", 'CSS Test Suite case 10')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.071", 'CSS Test Suite case 11')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.072", 'CSS Test Suite case 12')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.073", 'CSS Test Suite case 13')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.074", 'CSS Test Suite case 14')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.075", 'CSS Test Suite case 15')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.076", 'CSS Test Suite case 16')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.077", 'CSS Test Suite case 17')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.078", 'CSS Test Suite case 18')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.079", 'CSS Test Suite case 19')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.080", 'CSS Test Suite case 20')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.081", 'Acid3 case 01')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.082", 'Acid3 case 02')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.083", 'Acid3 case 03')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.084", 'Acid3 case 04')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.085", 'Acid3 case 05')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.086", 'Acid3 case 06')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.087", 'Acid3 case 07')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.088", 'Acid3 case 08')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.089", 'Acid3 case 09')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.090", 'Acid3 case 10')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.091", 'Acid3 case 11')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.092", 'Acid3 case 12')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.093", 'Acid3 case 13')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.094", 'Acid3 case 14')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.095", 'Acid3 case 15')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.096", 'Acid3 case 16')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.097", 'Acid3 case 17')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.098", 'Acid3 case 18')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.099", 'Acid3 case 19')
def _(ctx):
    raise Blocked("not runnable in this environment")

@case(18, "std.100", 'Acid3 case 20')
def _(ctx):
    raise Blocked("not runnable in this environment")
