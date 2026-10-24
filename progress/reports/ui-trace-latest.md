# UI rendering trace and scroll performance

Fecha: 2026-10-24
App: `/home/k3vin/Documents/bible/app` (Bible, Linux profile build)
Framework: NativaX `cf4a278`

## Cómo capturar

```bash
cd /home/k3vin/Documents/bible/app
NATIVAX_TRACE_DRAW=1 ./run.sh > /tmp/bible-trace.log 2>&1
```

`NATIVAX_TRACE_DRAW=1` también activa `NATIVAX_TRACE_RENDER` y el perfil de layout.

## Qué significa cada línea

```text
DRAW 55ms BUILD_START nodes=1682 cache=0 hits=0 misses=0
DRAW 62ms BUILD_END construct=61ms nodes=1682 cache=0 hits=0 misses=0 layers=1 viewport=1280.0x721.0
DRAW 62ms BUILD <body...> parent=<html> ms=0.05
DRAW 149ms LAYOUT <body...> parent=<html> size=1280.0x795.0 ms=115.00
DRAW 149ms PAINT <body...> parent=<html> offset=0.0,0.0 size=1280.0x795.0 ms=...
DRAW 381ms FRAME total=386ms build=238ms raster=7ms builds=296 computes=644 styleMs=0.0
DRAW 381ms FRAME_SLOWEST | 124ms LAYOUT <body...> | 98ms LAYOUT <header...>
DRAW 561ms FLUSH_STYLE ms=6 changed=12 computes=268 subtreePasses=0
DRAW ... MUTATION childList <option> parent=<optgroup> name=
```

- `BUILD_START/END`: frame build wall time, node count, widget-cache hits/misses,
  viewport and number of fixed/modal layers.
- `BUILD`: element being converted to a widget, its parent, and build time.
- `LAYOUT`: element, parent, size, and layout time.
- `PAINT`: element, absolute offset, size, and paint time.
- `FLUSH_STYLE`: time spent recomputing dirty CSS, number of changed elements
  and compute/subtree counters.
- `FRAME`: Flutter frame total/build/raster and delta of element builds,
  CSS computes and style time.
- `FRAME_SLOWEST`: the worst eight build/layout/paint/build operations of that
  frame; this is the first place to look for the next optimization.
- `MUTATION`: DOM change and target; useful to correlate a frame with app code.

## Estado observado

En el arranque de la Biblia se midió:

```text
FRAME total=386ms build=238ms raster=7ms builds=296 computes=644
FRAME_SLOWEST | 124ms LAYOUT <body> | 98ms LAYOUT <header>
```

El cuello principal es **layout de body/header**, seguido de construcción de
widgets. Los estilos ya no se recalculan para todo el documento cuando la hoja
usa `:has()`: en el renderer perezoso se invalidan ancestros/hermanos y los
selectores afectados. La traza de arranque pasó de `computes=1676` en una
captura anterior a `computes=644` en esta; no es un benchmark equivalente y no
se presenta como speedup final.

## Scroll

`CssVirtualBlockState` ya no hace `setState` cuando el scroll se mueve dentro
de la misma ventana materializada. Se añadió una prueba:

```text
flutter test packages/nativa_render/test/virtualization_test.dart
```

que verifica que un salto de scroll dentro de la ventana no reconstruye los
elementos (`elementBuilds <= 1`).

## Límites

- No hay un benchmark reproducible de FPS interactivo en esta corrida; las
  cifras son trazas de arranque de la app real.
- El coste de layout de texto/header sigue siendo alto y es el siguiente
  objetivo.
- La traza completa imprime cada BUILD/LAYOUT/PAINT y puede reducir el FPS;
  úsala para diagnóstico, no para medir rendimiento final.
