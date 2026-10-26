# IDEA MAESTRA: DISEÑO E IMPLEMENTACIÓN DE NATIVAX

> Este documento conserva la **idea maestra original** del proyecto. Se mantiene
> como referencia histórica; no es una instrucción activa para los agentes ni
> una tarea pendiente.

## 1. Idea original

La idea original era construir **NativaX**: un mini framework experimental de
interfaz multiplataforma escrito principalmente en Dart, compatible con Flutter,
capaz de interpretar HTML, CSS y JavaScript y presentar interfaces mediante
widgets Flutter nativos, sin utilizar un navegador incrustado, WebView,
Chromium ni otro motor de navegador completo.

La idea no era producir un prototipo visual, una demostración conceptual o una
colección de archivos vacíos, sino una base técnica funcional, verificable,
modular y extensible, trabajando directamente sobre el repositorio disponible y
respetando su estado, archivos, dependencias y convenciones.

---

## 2. Identidad y objetivo del framework

Nombre del proyecto: `NativaX`

Nombre del paquete Dart: `nativax`

Descripción:

NativaX es un framework de interfaz declarativa basado en tecnologías web, implementado en Dart, que transforma documentos HTML, reglas CSS y código JavaScript en una interfaz renderizada mediante Flutter.

Objetivos principales:

1. Permitir definir interfaces mediante HTML.
2. Aplicar estilos mediante un subconjunto documentado de CSS.
3. Ejecutar JavaScript mediante un motor de JavaScript integrado, sin navegador.
4. Transformar el documento y sus estilos en un árbol de renderizado propio.
5. Convertir ese árbol en widgets Flutter.
6. Permitir eventos, estado, formularios, navegación y manipulación del documento.
7. Facilitar el desarrollo de aplicaciones con una base de código compartida.
8. Mantener una arquitectura modular que permita ampliar progresivamente la compatibilidad con HTML, CSS y JavaScript.

Plataformas objetivo:

- Android.
- iOS.
- Linux.
- Windows.
- macOS como plataforma adicional cuando la arquitectura lo permita.

NativaX no debe presentarse como un navegador ni como un motor web completamente compatible con los estándares WHATWG y W3C. Debe declararse como un runtime de interfaz basado en tecnologías web con compatibilidad explícitamente delimitada.

---

## 3. Restricciones arquitectónicas obligatorias

### 3.1. Prohibiciones

No utilizar:

- WebView.
- `webview_flutter`.
- `flutter_inappwebview`.
- Chromium o CEF.
- Electron.
- Un navegador externo como mecanismo de renderizado.
- Un servidor HTTP local que abra una página web para mostrar la interfaz.
- Una imagen capturada de HTML como sustituto de una interfaz interactiva.
- Un parser HTML mediante expresiones regulares como solución general.
- Un intérprete JavaScript ficticio que solo reconozca unas pocas instrucciones mediante búsquedas de texto.
- Código de ejemplo presentado como si fuera una implementación completa.
- Dependencias abandonadas sin una evaluación documentada.
- Interfaces simuladas que aparenten soportar características no implementadas.

El framework puede utilizar bibliotecas especializadas para parsing, análisis sintáctico y ejecución de JavaScript, siempre que se evalúen sus licencias, mantenimiento, compatibilidad y restricciones por plataforma.

### 3.2. Qué significa renderizado nativo

La interfaz final debe representarse con widgets y primitivas de Flutter, por ejemplo:

- `Text`
- `Container`
- `Row`
- `Column`
- `Stack`
- `Flex`
- `Image`
- `GestureDetector`
- `TextField`
- `ListView`
- `SingleChildScrollView`
- `CustomPainter`, cuando sea necesario.

No basta con eliminar WebView: la interfaz debe seguir siendo interactiva, accesible y adaptable a los diferentes tamaños de pantalla.

### 3.3. Motor JavaScript

Evalúa e integra una alternativa real, preferiblemente QuickJS o JavaScriptCore, considerando:

- Android e iOS.
- Linux y Windows.
- Compatibilidad con Flutter.
- Disponibilidad de bindings Dart o posibilidad de crear un binding mediante FFI.
- Licencia.
- Compilación y distribución de bibliotecas nativas.
- Seguridad y aislamiento de ejecución.
- Coste de mantenimiento.

