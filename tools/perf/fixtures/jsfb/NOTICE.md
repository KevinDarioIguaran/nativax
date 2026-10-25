# js-framework-benchmark vanilla keyed fixture

- Source: https://github.com/krausest/js-framework-benchmark
- Files: `frameworks/keyed/vanillajs/index.html`, `src/Main.js`,
  `css/currentStyle.css`, `css/main.css`, `css/bootstrap/dist/css/bootstrap.min.css`
- License: Apache-2.0 (see `LICENSE`)
- Test fixture only; NativaX does not load it from the public runtime.

The stylesheet imports were rewritten from absolute `/css/...` paths to local
relative paths so the page runs from `file://`. No workload code was changed.
