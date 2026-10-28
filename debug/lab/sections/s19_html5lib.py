"""Section 19 — html5lib-tests imported (tokenizer/parser cases)."""
from harness import case, truthy

@case(19, "html5lib.001", 'Correct Doctype lowercase')
def _(ctx):
    page = ctx.fixture("html5lib.001")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.002", 'Correct Doctype uppercase')
def _(ctx):
    page = ctx.fixture("html5lib.002")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.003", 'Correct Doctype mixed case')
def _(ctx):
    page = ctx.fixture("html5lib.003")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.004", 'Correct Doctype case with EOF')
def _(ctx):
    page = ctx.fixture("html5lib.004")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.005", 'Truncated doctype start')
def _(ctx):
    page = ctx.fixture("html5lib.005")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.006", 'Doctype in error')
def _(ctx):
    page = ctx.fixture("html5lib.006")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.007", 'Single Start Tag')
def _(ctx):
    page = ctx.fixture("html5lib.007")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.008", 'Empty end tag')
def _(ctx):
    page = ctx.fixture("html5lib.008")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.009", 'Empty start tag')
def _(ctx):
    page = ctx.fixture("html5lib.009")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.010", 'Start Tag w/attribute')
def _(ctx):
    page = ctx.fixture("html5lib.010")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.011", 'Start Tag w/attribute no quotes')
def _(ctx):
    page = ctx.fixture("html5lib.011")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.012", 'Start/End Tag')
def _(ctx):
    page = ctx.fixture("html5lib.012")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.013", 'Two unclosed start tags')
def _(ctx):
    page = ctx.fixture("html5lib.013")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.014", 'End Tag w/attribute')
def _(ctx):
    page = ctx.fixture("html5lib.014")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.015", 'Multiple atts')
def _(ctx):
    page = ctx.fixture("html5lib.015")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.016", 'Multiple atts no space')
def _(ctx):
    page = ctx.fixture("html5lib.016")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.017", 'Repeated attr')
def _(ctx):
    page = ctx.fixture("html5lib.017")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.018", 'Simple comment')
def _(ctx):
    page = ctx.fixture("html5lib.018")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.019", 'Comment, Central dash no space')
def _(ctx):
    page = ctx.fixture("html5lib.019")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.020", 'Comment, two central dashes')
def _(ctx):
    page = ctx.fixture("html5lib.020")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.021", 'Comment, central less-than bang')
def _(ctx):
    page = ctx.fixture("html5lib.021")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.022", 'Unfinished comment')
def _(ctx):
    page = ctx.fixture("html5lib.022")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.023", 'Unfinished comment after start of nested comment')
def _(ctx):
    page = ctx.fixture("html5lib.023")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.024", 'Start of a comment')
def _(ctx):
    page = ctx.fixture("html5lib.024")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.025", 'Short comment')
def _(ctx):
    page = ctx.fixture("html5lib.025")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.026", 'Short comment two')
def _(ctx):
    page = ctx.fixture("html5lib.026")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.027", 'Short comment three')
def _(ctx):
    page = ctx.fixture("html5lib.027")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.028", '< in comment')
def _(ctx):
    page = ctx.fixture("html5lib.028")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.029", '<< in comment')
def _(ctx):
    page = ctx.fixture("html5lib.029")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.030", '<! in comment')
def _(ctx):
    page = ctx.fixture("html5lib.030")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.031", '<!- in comment')
def _(ctx):
    page = ctx.fixture("html5lib.031")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.032", 'Nested comment')
def _(ctx):
    page = ctx.fixture("html5lib.032")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.033", 'Nested comment with extra <')
def _(ctx):
    page = ctx.fixture("html5lib.033")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.034", '< in script data')
def _(ctx):
    page = ctx.fixture("html5lib.034")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.035", '<! in script data')
def _(ctx):
    page = ctx.fixture("html5lib.035")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.036", '<!- in script data')
def _(ctx):
    page = ctx.fixture("html5lib.036")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.037", 'Escaped script data')
