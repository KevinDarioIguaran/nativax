"""JSON evidence viewers: highlighted text with path spans, and a lazy tree
inspector with key/value search and schema-validation errors."""
from __future__ import annotations

import json
import tkinter as tk
from tkinter import ttk

from debug.app.components.basic import button, copy, entry, fmt, frame, label
from debug.styles import theme as t

MAX_CHARS = 1_500_000


class JsonText(tk.Frame):
    """Read-only JSON text. `spans[path] = (start, end)` character offsets."""

    def __init__(self, master, height=20):
        super().__init__(master, bg=t.color("surface-raised"))
        bar = frame(self, "surface-raised")
        bar.pack(fill="x")
        self.title = label(bar, "", surface="surface-raised")
        self.title.pack(side="left", padx=t.space("sm"))
        button(bar, "Copy JSON", lambda: copy(self, self.raw)).pack(side="right", padx=t.space("xs"))
        self.path_label = label(bar, "", role="code-small", fg="accent", surface="surface-raised")
        self.path_label.pack(side="right", padx=t.space("sm"))
        self.text = tk.Text(self, bg=t.color("surface-raised"), fg=t.color("text-primary"), relief="flat",
                            wrap="none", font=t.font("code"), height=height, padx=t.space("sm"),
                            insertbackground=t.color("text-primary"))
        ys = ttk.Scrollbar(self, orient="vertical", command=self.text.yview)
        xs = ttk.Scrollbar(self, orient="horizontal", command=self.text.xview)
        self.text.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        xs.pack(side="bottom", fill="x")
        self.text.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        for tag, token in (("key", "syntax-key"), ("str", "syntax-string"), ("num", "syntax-number"),
                           ("lit", "syntax-literal"), ("null", "syntax-null")):
            self.text.tag_configure(tag, foreground=t.color(token))
        self.text.tag_configure("hl", background=t.color("highlight"))
        self.spans: dict[str, tuple[int, int]] = {}
        self.raw = ""
        self.text.configure(state="disabled")

    def show(self, obj, title=""):
        self.spans = {}
        parts: list[tuple[str, str | None]] = []
        pos = [0]

        def put(s, tag=None):
            parts.append((s, tag))
            pos[0] += len(s)
            if pos[0] > MAX_CHARS:
                raise OverflowError

        def walk(v, path, indent):
            start = pos[0]
            pad = "  " * indent
            if isinstance(v, dict) and v:
                put("{\n")
                for i, (k, x) in enumerate(v.items()):
                    put(pad + "  ")
                    put(json.dumps(k, ensure_ascii=False), "key")
                    put(": ")
                    walk(x, f"{path}.{k}", indent + 1)
                    put(",\n" if i < len(v) - 1 else "\n")
                put(pad + "}")
            elif isinstance(v, list) and v:
                put("[\n")
                for i, x in enumerate(v):
                    put(pad + "  ")
                    walk(x, f"{path}[{i}]", indent + 1)
                    put(",\n" if i < len(v) - 1 else "\n")
                put(pad + "]")
            elif isinstance(v, (dict, list)):
                put("{}" if isinstance(v, dict) else "[]")
            elif isinstance(v, str):
                put(json.dumps(v, ensure_ascii=False), "str")
            elif v is None:
                put("null", "null")
            elif isinstance(v, bool):
                put("true" if v else "false", "lit")
            else:
                put(json.dumps(v), "num")
            self.spans[path] = (start, pos[0])

        truncated = False
        try:
            walk(obj, "$", 0)
        except OverflowError:
            truncated = True
        self.raw = json.dumps(obj, ensure_ascii=False, indent=2, default=str)
        self.text.configure(state="normal")
        self.text.delete("1.0", "end")
        for s, tag in parts:
            self.text.insert("end", s, tag or ())
        if truncated:
            self.text.insert("end", "\n… display truncated; “Copy JSON” copies the complete document.")
        self.text.configure(state="disabled")
        self.title.configure(text=title)
        self.path_label.configure(text="")

    def highlight(self, path) -> bool:
        self.text.tag_remove("hl", "1.0", "end")
        span = self.spans.get(path)
        self.path_label.configure(text=path if span else f"{path} (not present)")
        if not span:
            return False
        a, b = f"1.0 + {span[0]} chars", f"1.0 + {span[1]} chars"
        self.text.tag_add("hl", a, b)
        self.text.see(a)
        return True

    def path_at_cursor(self) -> str | None:
        counted = self.text.count("1.0", "insert", "chars")
        offset = int(counted[0]) if counted else 0
        best = None
        for path, (a, b) in self.spans.items():
            if a <= offset <= b and (best is None or b - a < best[1]):
                best = (path, b - a)
        return best[0] if best else None


