# Quality gate — mejor/peor que la línea base

- Fecha: 2026-10-24T21:59:54.067519+00:00
- Veredicto: **EQUAL**
- Baseline: `/home/k3vin/Documents/nativax/progress/reports/quality-baseline.json`

## Estado actual

| Área | Métrica | Valor |
|---|---|---:|
| Visual | Páginas | 51 |
| Visual | Fidelidad media | 52.59 % |
| Visual | Posición / layout / color / diseño | 36.2 / 53.0 / 45.2 / 96.7 % |
| Visual | Píxeles ΔE>2 | 6,569,980 / 36,720,000 |
| Visual | Imágenes generadas | 153 |
| Rendimiento | Escenarios PASS/FAIL | 5 / 10 |
| Rendimiento | App idle RSS / CPU | 105.04 MB / 0.00 % |
| Compatibilidad | test262 | 97.93 % |
| Compatibilidad | html5lib | 99.26 % |
| Compatibilidad | url | 74.22 % |
| Compatibilidad | html_tree | 71.18 % |
| Compatibilidad | wpt | 70.00 % |

## Cambios frente a la base

| Área | Métrica | Antes | Ahora | Δ | Estado |
|---|---|---:|---:|---:|---|

## Regresiones

Ninguna detectada.

## Límites de esta compuerta

- Bajo carga de CPU real: los escenarios ejecutan DOM/scroll/JS, pero no lanzan estresores de CPU en paralelo, ni soak tests largos, ni concurrencia. La comparación visual se hace en reposo y con animaciones congeladas.
- GPU/FPS reales: se mide trabajo de frame en CPU y RSS/CPU; la GPU no está expuesta en esta máquina y no se reportan FPS de pantalla ni rasterización GPU.
- Vídeo, audio, canvas animado y WebGL no se juzgan.
- La red se bloquea en ambos motores para que la comparación sea reproducible.
- PassMark 2D HTML Scroll es propietario; se usa una escena equivalente.
- Los números de una pasada tienen varianza; la compuerta compara cocientes y métricas con tolerancias, no FPS.
