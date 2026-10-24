# NativaX web compatibility matrix

Generated from `tools/analyze_app.py` over the reference app and
`examples/test-pages/`. This is a usage-driven matrix, not a claim of full
standards coverage.

| Area | Feature | Status | Evidence |
|---|---|---|---|
| HTML | HTML5 tree construction | yes | `package:html` parser; html5lib suite |
| HTML | templates, forms, tables, lists | yes/partial | unit + app tests |
| HTML | custom elements / shadow DOM | partial | `:host` diagnostics |
| CSS | block/flex/grid layout | yes/partial | render tests |
| CSS | selectors, pseudo-classes | partial | WPT CSS selectors |
| CSS | `@font-face`, TTF/OTF | yes | font runtime tests |
| CSS | CSS variables, transitions, keyframes | partial | animation tests |
| CSS | `:has()` | partial | targeted invalidation tests |
| DOM | nodes, attributes, classList, events | yes | nativa_dom tests |
| DOM | `elementFromPoint`, `elementsFromPoint` | yes | renderer hit-test |
| DOM | MutationObserver, Range, Selection | partial | DOM binding tests |
| DOM | fullscreen, pointer lock | no-op | app compatibility stubs |
| BOM | timers, rAF, fetch, localStorage | yes | bindings tests |
| BOM | clipboard, matchMedia, history | partial | platform services |
| BOM | Service Worker, Cache API | no | not implemented |
| BOM | `navigator.mediaDevices` | no | not implemented |
| JS | QuickJS-NG ES2023 subset | yes | engine tests |
| JS | V8 backend | not used by default | optional legacy backend |
| Build | static app analyzer | yes | `tools/analyze_app.py` |
| Build | AOT templates / bytecode | no | planned |
| Perf | virtualized long lists | yes | virtualization tests |
| Perf | incremental subtree invalidation | partial | scroll deferral + widget cache |

## Known gaps used by the analyzed apps

- `navigator.serviceWorker`, `window.caches`: stubbed/absent.
- `navigator.mediaDevices`: absent; meetings features that need camera/mic
  cannot work.
- Custom-element `:host(...)` selectors are diagnosed as unsupported.
- AOT compilation of templates/CSS and JS bytecode are not implemented.
- The QuickJS bridge still serializes host calls as JSON.
