# Tareas de test pendientes

Estas tareas no se pueden cerrar con tests rápidos o en esta máquina. Se dejan
como pendientes explícitas.

## Memoria y ciclo de vida
- Soak de 24–72 h con medición de RSS, heap, timers, listeners, wrappers,
  documentos y contextos.
- Medición de RSS pico de la app real con páginas pesadas.
- Controles positivo/negativo en plataformas reales.
- Pruebas de create/destroy masivo y navegación repetida.

## Plataforma
- Compilar y probar Android, iOS, Linux, Windows y macOS.
- DPI, orientación, teclado, accesibilidad, fuentes y entrada táctil.
- No afirmar soporte sin evidencia de compilación y ejecución.

## Visual
- Golden images por plataforma y tolerancias explícitas.
- Fuzzing HTML/CSS con minimización y semilla fija.
- Regresión visual con miles de nodos, texto largo, imágenes y actualizaciones.
- Comprobación de animaciones y frame stability.

## Video y juegos
- Pipeline multimedia real (decoder, audio, seek, controles).
- Ejecución del game-player Three.js completo con `NATIVAX_GAME_DPR`.
- Capturas golden de canvas por calidad.

## Arquitectura y seguridad
- Fuzzing de JS/DOM/CSS/HTML con minimización.
- Pruebas de agotamiento de RAM/CPU/descriptores.
- Carreras de carga/destrucción y reentrancia.
- Validación de licencias y dependencias.

## Conformidad
- Ejecutar las suites completas y actualizar tasas sin SKIP.
- WPT completo, no solo `dom/nodes` y `css/selectors`.

## Regla
Un test que solo aumenta un contador no cuenta como madurez. Cada tarea
pendiente necesita comando, métrica, límite y evidencia reproducible.