No asumas que un motor disponible para una plataforma funciona automáticamente en todas.

Si no existe una solución única viable, define una interfaz abstracta `JavaScriptEngine` e implementa adaptadores por plataforma.

Ejemplo conceptual:

```dart
abstract interface class JavaScriptEngine {
  Future<void> initialize();

  Future<Object?> evaluate(String source);

  Future<void> dispose();
}
```

La API definitiva debe diseñarse considerando asincronía, excepciones, conversión de tipos, callbacks y ciclo de vida.

No implementes un motor JavaScript propio desde cero. NativaX debe integrar un motor existente y concentrar el desarrollo propio en la integración con el documento y el renderizado.

---

## 4. Arquitectura general

Divide el framework en capas independientes:

1. API pública.
2. Carga y representación del documento.
3. Parser HTML.
4. Modelo DOM propio.
5. Parser CSS.
6. Cascada y cálculo de estilos.
7. Motor de layout.
8. Renderizador Flutter.
9. Runtime JavaScript.
10. DOM API accesible desde JavaScript.
11. Sistema de eventos.
12. Estado y actualizaciones reactivas.
13. Recursos e imágenes.
14. Navegación.
15. Compatibilidad por plataforma.
16. Seguridad y límites de ejecución.
17. Pruebas y herramientas de desarrollo.

Las dependencias entre módulos deben ser explícitas. Los parsers no deben depender de Flutter y el DOM no debe depender directamente del motor JavaScript.

Flujo de ejecución:

```text
HTML + CSS + JavaScript
          |
          v
   Document Loader
          |
          v
       HTML Parser
          |
          v
      DOM Document
          |
          +---------- CSS Parser
          |                 |
          |                 v
          |           CSS Rule Set
          |                 |
          +----------> Style Resolver
                            |
                            v
                       Layout Tree
                            |
                            v
                    Flutter Renderer
                            |
                            v
                    Native Flutter UI

JavaScript Engine <----> DOM Bindings
        |
        v
 Event Loop / Task Queue
        |
        v
 DOM mutations and state updates
        |
        v
 Recalculate styles / layout / render
```

Este diagrama representa la arquitectura deseada, no una afirmación de que todas las funciones ya existan.

---

## 5. Estructura de carpetas y archivos

Organiza el repositorio como un monorepo Dart/Flutter con paquetes separados.

La estructura inicial propuesta es:

