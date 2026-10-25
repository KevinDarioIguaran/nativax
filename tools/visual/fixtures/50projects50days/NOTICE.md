# 50projects50days fixtures

Vendored, unmodified copies of the HTML/CSS/JS pages from:

- Source: https://github.com/bradtraversy/50projects50days
- Commit: `c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481`
- License: MIT (see `LICENSE` in this directory)
- Author: Brad Traversy and contributors

These pages are test fixtures only. They are not part of the NativaX runtime
and their styles or scripts are never loaded by the public API.

`_project_starter_` is kept for provenance but skipped by
`discoverPages()` because it is not one of the 50 projects.

The judge blocks external network access in both engines. Several fixtures
reference Google Fonts, CDNs and remote images; those requests fail in both
Chromium and NativaX, so the comparison covers the local HTML/CSS/JS and the
system font fallback. This is reported per page as `external-resources`.
