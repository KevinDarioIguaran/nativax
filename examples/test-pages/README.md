# General NativaX test pages

Small, Bible-independent pages used to validate engine changes:

- `list.html`: 500 rows, scrolling, delegated click mutations.
- `form.html`: input/change/submit events.
- `animations.html`: infinite CSS animation and class toggle.

They can be opened by any NativaX host and used with the static analyzer:

```bash
python3 tools/analyze_app.py examples/test-pages
```