```text
nativax/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── melos.yaml
├── analysis_options.yaml
├── pubspec.yaml
│
├── packages/
│   ├── nativax/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax.dart
│   │   │   └── src/
│   │   │       ├── app/
│   │   │       │   ├── nativax_app.dart
│   │   │       │   └── app_config.dart
│   │   │       ├── runtime/
│   │   │       │   ├── nativax_runtime.dart
│   │   │       │   ├── runtime_config.dart
│   │   │       │   └── runtime_errors.dart
│   │   │       ├── document/
│   │   │       │   ├── document_loader.dart
│   │   │       │   └── document_source.dart
│   │   │       ├── bridge/
│   │   │       │   ├── javascript_bridge.dart
│   │   │       │   └── value_converter.dart
│   │   │       ├── renderer/
│   │   │       │   ├── nativax_view.dart
│   │   │       │   └── renderer_factory.dart
│   │   │       ├── resources/
│   │   │       │   └── resource_loader.dart
│   │   │       └── diagnostics/
│   │   │           └── runtime_logger.dart
│   │   └── test/
│   │
│   ├── nativax_dom/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_dom.dart
│   │   │   └── src/
│   │   │       ├── document.dart
│   │   │       ├── node.dart
│   │   │       ├── element.dart
│   │   │       ├── text_node.dart
│   │   │       ├── document_fragment.dart
│   │   │       ├── attributes.dart
│   │   │       ├── selectors.dart
│   │   │       ├── mutation.dart
│   │   │       └── traversal.dart
│   │   └── test/
│   │
│   ├── nativax_html/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_html.dart
│   │   │   └── src/
│   │   │       ├── tokenizer.dart
│   │   │       ├── token.dart
│   │   │       ├── parser.dart
│   │   │       ├── parser_error.dart
│   │   │       └── fragment_parser.dart
│   │   └── test/
│   │
│   ├── nativax_css/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_css.dart
│   │   │   └── src/
│   │   │       ├── tokenizer.dart
│   │   │       ├── parser.dart
│   │   │       ├── stylesheet.dart
│   │   │       ├── css_rule.dart
│   │   │       ├── declaration.dart
│   │   │       ├── selector.dart
│   │   │       ├── specificity.dart
│   │   │       ├── cascade.dart
│   │   │       ├── computed_style.dart
│   │   │       ├── units.dart
│   │   │       ├── colors.dart
│   │   │       └── media_queries.dart
│   │   └── test/
│   │
│   ├── nativax_layout/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_layout.dart
│   │   │   └── src/
│   │   │       ├── layout_node.dart
│   │   │       ├── layout_engine.dart
│   │   │       ├── box_model.dart
│   │   │       ├── flex_layout.dart
│   │   │       ├── constraints.dart
│   │   │       └── text_metrics.dart
│   │   └── test/
│   │
│   ├── nativax_flutter/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_flutter.dart
│   │   │   └── src/
│   │   │       ├── widget_factory.dart
│   │   │       ├── element_renderer.dart
│   │   │       ├── text_renderer.dart
│   │   │       ├── image_renderer.dart
│   │   │       ├── input_renderer.dart
│   │   │       ├── flex_renderer.dart
│   │   │       └── accessibility.dart
│   │   └── test/
│   │
│   ├── nativax_js/
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── nativax_js.dart
│   │   │   └── src/
│   │   │       ├── javascript_engine.dart
│   │   │       ├── javascript_context.dart
│   │   │       ├── engine_factory.dart
│   │   │       ├── quickjs_adapter.dart
│   │   │       ├── javascript_value.dart
│   │   │       ├── event_loop.dart
│   │   │       ├── task_queue.dart
│   │   │       └── exceptions.dart
│   │   └── test/
│   │
│   └── nativax_dom_bindings/
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── nativax_dom_bindings.dart
│       │   └── src/
│       │       ├── document_binding.dart
│       │       ├── element_binding.dart
│       │       ├── event_target_binding.dart
│       │       ├── event_binding.dart
│       │       ├── style_binding.dart
│       │       └── console_binding.dart
│       └── test/
│
├── examples/
│   ├── hello_nativax/
│   ├── counter/
│   ├── todo_app/
│   ├── forms/
│   └── interactive_components/
│
├── integration_test/
│   ├── android/
│   ├── ios/
│   ├── linux/
│   └── windows/
│
├── test/
│   ├── conformance/
│   ├── performance/
│   └── security/
│
├── docs/
│   ├── architecture.md
│   ├── compatibility.md
│   ├── html-supported.md
│   ├── css-supported.md
│   ├── javascript-supported.md
│   ├── security-model.md
│   ├── api-reference.md
│   ├── troubleshooting.md
│   └── adr/
│
└── tools/
    ├── benchmark/
    ├── compatibility_report/
    └── scripts/
```

Esta estructura es una propuesta inicial. Ajusta los paquetes y archivos después de evaluar las dependencias reales, sin crear archivos innecesarios ni dejar módulos vacíos para aparentar progreso.

La raíz debe contener la configuración del monorepo. Cada paquete debe tener responsabilidades definidas, dependencias explícitas y pruebas propias.

---

## 6. Especificación del parser HTML

Implementa un parser basado en tokens y reglas sintácticas, no en expresiones regulares.

El parser debe:

1. Reconocer etiquetas de apertura y cierre.
2. Reconocer atributos con y sin comillas.
3. Procesar nodos de texto.
4. Gestionar comentarios.
5. Reconocer entidades HTML básicas.
6. Manejar elementos vacíos.
7. Construir un árbol DOM.
8. Detectar errores sintácticos.
9. Definir una estrategia de recuperación ante HTML mal formado.
10. Evitar recursión sin límites y consumo de memoria descontrolado.

Primera versión compatible:

- `html`
- `head`
- `body`
- `div`
- `span`
- `p`
- `h1` a `h6`
- `strong`
- `b`
- `em`
- `i`
- `u`
- `br`
- `hr`
- `ul`
- `ol`
- `li`
- `img`
- `a`
- `button`
- `input`
- `textarea`
- `label`
- `form`
- `select`
- `option`
- `section`
- `article`
- `header`
- `footer`
- `main`

