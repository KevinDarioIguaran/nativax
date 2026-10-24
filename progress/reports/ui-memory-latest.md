# UI memory and startup measurements

Fecha: 2026-10-24
App: `/home/k3vin/Documents/bible/app` (Linux profile, Bible)
Framework: `1ca8f92` / `64b54c3`

## Medición

| Motor | RSS observado | CPU inicio | Nota |
|---|---:|---:|---|
| V8 | ~543 MB | 70–90 % | perfil por defecto de la app |
| QuickJS | ~344 MB | ~100 % | `NATIVAX_ENGINE=quickjs` |

V8 heap medido con `NATIVAX_TRACE_GC=1`: 183 MB antes de GC, 84 MB después.
El resto del RSS no es el heap JS: es Flutter/Dart, render objects, widgets,
DOM/CSS y fuentes.

## Objetivo 100 MB

No es alcanzable con la arquitectura actual. Incluso con QuickJS, que reduce
el motor JS, el proceso no baja de **344 MB**. El navegador comparado (~150 MB)
tiene otro modelo de memoria (motor nativo compartido, DOM nativo y sin
Flutter). Un objetivo de 100 MB exigiría cambiar la arquitectura de UI/engine,
no un parche.

Objetivo realista para esta app:

- Meta acordada: **250 MB** con QuickJS y cachés acotadas.
- QuickJS medido sin esas optimizaciones: ~344 MB; V8: ~543 MB.
- V8: ≤ 550–600 MB (más CPU/JS, menos RSS).
- 100 MB: bloqueado por el baseline de Flutter + DOM/CSS + engine.

## Cambios de esta iteración

- `@font-face`: se intentó cargar sólo familias usadas por el CSS, pero el
  filtro dejó sin glifos a Font Awesome. Se revirtió en el árbol de trabajo:
  por ahora se cargan todas las fuentes declaradas. Un cargador perezoso
  seguro (iconos siempre incluidos) sigue pendiente.
- `ResizeObserver`/`IntersectionObserver`: polling a 10 Hz, no un
  `requestAnimationFrame` infinito.
- `:has()`: invalidación diferida y dirigida en modo lazy; no recorre todo el
  documento por cada mutación.
- Scroll virtual: no rehace `setState` mientras el rango materializado no
  cambia.
- `NATIVAX_TRACE_DRAW=1`: BUILD/LAYOUT/PAINT con elemento, padre, offset,
  tamaño, milisegundos, FLUSH_STYLE, FRAME y FRAME_SLOWEST.

## Límites

- No hay benchmark de FPS interactivo en esta corrida.
- La traza completa añade I/O y no debe usarse para medir FPS final.
- La meta de 100 MB no se declara cumplida.
