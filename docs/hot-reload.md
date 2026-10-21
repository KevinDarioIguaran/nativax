# Hot reload de documento

`NativaXHotReloadView` es una herramienta de desarrollo: lee un archivo HTML,
lo renderiza y lo vuelve a cargar cuando el archivo cambia.

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: NativaXHotReloadView(
        sourcePath: 'dev/ui.html',
      ),
    ),
  ));
}
```

El archivo puede contener HTML, CSS y JavaScript:

```html
<style>
  body { font-family: sans-serif }
  button { padding: 8px 16px }
</style>
<button id="b">0</button>
<script>
  let n = 0;
  document.getElementById('b').addEventListener('click', () => {
    n += 1;
    document.getElementById('b').textContent = String(n);
  });
</script>
```

## Qué hace

- Vigila el **directorio** del archivo (los editores suelen guardar con
  rename) y filtra por nombre.
- Debounce de 80 ms para no recargar a mitad de una escritura.
- Relee el archivo de forma síncrona (solo desarrollo) y crea un
  `NativaXRuntime` nuevo.
- Mantiene el runtime anterior si la lectura falla y reporta el error por
  `onError`.

## Qué no hace

Es un **hot reload de documento**, no un parche del realm de JavaScript:

- No conserva variables ni estado de los scripts.
- No conserva el foco, el scroll ni el estado de los controles.
- No hace HMR de módulos.

Es equivalente a un “hot restart” del documento. Para conservar estado de la
aplicación, usa `onBeforeReload`/`onAfterReload` y guárdalo fuera del runtime
(por ejemplo en el host Dart).

## Control manual

```dart
final controller = NativaXHotReloadController();

NativaXHotReloadView(
  sourcePath: 'dev/ui.html',
  controller: controller,
);

// Desde un botón o un test:
await controller.reload();
```

El controlador expone `revision`, `isReloading` y `lastError`.

## Limitaciones

- Requiere `dart:io`; no está pensado para Flutter web.
- El watcher depende del sistema (inotify en Linux). Si el sistema no lo
  soporta, el control manual sigue funcionando.
- No usar en producción: releer el archivo en cada cambio es una herramienta
  de desarrollo.
