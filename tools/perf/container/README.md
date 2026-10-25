# Per-container performance runs

The benchmark suite can run inside a Docker container with hard CPU and RAM
limits, so the browser and NativaX are isolated together.

```bash
# One configuration
tools/perf/container/run.sh --cpus 1 --memory 1g --name low \
  --only 'js.arrays|dom.rows-create-1k'

# Three configurations + summary
tools/perf/container/matrix.sh
```

The first run builds `nativa-perf:local` (Debian trixie + Chromium + build
tools). Flutter and the repository are **mounted at their real host paths**,
because `package_config.json` and the Flutter SDK use absolute paths. The
container runs with:

- `--network none`
- `--cpus` and `--memory` (Docker cgroup limits)
- `--shm-size 1g`
- the host UID/GID, so results are writable
- `NATIVAX_PERF_NO_SANDBOX=1` for Chromium inside the container

Results land in `.perf/container/<name>/` and the matrix summary in
`.perf/container/matrix.{json,md}`. Open it from the **Contenedores** tab in
the Tkinter dashboard. The tab has CPU (0.25–4), RAM (512 MB–4 GB), name and
scenario controls, plus the fixed matrix. The RSS column is labelled **RSS
arnés / RAM** and includes the Docker limit (for example `714 / 2048 MB`).

The RSS numbers include the `flutter test` runner (694–720 MB), not the app.
The real app idle is measured outside the container: **105 MB / 0.00 % CPU**.

Limits: these are cgroup CPU quotas, not real CPU frequency changes. There are
no concurrent CPU stressors or long soak tests, and the visual judge still runs
at rest.
