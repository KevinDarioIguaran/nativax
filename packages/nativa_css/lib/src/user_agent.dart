/// NativaX's default stylesheet, modelled on the HTML rendering section of
/// the HTML standard but limited to supported properties.
const String userAgentStyleSheet = r'''
html, body, div, p, h1, h2, h3, h4, h5, h6, ul, ol, section, article,
header, footer, main, nav, aside, form, hr, blockquote, pre, figure,
figcaption, address, details, summary, dl, dt, dd, fieldset, legend, menu,
center, optgroup, dialog, hgroup, search, main, picture, figure, address,
table, thead, tbody, tfoot, caption, legend { display: block }
tr { display: flex }
td, th { display: block; padding: 1px; flex: 1 1 0 }
li, summary { display: list-item }
summary { list-style-type: none; cursor: pointer }
head, script, style, title, meta, link, template, noscript, base, datalist,
option, [hidden], dialog:not([open]), area, param, source, track { display: none }
details:not([open]) > :not(summary:first-of-type) { display: none }
dialog {
  position: absolute; left: 0; right: 0; margin: auto; border: 1.5px solid #000000;
  padding: 1em; background-color: #ffffff; color: #000000;
}
dialog:modal { position: fixed; overflow: auto; max-width: calc(100% - 6px - 2em); max-height: calc(100% - 6px - 2em) }
dialog::backdrop { background-color: rgba(0, 0, 0, 0.1) }
mark { background-color: #ffff00; color: #000000 }
sub { font-size: smaller; vertical-align: sub }
sup { font-size: smaller; vertical-align: super }
q::before { content: open-quote }
q::after { content: close-quote }
abbr[title] { text-decoration: underline dotted }
address { font-style: italic }
legend { padding-left: 2px; padding-right: 2px }
th { font-weight: bold; text-align: center }
:focus-visible { outline: auto 1px #101010 }

body { margin: 8px }
p, blockquote, figure, dl, pre { margin-top: 1em; margin-bottom: 1em }
blockquote, figure { margin-left: 40px; margin-right: 40px }
dd { margin-left: 40px }
h1 { font-size: 2em; margin-top: 0.67em; margin-bottom: 0.67em; font-weight: bold }
h2 { font-size: 1.5em; margin-top: 0.83em; margin-bottom: 0.83em; font-weight: bold }
h3 { font-size: 1.17em; margin-top: 1em; margin-bottom: 1em; font-weight: bold }
h4 { font-size: 1em; margin-top: 1.33em; margin-bottom: 1.33em; font-weight: bold }
h5 { font-size: 0.83em; margin-top: 1.67em; margin-bottom: 1.67em; font-weight: bold }
h6 { font-size: 0.67em; margin-top: 2.33em; margin-bottom: 2.33em; font-weight: bold }
strong, b, th { font-weight: bold }
em, i, cite, var, dfn { font-style: italic }
u, ins { text-decoration: underline }
s, strike, del { text-decoration: line-through }
small { font-size: smaller }
big { font-size: larger }
code, kbd, samp, pre { font-family: monospace }
pre { white-space: pre }
a { color: #0000ee; text-decoration: underline; cursor: pointer }
ul, ol, menu { margin-top: 1em; margin-bottom: 1em; padding-left: 40px }
ul ul, ol ul, ul ol, ol ol { margin-top: 0; margin-bottom: 0 }
ol { list-style-type: decimal }
ul ul, ol ul { list-style-type: circle }
hr { border: 1px solid #b0b0b0; margin-top: 0.5em; margin-bottom: 0.5em }
img { display: inline-block }
button, input, textarea, select {
  display: inline-block; font-size: 13.333px; font-family: Arial; color: #000000;
  border: 1px solid #767676; border-radius: 2px;
}
button {
  padding: 1px 6px; background-color: #efefef; cursor: pointer;
  text-align: center;
}
input, textarea { padding: 1px 2px; background-color: #ffffff; cursor: text }
select { padding: 0 0; background-color: #ffffff }
option { font-weight: normal; padding: 0 2px 1px; white-space: nowrap }
input[type=checkbox], input[type=radio] { border: none; padding: 0; background-color: transparent; margin: 3px 3px 3px 4px }
input[type=range] { border: none; padding: 0; background-color: transparent; margin: 2px }
input[type=color] { width: 50px; height: 27px; padding: 1px 2px; background-color: #efefef }
input[type=file] { border: none; padding: 0; background-color: transparent }
input[type=submit], input[type=button], input[type=reset] { padding: 1px 6px; background-color: #efefef; cursor: pointer; text-align: center }
input[type=hidden] { display: none }
input::placeholder, textarea::placeholder { color: #757575 }
textarea { white-space: pre-wrap; font-family: monospace }
fieldset { border: 1px solid #c0c0c0; padding: 0.35em 0.75em 0.625em; margin-left: 2px; margin-right: 2px }
''';
