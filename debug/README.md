# NativaX Native Debug Laboratory

This directory contains the quality laboratory for the native C11 + Sokol
implementation of NativaX located at `/home/k3vin/Desktop/native`.

Scope:
- Native C11 runtime only.
- No Dart, Flutter, WebView, or embedded browser runtime.
- JavaScript runs through JavaScriptCore.

Primary entry point:

```bash
python3 debug/run.py doctor
python3 debug/run.py build
python3 debug/run.py test --suite smoke
python3 debug/run.py report
```

Generated artifacts are written under `debug/artifacts/` and are not source code.
`debug/artifacts/` is ignored by version control.