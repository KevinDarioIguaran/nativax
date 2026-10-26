# Glossary

Terms used precisely in NativaX documentation.

**App handler** — A named Dart callback registered in
`NativaXRuntimeConfig.appHandlers`, called from scripts as
`nativax.invoke(name, ...)`. It receives JSON-compatible values and is an
application API, not a security sandbox.

**Binding** — The JavaScript-visible web/DOM API installed by
`nativa_dom_bindings` over the host bridge. A binding is not a browser engine.

**Bridge** — The FFI host-call seam between a JavaScript engine and Dart. Raw
engines expose a native callback; the prelude wraps it; scripts see only
JSON-compatible values and integer handles.

**Computed style** — The resolved CSS values for an element after cascade,
inheritance, variables, media/supports, and defaults. The renderer reads this;
it does not parse CSS itself.

**Conformance** — A measured result from an official suite adapter
(Test262/html5lib/WPT/URL/tree). Conformance is not the same as unit tests,
visual similarity, or product completeness. `SKIP` is excluded and never counts
as compatibility.

**Contract** — A documented interface plus its guarantees and limits. A file
that merely exports a function is not a contract until its behavior and tests
are defined.

**DPR** — Device pixel ratio. NativaX defaults to 1.0 in its stable defaults;
the Flutter view can expose the host DPR, and the app can cap it.

**Engine** — The JavaScript backend: QuickJS-ng or V8. "Engine" does not mean a
CSS/HTML layout engine; those are separate layers.

**Evidence** — A reproducible artifact: command, run id, commit, environment,
result files. A sentence in a report is not evidence without those.

**Host** — The Dart/Flutter app embedding NativaX. The host owns resource
policy, network policy, images, platform services, app handlers, navigation, and
disposal.

**Implemented and verified** — Source exists and a reproducible test/measurement
passes for the claimed scope.

**Implemented, insufficiently verified** — Source exists but tests, platform
coverage, or measurements are incomplete.

**Layout host** — The renderer-side implementation of DOM geometry/scroll/focus
queries (`LayoutHost`). `NativaXDocumentView` registers itself as the document's
layout host.

**Manifest** — `manifest.json` for a benchmark run: run id, area, command,
commit, dirty state, timestamps, host, and result files. It makes a run
traceable.

**Partial** — Some behavior works; documented gaps remain. Not a synonym for
"done".

**Prelude** — JavaScript code installed before page scripts. It defines DOM,
window, and web APIs and closes over the frozen host function. The raw bridge is
removed by `harden()` before user code.

**QuickJS-ng** — The vendored portable JavaScript interpreter used by default on
mobile, for modules, workers, WebAssembly, SharedArrayBuffer, and WebGL. It has
an execution budget.

**Renderer** — `nativa_render`: CSS layout and Flutter render objects. It is not
a WebView and not a separate browser process.

**Run id** — `<UTC timestamp>-<short commit>` (for example
`20261026T024956Z-f47240e`). Used for benchmark directories and manifests.

**Runtime** — `NativaXRuntime`: one document session owning DOM, style engine,
JS engine, bindings, timers, resources, and lifecycle.

**SKIP** — A test the adapter could not execute or that is out of scope. It is
not a pass, a failure, or compatibility. It must carry a reason.

**Stable default** — A product setting that changes only deliberately: DPR 1.0,
`backdrop-filter` enabled, `GlSurfaceView` + `RawImage`, metrics opt-in.

**Status vocabulary** — implemented/verified, implemented-but-insufficiently-verified,
partial, experimental, planned, unsupported, unknown. See [`README.md`](README.md).

**Unsupported** — Deliberately absent or impossible in the current architecture.
It is not a bug report waiting for an undocumented bridge.

**V8** — Optional desktop JavaScript backend loaded from `libnx_v8.so`. It has
no module support, no host WebAssembly/SharedArrayBuffer/WebGL, and currently no
time/job/stack enforcement. It is not the default for pages with module scripts.

**Worktree** — A separate checkout of the repository. Optional for contributors;
not part of the runtime.
