# Phase 8 evidence — dev server, hot reload, incremental native rebuild

Date: 2026-10-28. Branch `native-c-sokol`. Environment: Linux, X11 display `:1`
(Xvfb + llvmpipe), gcc 13.3, JSC 4.1.

Executed command:

```bash
setsid ./build/nativax dev examples/counter > /tmp/nxdev.log 2>&1
```

Observed (verbatim excerpts from the run log):

```
nativax dev: serving examples/counter at http://127.0.0.1:8788
nativax dev: hot reload channel ws://127.0.0.1:8788/__nativax_ws (1 watchers)
[script] app.js ready: nodes 4
hot reload connected: ws://127.0.0.1:8788/__nativax_ws
websocket client connected (fd 5)
```

HTTP check while running: `curl -w %{http_code} http://127.0.0.1:8788/` → `200`,
`/style.css` served with its real contents.

1. CSS edit (`examples/counter/style.css` appended):

```
reload broadcast: css /style.css (1 client(s))
hot reload: css -> styles + layout rebuilt (DOM/JS state kept)
```

2. JavaScript edit (`examples/counter/app.js` appended):

```
reload broadcast: js /app.js (1 client(s))
hot reload: js -> fresh context, scripts re-run (DOM kept)
[script] app.js ready: nodes 4
```

3. Native C edit (`src/log.c` appended):

```
nativax dev: native source changed -> incremental rebuild
[14/14] Linking C executable nativax-runtime
nativax dev: relaunching app
hot reload connected: ws://127.0.0.1:8788/__nativax_ws
runtime ready: examples/counter/index.html (1024x768 css px, dpi 1.04)
```

Probe edits were reverted afterwards; the runtime rebuilt and all 12 ctest
suites passed again.

Automated coverage (no manual steps required):

- `unit_devserver`: HTTP 200/304/404, ETag, RFC 6455 handshake accept key
  (`s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` for the RFC example key), broadcast frame
  delivery, inotify-driven `css` message after editing a file.
- `unit_app`: load real HTML+CSS+JS, click hit-testing, script mutation of
  text/style, repaint delta, CSS reload with DOM preserved, JS reload with
  scripts re-executed, full document reload.

Known limits: JS heap state is dropped on JS reload (documented contract);
native changes restart the process by design; no capture-phase scripting yet.