class JsonTree(tk.Frame):
    """Tree inspector. Nodes are created lazily on expand, so documents with
    hundreds of thousands of values stay usable. Search walks the whole
    document (keys and values) and lists matching paths."""

    def __init__(self, master):
        super().__init__(master, bg=t.color("surface"))
        bar = frame(self)
        bar.pack(fill="x")
        label(bar, "Find key or value").pack(side="left")
        self.query = entry(bar, 28)
        self.query.pack(side="left", padx=t.space("sm"))
        self.query.bind("<Return>", lambda _e: self.find())
        button(bar, "Find", self.find).pack(side="left")
        self.status = label(bar, "")
        self.status.pack(side="left", padx=t.space("md"))
        self.errors = label(self, "", fg="status-error", justify="left", anchor="w", wraplength=1200)
        self.errors.pack(fill="x")
        panes = tk.PanedWindow(self, orient="vertical", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        holder = frame(panes)
        self.tree = ttk.Treeview(holder, columns=("value", "type"), show="tree headings")
        self.tree.heading("value", text="Value")
        self.tree.heading("type", text="Type")
        self.tree.column("#0", width=320)
        self.tree.column("value", width=520)
        self.tree.column("type", width=70)
        ys = ttk.Scrollbar(holder, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=ys.set)
        self.tree.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        panes.add(holder, height=360)
        self.hits = ttk.Treeview(panes, columns=("path", "match"), show="headings", height=6)
        self.hits.heading("path", text="Matching path")
        self.hits.heading("match", text="Match")
        self.hits.column("path", width=520)
        self.hits.column("match", width=420)
        panes.add(self.hits)
        self.tree.bind("<<TreeviewOpen>>", self._expand)
        self.hits.bind("<Double-1>", self._goto)
        self.doc = None
        self.nodes: dict[str, object] = {}

    def show(self, doc, errors=()):
        self.doc = doc
        self.nodes = {}
        self.tree.delete(*self.tree.get_children())
        self.hits.delete(*self.hits.get_children())
        self.errors.configure(text="\n".join(f"validation: {e}" for e in list(errors)[:20])
                              + (f"\n… {len(errors) - 20} more" if len(errors) > 20 else ""))
        self._insert("", "$", "$", doc)
        if self.tree.exists("$"):
            self.tree.item("$", open=True)
            self._fill("$")

    def _kind(self, v):
        return ("object" if isinstance(v, dict) else "array" if isinstance(v, list) else
                "null" if v is None else "bool" if isinstance(v, bool) else
                "number" if isinstance(v, (int, float)) else "string")

    def _insert(self, parent, path, name, value):
        self.nodes[path] = value
        container = isinstance(value, (dict, list))
        shown = (f"{len(value)} entries" if container else
                 "null" if value is None else json.dumps(value, ensure_ascii=False)[:300])
        self.tree.insert(parent, "end", iid=path, text=name, values=(shown, self._kind(value)))
        if container and value:
            self.tree.insert(path, "end", iid=path + "::ph", text="…")

    def _fill(self, path):
        ph = path + "::ph"
        if self.tree.exists(ph):
            self.tree.delete(ph)
            value = self.nodes[path]
            items = value.items() if isinstance(value, dict) else enumerate(value)
            for i, (k, v) in enumerate(items):
                if i >= 5000:
                    self.tree.insert(path, "end", iid=f"{path}::more", text=f"… {len(value) - 5000} more")
                    break
                child = f"{path}.{k}" if isinstance(value, dict) else f"{path}[{k}]"
                self._insert(path, child, str(k), v)

    def _expand(self, _e=None):
        self._fill(self.tree.focus())

    def find(self):
        q = self.query.get().strip().lower()
        self.hits.delete(*self.hits.get_children())
        if not q or self.doc is None:
            return
        found = 0
        stack = [("$", self.doc)]
        while stack and found < 2000:
            path, v = stack.pop()
            if isinstance(v, dict):
                for k, x in v.items():
                    p = f"{path}.{k}"
                    if q in str(k).lower():
                        self.hits.insert("", "end", values=(p, f"key {k}"))
                        found += 1
                    stack.append((p, x))
            elif isinstance(v, list):
                stack.extend((f"{path}[{i}]", x) for i, x in enumerate(v))
            elif q in fmt(v).lower():
                self.hits.insert("", "end", values=(path, fmt(v)[:200]))
                found += 1
        self.status.configure(text=f"{found} match(es)" + (" (first 2000)" if found >= 2000 else ""))

    def reveal(self, path: str) -> bool:
        """Expands the tree down to `path` and selects it."""
        steps, cur = [], ""
        i = 0
        while i < len(path):
            j = min([x for x in (path.find(".", i + 1), path.find("[", i + 1)) if x > 0] or [len(path)])
            cur = path[:j]
            steps.append(cur)
            i = j
        for step in steps[:-1]:
            if self.tree.exists(step):
                self.tree.item(step, open=True)
                self._fill(step)
        if self.tree.exists(path):
            self.tree.selection_set(path)
            self.tree.see(path)
            return True
        return False

    def _goto(self, _e=None):
        sel = self.hits.selection()
        if sel:
            self.reveal(self.hits.item(sel[0], "values")[0])