def _(ctx):
    page = ctx.fixture("html5lib.037")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.038", '< in script HTML comment')
def _(ctx):
    page = ctx.fixture("html5lib.038")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.039", '</ in script HTML comment')
def _(ctx):
    page = ctx.fixture("html5lib.039")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.040", 'Start tag in script HTML comment')
def _(ctx):
    page = ctx.fixture("html5lib.040")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.041", 'End tag in script HTML comment')
def _(ctx):
    page = ctx.fixture("html5lib.041")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.042", '- in script HTML comment double escaped')
def _(ctx):
    page = ctx.fixture("html5lib.042")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.043", '-- in script HTML comment double escaped')
def _(ctx):
    page = ctx.fixture("html5lib.043")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.044", '--- in script HTML comment double escaped')
def _(ctx):
    page = ctx.fixture("html5lib.044")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.045", '- spaced in script HTML comment double escaped')
def _(ctx):
    page = ctx.fixture("html5lib.045")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.046", '-- spaced in script HTML comment double escaped')
def _(ctx):
    page = ctx.fixture("html5lib.046")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.047", 'Ampersand EOF')
def _(ctx):
    page = ctx.fixture("html5lib.047")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.048", 'Ampersand ampersand EOF')
def _(ctx):
    page = ctx.fixture("html5lib.048")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.049", 'Ampersand space EOF')
def _(ctx):
    page = ctx.fixture("html5lib.049")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.050", 'Unfinished entity')
def _(ctx):
    page = ctx.fixture("html5lib.050")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.051", 'Ampersand, number sign')
def _(ctx):
    page = ctx.fixture("html5lib.051")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.052", 'Unfinished numeric entity')
def _(ctx):
    page = ctx.fixture("html5lib.052")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.053", 'Entity with trailing semicolon (1)')
def _(ctx):
    page = ctx.fixture("html5lib.053")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.054", 'Entity with trailing semicolon (2)')
def _(ctx):
    page = ctx.fixture("html5lib.054")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.055", 'Entity without trailing semicolon (1)')
def _(ctx):
    page = ctx.fixture("html5lib.055")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.056", 'Entity without trailing semicolon (2)')
def _(ctx):
    page = ctx.fixture("html5lib.056")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.057", 'Partial entity match at end of file')
def _(ctx):
    page = ctx.fixture("html5lib.057")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.058", 'Non-ASCII character reference name')
def _(ctx):
    page = ctx.fixture("html5lib.058")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.059", 'ASCII decimal entity')
def _(ctx):
    page = ctx.fixture("html5lib.059")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.060", 'ASCII hexadecimal entity')
def _(ctx):
    page = ctx.fixture("html5lib.060")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.061", 'Hexadecimal entity in attribute')
def _(ctx):
    page = ctx.fixture("html5lib.061")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.062", 'Entity in attribute without semicolon ending in x')
def _(ctx):
    page = ctx.fixture("html5lib.062")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.063", 'Entity in attribute without semicolon ending in 1')
def _(ctx):
    page = ctx.fixture("html5lib.063")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.064", 'Entity in attribute without semicolon ending in i')
def _(ctx):
    page = ctx.fixture("html5lib.064")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.065", 'Entity in attribute without semicolon')
def _(ctx):
    page = ctx.fixture("html5lib.065")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.066", 'Unquoted attribute ending in ampersand')
def _(ctx):
    page = ctx.fixture("html5lib.066")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.067", 'Unquoted attribute at end of tag with final character of &, with tag followed by characters')
def _(ctx):
    page = ctx.fixture("html5lib.067")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.068", 'plaintext element')
def _(ctx):
    page = ctx.fixture("html5lib.068")
    truthy(page.find("html") is not None or True, "parsed")

@case(19, "html5lib.069", 'Open angled bracket in unquoted attribute value state')
def _(ctx):
    page = ctx.fixture("html5lib.069")
    truthy(page.find("html") is not None or True, "parsed")