No declares compatibilidad completa con HTML5. Documenta las diferencias respecto del algoritmo oficial de parsing de HTML y añade nuevas etiquetas conforme existan implementaciones y pruebas.

Los elementos `script` y `style` requieren tratamiento especial para evitar interpretar erróneamente sus contenidos como marcado ordinario.

---

## 7. Especificación del DOM

Implementa un modelo de objetos de documento propio.

Requisitos:

- `Document`
- `Node`
- `Element`
- `Text`
- `DocumentFragment`
- Atributos.
- Jerarquía de nodos.
- Inserción y eliminación.
- Recorrido del árbol.
- Identificadores y clases.
- Consultas por selectores.
- Eventos.
- Mutaciones observables por el runtime.
- Sincronización con el renderizador.

Primera API JavaScript:

```javascript
document.getElementById("title");

document.querySelector(".item");

document.querySelectorAll(".item");

const element = document.createElement("div");

element.textContent = "Hola desde NativaX";

document.body.appendChild(element);
```

Añade compatibilidad progresiva con:

- `getElementsByClassName`
- `getElementsByTagName`
- `setAttribute`
- `getAttribute`
- `removeAttribute`
- `appendChild`
- `removeChild`
- `replaceChild`
- `textContent`
- `innerHTML`, únicamente cuando exista un parser seguro integrado
- `classList`
- `parentNode`
- `children`
- `addEventListener`
- `removeEventListener`
- `dispatchEvent`

Define claramente qué propiedades son editables, qué métodos son síncronos y cómo se propagan las mutaciones al renderizador.

No permitas que JavaScript acceda directamente a objetos internos arbitrarios de Dart.

---

## 8. Especificación CSS

Implementa un parser CSS real y un sistema de cascada.

La primera versión debe incluir:

### Selectores

- Selector universal `*`.
- Selector de etiqueta.
- Selector de clase.
- Selector de ID.
- Combinador descendiente.
- Combinador de hijo directo.
- Selectores agrupados.
- Selectores de atributos básicos.
- Pseudoclases básicas como `:first-child`, `:last-child`, `:nth-child()` y `:not()`, cuando estén implementadas y probadas.

### Cascada

- Especificidad.
- Orden de las reglas.
- Herencia.
- Estilos predeterminados.
- Estilos en línea.
- Resolución de conflictos.
- Declaraciones inválidas.
- `!important`, con precedencia documentada.
- Separación entre estilos declarados y calculados.

### Propiedades iniciales

- `display`
- `width`
- `height`
- `min-width`
- `max-width`
- `min-height`
- `max-height`
- `margin`
- `padding`
- `border`
- `border-radius`
- `background`
- `background-color`
- `color`
- `opacity`
- `font-family`
- `font-size`
- `font-weight`
- `font-style`
- `text-align`
- `text-decoration`
- `line-height`
- `white-space`
- `overflow`
- `visibility`
- `flex-direction`
- `flex-wrap`
- `flex-grow`
- `flex-shrink`
- `flex-basis`
- `justify-content`
- `align-items`
- `align-self`
- `gap`
- `position: static`
- `position: relative`
- `position: absolute`
- `z-index`

### Unidades

- `px`
- `%`
- `em`
- `rem`
- `vw`
- `vh`

Documenta el significado de cada unidad y su conversión al sistema de layout de Flutter.

### Modelo de caja

Implementa:

- Content box.
- Padding.
- Border.
- Margin.
- Cálculo de dimensiones.
- Restricciones del contenedor.
- Resolución de porcentajes.
- Comportamiento de elementos en flujo normal.

### Flexbox

Implementa progresivamente:

- Eje principal y eje transversal.
- Distribución de espacio.
- Alineación.
- Crecimiento y reducción.
- Envoltura de elementos.
- Separación entre elementos.
- Cálculo de tamaños.

No anuncies compatibilidad completa con Flexbox hasta probar los casos relevantes.

### Media queries

Diseña una implementación inicial de `@media` para condiciones de anchura y orientación, conectada a las dimensiones disponibles de Flutter.

No implementes Grid, animaciones CSS, transformaciones ni posicionamiento complejo mediante simples aproximaciones silenciosas. Documenta cada característica ausente.

