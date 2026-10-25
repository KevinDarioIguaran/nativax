# Rendimiento NativaX vs Chromium — última ejecución

- Fecha: 2026-10-24
- Comando: `dart run tools/perf/bin/perf.dart run --out .perf/latest` (idle real medido aparte)
- Referencia: Google Chrome 152.0.7977.82 headless; viewport 800x900; red bloqueada; animaciones congeladas
- Escenarios medidos: **17 de 245 definidos** — PASS **5**, WARN **2**, FAIL **10**, INVALID **0** (última pasada)
- En tres pasadas completas el reparto fue **4–5 PASS, 2–4 WARN, 9–10 FAIL**; los veredictos de DOM/scroll se mantienen, pero los ms absolutos cambian. No tomar una sola pasada como FPS.
- Objetivos: frame p95 ≤ 16,7 ms; frame máximo ≤ 100 ms; trabajo ≤ 3× Chromium; app idle ≤ 250 MB y ≤ 1 % CPU

## App de escritorio en reposo (página blanca)

| Métrica | Valor | Objetivo | Estado |
|---|---:|---:|---|
| RSS en reposo | **105.0 MB** | ≤ 250 MB | OK |
| CPU en reposo | **0.00 %** | ≤ 1 % | OK |
| RSS pico durante la medición | 106.5 MB | — | — |
| CPU pico durante la medición | 25.45 % | — | — |
| GPU | no expuesta por el kernel | — | — |

Es el **proceso real de la app Flutter Linux**, no el arnés `flutter test`. El `idle.blank` de la tabla es el arnés offscreen (incluye el test runner); no decide el objetivo de 250 MB.

## Tabla de escenarios medidos

| Escenario | Veredicto | NativaX ms | Chromium ms | Cociente | Nodos N/C | Frame p95 | Frame max |
|---|---|---:|---:|---:|---:|---:|---:|
| `idle.blank` | PASS | 0.0 | 0.0 | — | 7/7 | — | — |
| `dom.rows-create-1k` | FAIL | 512.0 | 31.4 | 16.33x | 1008/1008 | 130.6 | 130.6 |
| `dom.rows-create-10k` | FAIL | — | 263.1 | — | — | — | — |
| `dom.rows-update-10k` | FAIL | — | 29.0 | — | — | — | — |
| `dom.rows-remove-10k` | WARN | 161.5 | 6.7 | 23.96x | 8/8 | 98.7 | 98.7 |
| `scroll.rows-10k` | FAIL | 2357.5 | 1.2 | 1964.60x* | 10008/10008 | 199.0 | 234.0 |
| `scroll.2d-tiles` | PASS | 192.8 | 1.2 | 160.69x* | 908/908 | 8.5 | 74.1 |
| `js.arrays` | PASS | 108.1 | 45.7 | 2.37x | 8/8 | 4.6 | 4.6 |
| `js.objects` | PASS | 46.3 | 16.3 | 2.84x | 8/8 | 5.2 | 5.2 |
| `js.strings` | PASS | 20.3 | 13.8 | 1.47x | 8/8 | 5.1 | 5.1 |
| `js.json` | WARN | 133.9 | 36.0 | 3.72x | 8/8 | 4.9 | 4.9 |
| `external.browserbench-quick` | FAIL | 14780.1 | 11281.4 | 1.31x | 0/16917 | 1330.0 | 1330.0 |
| `external.jsfb-create-1k` | FAIL | 3723.4 | 118.0 | 31.55x | 8031/8031 | 272.6 | 272.6 |
| `external.jsfb-create-10k` | FAIL | — | 1313.2 | — | — | 3.0 | 87.2 |
| `external.jsfb-clear` | FAIL | — | 250.1 | — | — | — | — |
| `external.cerious-load-scroll` | FAIL | 149.7 | 0.2 | 748.62x | 416/721 | 27.9 | 49.9 |
| `external.uibench-load-scroll` | FAIL | 11.4 | 0.5 | 22.75x | 13/153 | 0.2 | 4.1 |

`*` En scroll el cociente es informativo: el compositor de Chromium puede tardar <1 ms y el objetivo real es frame p95/máximo.

## Hallazgos (estables entre pasadas)

- **JS puro a la altura**: arrays, objects y strings pasan; json oscila entre PASS y WARN. QuickJS no es el cuello de botella de CPU.
- **Crear filas**: 1.000 filas 4–16× más lentas según la pasada; 10.000 filas acaban en timeout del presupuesto JS o 6,6–8,2 s.
- **Actualizar/limpiar 10.000 filas**: el presupuesto de ejecución de QuickJS se agota en una sola llamada.
- **Scroll de 10.000 filas**: p95 108–234 ms y frames de 128–234 ms; la UI se traba.
- **Scroll 2D de 900 teselas**: p95 6,8–8,4 ms y nodos idénticos; el pipeline puede ser fluido.
- **js-framework-benchmark vanilla 1k**: 13,6×–31,5× y frame de ~170–190 ms; 10k no completa.
- **Browser-Bench Quick**: Chromium termina con ~31.000 puntos; NativaX o no completa o deja un frame de ~1,3 s.
- **Cerious / uibench**: 416 vs 721 nodos y 13 vs 153; las librerías no inicializan igual.

## Cómo leerlo

- `Trabajo = escenario + render/frame`. El frame de Chromium es layout/style del hilo principal (CDP); el de NativaX es `tester.pump()` offscreen. Son relojes distintos: el cociente es una señal de regresión, no FPS.
- Los frames offscreen son CPU (build/layout/paint), no rasterización GPU ni refresco de pantalla.
- El heap solo lo reporta Chromium. La GPU no está expuesta en esta máquina; no se inventa un valor.

## Reproducir

```bash
dart run tools/perf/bin/perf.dart run --app-idle --out .perf/latest
python3 tools/perf/gui/perf_gui.py
```
