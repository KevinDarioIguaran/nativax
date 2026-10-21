# Security platform matrix

NativaX solo puede declarar una plataforma como verificada si la suite se
ejecutó en ese entorno real.

| Plataforma | Build | Suite seguridad | Aislamiento OS | Estado |
|---|---|---|---|---|
| Linux x86_64 | Sí | **Sí (13 PASS / 1 FAIL / 1 SKIP)** | No | Parcial |
| Android | No | No | No | **No verificado** |
| iOS | No | No | No | **No verificado** |
| Windows | No | No | No | **No verificado** |
| macOS | No | No | No | **No verificado** |

## Diferencias que deben probarse por plataforma

- Rutas, sistema de archivos y carga de bibliotecas nativas.
- Permisos de manifiesto/entitlements y sandbox de la app.
- TLS, certificados y almacenamiento seguro.
- Hilos, isolates, pila disponible y FFI.
- Entrada táctil, teclado, foco, IME y accesibilidad.
- Ciclo de vida (suspender/reanudar, orientación, memoria).
- QuickJS/native assets en MSVC (`/experimental:c11atomics`) y iOS sin JIT.

## Regla

No se declara una plataforma “segura” por pasar tests en Linux. La ausencia de
pruebas en Android/iOS/Windows/macOS se registra como **no verificado**, no
como `PASS`.