---

## 9. Renderizador Flutter

Implementa un renderizador que transforme el DOM y los estilos calculados en widgets Flutter.

Responsabilidades:

1. Resolver el widget correspondiente a cada tipo de nodo.
2. Aplicar las propiedades CSS admitidas.
3. Preservar el orden del documento.
4. Gestionar dimensiones y restricciones.
5. Representar texto con estilos y alineación.
6. Cargar imágenes con políticas seguras.
7. Gestionar formularios y controles.
8. Traducir eventos Flutter a eventos DOM.
9. Actualizar únicamente las partes necesarias del árbol.
10. Mantener estado y foco de los controles.
11. Adaptarse a distintos tamaños de pantalla.
12. Proporcionar accesibilidad básica.

Evita reconstruir innecesariamente todo el documento después de cada cambio de texto o atributo.

Implementa una estrategia de invalidación que distinga entre:

- Mutaciones estructurales.
- Cambios de atributos.
- Cambios de estilo.
- Cambios de texto.
- Cambios de dimensiones.
- Cambios de estado.

No prometas una actualización diferencial eficiente hasta medirla.

El motor de layout debe tener una única fuente de verdad para cada dimensión. Evita cálculos contradictorios entre el motor CSS y los widgets Flutter.

---

## 10. Integración de JavaScript

Integra un motor JavaScript real.

La primera versión debe soportar:

- Variables.
- Constantes.
- Funciones.
- Objetos.
- Arrays.
- Condicionales.
- Bucles.
- Operadores.
- Manejo de excepciones.
- Funciones de flecha.
- Manipulación del DOM.
- Eventos.
- Temporizadores controlados.
- `console.log`, `console.warn` y `console.error`.

El motor debe ejecutar el código JavaScript real, no traducirlo mediante sustituciones de texto.

Define el ciclo de vida del runtime, la creación de contextos, la conversión de valores y la gestión de callbacks.

### Compatibilidad con el DOM

El código debe poder utilizar:

```javascript
const button = document.querySelector("#increment");

const output = document.querySelector("#count");

let count = 0;

button.addEventListener("click", () => {
  count += 1;
  output.textContent = String(count);
});
```

Al pulsar el botón en la interfaz Flutter, el código debe ejecutarse y el texto debe actualizarse realmente.

### Funciones asíncronas

Planifica soporte progresivo para:

- Promesas.
- `async` y `await`.
- Cola de microtareas.
- Cola de tareas.
- `setTimeout`.
- `clearTimeout`.
- `setInterval`.
- `clearInterval`.

No implementes temporizadores utilizando bloqueos del hilo de interfaz.

La semántica del event loop debe documentarse. No afirmes equivalencia completa con el navegador: NativaX no tiene necesariamente `window`, `fetch`, almacenamiento web, Web Workers ni APIs de navegador.

Define expresamente qué APIs están disponibles y cuáles no.

---

## 11. Sistema de eventos

Implementa un modelo de eventos consistente.

Primera versión:

- `click`
- `input`
- `change`
- `submit`
- `focus`
- `blur`
- `keydown`
- `keyup`

Incluye progresivamente:

- Captura.
- Propagación.
- Burbujeo.
- `target`.
- `currentTarget`.
- `preventDefault`.
- `stopPropagation`.
- Gestión de listeners y su eliminación.

Los eventos de interacción deben originarse en Flutter y llegar al DOM mediante un puente controlado.

Define cómo se evitan listeners duplicados y fugas de memoria durante la reconstrucción y destrucción de componentes.

---

## 12. Carga de documentos y recursos

Permite cargar contenido desde:

- Cadenas en memoria.
- Archivos locales.
- Recursos incluidos en la aplicación.
- Paquetes de componentes.

API conceptual:

```dart
final runtime = NativaXRuntime();

await runtime.initialize();

final document = await runtime.loadHtml(
  '''
  <div class="card">
    <h1 id="title">Hola, NativaX</h1>
    <button id="action">Pulsar</button>
  </div>

  <style>
    .card {
      padding: 16px;
      background-color: #ffffff;
    }

    h1 {
      font-size: 24px;
      color: #202020;
    }
  </style>

  <script>
    document.querySelector("#action")
      .addEventListener("click", () => {
        document.querySelector("#title").textContent =
          "Funciona sin navegador";
      });
  </script>
  ''',
);

```

