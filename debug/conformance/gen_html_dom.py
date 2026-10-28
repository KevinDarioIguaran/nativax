import json
cases = []
# 10 basic valid
for i in range(10):
    cases.append({"id": f"html-basic-{i}", "html": f"<div id='d{i}'><p>para {i}</p><span>span</span></div>", "css": f"#d{i}{{padding:4px;}}"})
# 10 invalid/malformed
for i in range(10):
    cases.append({"id": f"html-invalid-{i}", "html": f"<div><p>unclosed {i}<span>text</div>", "css": ""})
# 10 limits/extremes
for i in range(10):
    cases.append({"id": f"html-limit-{i}", "html": "<div>" + ("x" * (i*100+1)) + "</div>", "css": ""})
# 10 nested/complex
for i in range(10):
    cases.append({"id": f"html-nested-{i}", "html": "<div>" + "<span>"* (i+1) + "deep" + "</span>"*(i+1) + "</div>", "css": ""})
# 10 interaction/mutation-ish (static html)
for i in range(10):
    cases.append({"id": f"html-mixed-{i}", "html": f"<section><h{i%6+1}>title</h{i%6+1}><ul><li>a</li><li>b</li></ul></section>", "css": "section{margin:8px;}"})
# total 50
assert len(cases) == 50
out = Path if False else None
from pathlib import Path
Path("debug/conformance/html_dom_50.json").write_text(json.dumps({"html_dom": cases}, indent=2))
print("generated", len(cases))
