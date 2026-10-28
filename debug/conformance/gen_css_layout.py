import json
cases = []
for i in range(10):
    cases.append({"id": f"css-basic-{i}", "html": "<div class='a'>x</div>", "css": f".a{{width:{50+i*5}px;height:20px;background:#ccc;margin:4px;padding:2px;border:1px solid #000;}}"})
for i in range(10):
    cases.append({"id": f"css-flex-{i}", "html": "<div class='f'><span>a</span><span>b</span><span>c</span></div>", "css": f".f{{display:flex;gap:{i}px;}} span{{background:#eee;padding:2px;}}"})
for i in range(10):
    cases.append({"id": f"css-transform-{i}", "html": "<div class='t'>x</div>", "css": f".t{{transform:translate({i*3}px,{i*2}px) scale({1+i*0.1:.1f});opacity:{0.5+i*0.05:.2f};border-radius:{i}px;}}"})
for i in range(10):
    cases.append({"id": f"css-overflow-{i}", "html": "<div class='o'><p>long text content here</p></div>", "css": f".o{{width:{60+i*5}px;height:30px;overflow:hidden;background:#eee;}}"})
for i in range(10):
    cases.append({"id": f"css-nested-{i}", "html": "<div class='a'><div class='b'><div class='c'>deep</div></div></div>", "css": f".a{{padding:{i}px;}} .b{{margin:2px;}} .c{{color:red;font-size:{12+i}px;}}"})
assert len(cases)==50
from pathlib import Path
Path("debug/conformance/css_layout_50.json").write_text(__import__("json").dumps({"css_layout": cases}, indent=2))
print("generated", len(cases))