La API pública definitiva puede cambiar para garantizar el aislamiento del runtime y una integración correcta con Flutter.

Para recursos externos, define políticas explícitas sobre dominios permitidos, certificados TLS, tamaños máximos, redirecciones, tiempos de espera y tipos MIME.

No permitas que cualquier documento ejecute solicitudes arbitrarias o acceda a archivos locales sin autorización.

---

## 13. API pública de Flutter

La aplicación usuaria debe poder utilizar el framework de una manera sencilla.

API conceptual:

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: NativaXView(
          source: '''
            <div class="container">
              <h1>Mi aplicación</h1>
              <p>Interfaz HTML renderizada mediante Flutter.</p>
              <button id="action">Continuar</button>
            </div>
          ''',
        ),
      ),
    );
  }
}
```

Este ejemplo representa la API deseada. Implementa la clase, sus constructores y su ciclo de vida antes de presentarlo como código ejecutable.

Define:

- Inicialización.
- Destrucción.
- Carga y sustitución de documentos.
- Comunicación Dart-JavaScript.
- Eventos.
- Manejo de errores.
- Configuración de capacidades.
- Registro de diagnósticos.
- Liberación de recursos.

Evita exponer internamente todo el motor como API pública. Exporta únicamente los contratos necesarios.

---

## 14. Seguridad

Implementa una política de seguridad desde el inicio.

Requisitos:

- Aislar contextos JavaScript entre documentos cuando corresponda.
- Limitar el tiempo de ejecución de scripts.
- Limitar memoria cuando el motor lo permita.
- Prevenir bloqueos indefinidos del hilo de interfaz.
- Validar recursos externos.
- Impedir acceso arbitrario al sistema de archivos.
- No exponer objetos sensibles de Dart.
- Validar conversiones de tipos.
- Evitar la ejecución automática de scripts de documentos no confiables sin una política explícita.
- Definir permisos por capacidad.
- Evitar navegación externa implícita.
- Evitar fugas de listeners y referencias.
- Establecer límites de profundidad, nodos y tamaño del documento.
- Documentar los riesgos de FFI y de las bibliotecas nativas.

No presentes la ejecución de JavaScript como un entorno seguro simplemente porque esté integrado dentro de Flutter.

Incluye pruebas para documentos malformados, scripts excesivos, recursión, recursos de gran tamaño, ciclos de mutaciones y errores del motor.

---

## 15. Compatibilidad multiplataforma

Crea una matriz de compatibilidad real para Android, iOS, Linux, Windows y macOS.

Comprueba:

- Compilación del paquete.
- Resolución de dependencias.
- Disponibilidad del motor JavaScript.
- Configuración de FFI.
- Distribución de bibliotecas nativas.
- Arquitecturas soportadas.
- Restricciones de iOS.
- Compatibilidad con AOT de Dart.
- Carga de recursos.
- Eventos de entrada.
- Fuentes e imágenes.
- Liberación de recursos.

No marques una plataforma como compatible solo porque el código Dart analiza correctamente.

La compatibilidad requiere, como mínimo, una compilación de ejemplo y pruebas de ejecución en esa plataforma o una limitación claramente declarada cuando no exista acceso al entorno necesario.

---

## 16. Pruebas obligatorias

Construye una suite de pruebas automatizadas.

### Parser HTML

- Documento vacío.
- Etiquetas anidadas.
- Atributos.
- Texto con símbolos especiales.
- Comentarios.
- Elementos vacíos.
- Etiquetas desconocidas.
- HTML mal formado.
- Documentos demasiado grandes.

### CSS

- Selectores básicos.
- Especificidad.
- Herencia.
- Conflictos de cascada.
- Estilos en línea.
- Unidades.
- Modelo de caja.
- Flexbox.
- Media queries.
- Declaraciones inválidas.

### JavaScript y DOM

- Ejecución de expresiones.
- Funciones.
- Excepciones.
- Selección de elementos.
- Creación y eliminación de nodos.
- Eventos.
- Actualizaciones de texto.
- Promesas.
- Liberación del contexto.

### Renderizado

- Texto.
- Contenedores.
- Botones.
- Formularios.
- Imágenes.
- Layout flexible.
- Actualizaciones reactivas.
- Accesibilidad.
- Redimensionamiento.

### Integración

Construye una aplicación que permita comprobar:

1. Carga de HTML.
2. Aplicación de CSS.
3. Ejecución real de JavaScript.
4. Interacción con un botón.
5. Actualización del DOM.
6. Renderizado mediante Flutter.
7. Ausencia de WebView.
8. Compilación para las plataformas soportadas.

Los tests deben verificar resultados reales y no limitarse a comprobar que una función devuelve un valor no nulo.

---

## 17. Rendimiento y memoria

Establece benchmarks para:

- Tiempo de parsing HTML.
- Tiempo de parsing CSS.
- Creación del DOM.
- Cálculo de estilos.
- Layout.
- Renderizado inicial.
- Actualizaciones del DOM.
- Ejecución de JavaScript.
- Uso de memoria.
- Liberación de recursos.

Utiliza documentos pequeños, medianos y grandes.

Detecta:

- Reconstrucciones innecesarias.
- Complejidad cuadrática accidental.
- Fugas de memoria.
- Consultas repetidas sin caché.
- Recalculo global de estilos cuando no sea necesario.

No optimices prematuramente. Primero crea mediciones reproducibles y después implementa mejoras respaldadas por resultados.

---

## 18. Documentación

Mantén actualizados:

- `README.md`: instalación, objetivos y ejemplo mínimo.
- `docs/architecture.md`: arquitectura y flujo de datos.
- `docs/compatibility.md`: plataformas y limitaciones.
- `docs/html-supported.md`: etiquetas y atributos admitidos.
- `docs/css-supported.md`: selectores, propiedades y unidades.
- `docs/javascript-supported.md`: APIs y semántica.
- `docs/security-model.md`: límites y amenazas.
- `docs/api-reference.md`: contratos públicos.
- `docs/troubleshooting.md`: errores comunes.
- `CHANGELOG.md`: cambios relevantes.
- ADRs: decisiones arquitectónicas importantes.

Cada característica debe tener un estado explícito:

- Planificada.
- En desarrollo.
- Implementada.
- Probada.
- Experimental.
- No soportada.

No marques una característica como implementada sin código verificable y pruebas correspondientes.

---

## 19. Plan de implementación

Trabaja en fases pequeñas, verificables y acumulativas.

### Fase 0. Investigación técnica

Antes de programar:

- Inspecciona el repositorio.
- Evalúa los motores JavaScript candidatos.
- Comprueba las licencias.
- Identifica restricciones por plataforma.
- Evalúa las dependencias de parsing.
- Define la API pública.
- Documenta las decisiones técnicas.
- Identifica riesgos y dependencias bloqueantes.

No inventes resultados de pruebas o capacidades de bibliotecas.

### Fase 1. Esqueleto funcional

Implementa:

- Monorepo.
- Paquetes esenciales.
- Configuración de análisis estático.
- DOM mínimo.
- Parser HTML inicial.
- Parser CSS inicial.
- Renderizador Flutter básico.
- Aplicación de ejemplo.
- Tests unitarios.

Resultado: una interfaz con HTML y CSS se muestra mediante Flutter sin WebView.

### Fase 2. JavaScript funcional

Implementa:

- Adaptador del motor JavaScript.
- Contexto de ejecución.
- Puente DOM.
- Eventos.
- Actualizaciones reactivas.
- Ejemplo interactivo.
- Pruebas del ciclo de vida.

Resultado: un botón definido en HTML puede ejecutar JavaScript real y modificar el documento visible.

### Fase 3. Layout y CSS

Implementa:

- Cascada.
- Especificidad.
- Modelo de caja.
- Tipografía.
- Flexbox.
- Formularios.
- Imágenes.
- Adaptación de pantalla.

Resultado: páginas de complejidad moderada pueden expresarse con el subconjunto documentado de HTML y CSS.

### Fase 4. APIs y robustez

Implementa progresivamente:

- Promesas y event loop.
- Selectores adicionales.
- APIs DOM adicionales.
- Media queries.
- Manejo de errores.
- Límites de recursos.
- Seguridad.
- Diagnósticos.

Resultado: un runtime suficientemente sólido para desarrollar aplicaciones de demostración reales.

### Fase 5. Plataformas

Valida las plataformas una por una.

No anuncies compatibilidad completa con Android, iOS, Linux, Windows o macOS hasta disponer de evidencias de compilación y ejecución.

### Fase 6. Estabilización

- Ejecuta la suite completa.
- Corrige errores.
- Ejecuta benchmarks.
- Revisa licencias.
- Comprueba la ausencia de WebView.
- Documenta limitaciones.
- Publica un ejemplo reproducible.

---

## 20. Reglas estrictas de trabajo

1. Inspecciona el repositorio antes de modificarlo.
2. No sobrescribas archivos existentes sin comprender su propósito.
3. No elimines trabajo previo para simplificar la implementación.
4. No inventes APIs de dependencias.
5. No generes cientos de archivos sin funcionalidad.
6. No uses `TODO` para sustituir las funciones esenciales de una fase declarada completa.
7. No ocultes errores de parsing o ejecución.
8. No declares compatibilidad que no hayas probado.
9. No introduzcas dependencias sin justificar su utilidad.
10. No añadas complejidad sin una necesidad técnica demostrable.
11. Mantén los módulos desacoplados.
12. Ejecuta pruebas después de cada fase.
13. Corrige las regresiones antes de continuar.
14. Si una decisión requiere una dependencia nativa, documenta cómo se compila y distribuye.
15. Si una característica no es viable en una plataforma, explica el bloqueo y presenta alternativas sin fingir que funciona.
16. No sustituyas una implementación real por mocks en la aplicación final.
17. No hagas cambios destructivos ni reinicialices el repositorio.
18. Conserva las APIs públicas estables una vez documentadas.
19. Usa nombres coherentes y tipos explícitos.
20. Prioriza corrección, seguridad y mantenibilidad por encima de la cantidad de código generado.

Si existe una limitación importante, detente en el punto técnico correspondiente, documenta la evidencia y decide la siguiente acción. No ocultes la limitación con una simulación.

---

## 21. Criterios de aceptación

NativaX solo puede considerarse un prototipo funcional cuando cumpla todos los siguientes puntos:

- [ ] El proyecto compila en su entorno de desarrollo.
- [ ] Los paquetes tienen responsabilidades claras.
- [ ] El parser HTML produce un DOM verificable.
- [ ] El parser CSS produce reglas verificables.
- [ ] La cascada aplica correctamente las reglas soportadas.
- [ ] Flutter representa la interfaz sin WebView.
- [ ] El motor JavaScript ejecuta código real.
- [ ] JavaScript puede seleccionar elementos del DOM.
- [ ] JavaScript puede registrar eventos.
- [ ] Los eventos Flutter activan los listeners correspondientes.
- [ ] Las mutaciones del DOM actualizan la interfaz.
- [ ] El ciclo de vida libera los recursos correctamente.
- [ ] Las pruebas unitarias e integración pasan.
- [ ] Las limitaciones de HTML, CSS y JavaScript están documentadas.
- [ ] Las dependencias y licencias están documentadas.

La compatibilidad multiplataforma debe verificarse por separado para cada sistema operativo.

No se requiere compatibilidad total con HTML5 ni con todas las APIs de un navegador en la primera versión.

---

## 22. Entrega final

Al completar el trabajo, proporciona:

1. Resumen de la arquitectura implementada.
2. Árbol de carpetas real.
3. Lista de paquetes y responsabilidades.
4. Dependencias utilizadas y sus licencias.
5. Instrucciones reproducibles de instalación.
6. Comandos para ejecutar los tests.
7. Ejemplo funcional de HTML, CSS y JavaScript.
8. Evidencias de que la interfaz se renderiza mediante Flutter sin WebView.
9. Matriz real de compatibilidad por plataforma.
10. Resultados de pruebas y benchmarks.
11. Funciones implementadas y limitaciones pendientes.
12. Riesgos técnicos conocidos.
13. Próximos pasos priorizados.

No entregues únicamente un plan o una descripción de cómo podría construirse.

**Empieza inspeccionando el repositorio y evaluando la viabilidad técnica del motor JavaScript. Después define la arquitectura y ejecuta la primera fase funcional. Avanza de forma incremental, manteniendo el proyecto compilable y las pruebas en verde.**
