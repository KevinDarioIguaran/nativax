# Architecture

Multi-worker Three.js + Rapier physics.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         MAIN THREAD                              │
│  App ─┬─ WorkerCoordinator (worker lifecycle)                   │
│       ├─ EntityCoordinator                                       │
│       │   ├─ WorldSpawner, PlayerSpawner                        │
│       │   └─ BoxSpawner, SphereSpawner                          │
│       ├─ InputRouter, AudioBridge, AudioManager                 │
│       ├─ InputManager, DebugManager, UIManager                  │
│       └─ ResizeHandler, SpawnHandler                            │
└─────────────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌───────────────┐  ┌─────────┐  ┌───────────────┐
│PHYSICS WORKER │  │ Shared  │  │ RENDER WORKER │
│  PhysicsWorld │══│ Buffer  │══│  Experience   │
│  60Hz fixed   │  └─────────┘  │  ~60Hz (rAF)  │
└───────────────┘               └───────────────┘
```

## Main Thread Modules

| Module | Responsibility |
|--------|----------------|
| WorkerCoordinator | Worker lifecycle |
| EntityCoordinator | Entity orchestration via sub-spawners |
| InputRouter | Route input → workers |
| AudioManager | Web Audio API, spatial sound |
| AudioBridge | Wire audio callbacks → AudioManager |
| UIManager | Loading screen, errors, spawner UI |
| DebugManager | Tweakpane + Stats.js |

### WorkerCoordinator

```typescript
await coordinator.init(canvas, viewport, debug, callbacks);
const physicsApi = coordinator.getPhysicsApi();
const renderApi = coordinator.getRenderApi();
coordinator.startPhysics();
coordinator.dispose();
```

### EntityCoordinator

```typescript
await entities.initWorld();
await entities.spawnBoxes([{ position: { x: 0, y: 5, z: 0 } }]);
await entities.spawnSpheres([{ position: { x: -2, y: 5, z: 0 }, radius: 0.5 }]);
await entities.clearAll();
```

Sub-spawners: WorldSpawner, PlayerSpawner, BoxSpawner, SphereSpawner.

## Design Principles

### 1. Thin Workers

Worker files = Comlink API only. Logic in domain modules.

```typescript
// workers/render.worker.ts
Comlink.expose(createRenderApi());
```

### 2. Domain-Based Organization

| Folder | Purpose |
|--------|---------|
| `renderer/` | Three.js code |
| `physics/` | Rapier code |
| `app/` | Main thread |
| `shared/` | Cross-worker contracts |
| `workers/` | Entry points only |

### 3. Experience/World/Renderer Pattern

```
Experience (orchestrator)
├── Renderer, Camera
├── World (entities + scene)
│   ├── EntityFactory
│   ├── InstancedBoxes, InstancedSpheres
│   └── Floor, Environment
├── TransformSync
└── Time, Debug, Resources
```

### 4. Centralized Config

All settings in `src/shared/config.ts`.

## Project Structure

```
src/
  app/
    index.ts                 # App
    coordinators/            # WorkerCoordinator, EntityCoordinator
    managers/                # AudioManager, InputManager, debug/
    handlers/                # ResizeHandler, SpawnHandler
    bridges/                 # AudioBridge
    routing/                 # InputRouter
    providers/               # CanvasProvider
    utils/                   # LoadProgressTracker, device-detector
    spawners/                # Box, Sphere, Player, World spawners
    ui/                      # UIManager
    components/              # UI web components
    
  renderer/
    core/                    # Experience, Renderer, Camera
    world/                   # World, Environment
    entities/                # Factory, Registry, components/
    objects/                 # InstancedMeshBase, boxes, spheres, fox
    sync/                    # TransformSync, PhysicsDebugRenderer
    systems/                 # Time, Resources, Debug, InputState, GroundRaycaster
    
  physics/
    physics-world.ts
    floating-capsule-controller.ts
    
  workers/
    render.worker.ts
    physics.worker.ts
    
  shared/
    config.ts
    debug-config.ts
    types/, buffers/, utils/
```

## Workers

### Communication

1. **Comlink RPC** - Commands/callbacks (async)
2. **SharedArrayBuffer** - High-frequency data (zero-copy)

### Adding Workers

1. Create domain: `src/audio/index.ts`
2. Create entry: `src/workers/audio.worker.ts`
3. Add types: `src/shared/types/audio-api.ts`
4. Add to WorkerCoordinator

## Entity System

See `docs/entities.md`.

```typescript
const id = createEntityId();
sharedBuffer.registerEntity(id);
await physicsApi.spawnEntity(entity, config);
await renderApi.spawnEntity(id, "player");
```

## SharedArrayBuffer Layout

```
Control: [FrameCounter, EntityCount, EntityIds...]
Timing:  [CurrentTime, PreviousTime, Interval]
Transform: [Entity0 Current(7), Entity0 Previous(7), Entity1...]
Flags: [Entity0 Flags, Entity1 Flags, ...] (grounded state)
```

Uses Atomics for thread-safe sync.

Requires COOP/COEP headers.

## Update Loop

```
Experience.update()
├─ TransformSync.update() - Read timing, interpolate
├─ World.update() - Entity lifecycle hooks
├─ Camera.update() - Follow target
└─ Renderer.render()
```

## Instanced Mesh

InstancedBoxes/InstancedSpheres extend InstancedMeshBase:
- 1 draw call per type
- O(1) removal (swap-with-last)
- Per-instance scales

## Audio System

See `docs/audio.md`.

Main thread AudioManager with spatial audio:
- Footsteps from player animation
- Collision sounds via AudioBridge
- Jump/land from player state
- Camera-based listener position

## Design System

CSS design tokens in `style.css` cascade into Shadow DOM components.

```css
/* Primitives */
--color-blue-500: #4a9eff;
--space-4: 16px;

/* Semantics */
--color-accent: var(--color-blue-500);
--color-surface: var(--color-gray-900);

/* Component tokens */
--btn-bg-active: rgba(74, 158, 255, 0.15);
```

## UI Components

| Component | Purpose |
|-----------|---------|
| LoadingScreen | Loading progress + start button |
| ErrorOverlay | Error display |
| SpawnerUI | Unified: canvas preview + popover menu (Popover API) |
| KeyboardControlsUI | Desktop: WAD/Space overlay |
| VirtualJoystick | Mobile: touch joystick (bottom-right) |
| JumpButton | Mobile: jump button (bottom-left) |
| ShapePreview | Three.js preview for spawner (80×80, main thread) |

All components use Shadow DOM and inherit design tokens from `:root`.

### SpawnerUI

Uses native Popover API for light-dismiss behavior:

```html
<button popovertarget="spawner-menu">
  <canvas class="preview-canvas"></canvas>
</button>
<div id="spawner-menu" popover>
  <!-- Segmented shape toggle + size slider -->
</div>
```

- Canvas preview IS the button
- Segmented control toggle (cube | sphere icons with sliding indicator)
- Works on both desktop and mobile

## Mobile Touch Controls

On touch devices, the UI switches to mobile-optimized controls:

- **VirtualJoystick** - Circular touch joystick with analog turning
  - Distance > 70% triggers sprint (orange visual feedback)
  - Analog `turnAxis` (-1 to 1) with 1.5 power curve for precision
  - Gentle push = slow turn, full push = full turn speed
- **JumpButton** - Simple touch button for jumping

Device detection via `src/app/utils/device-detector.ts`. Touch input bridged to physics via `TouchInputHandler`.

## Browser Support

Required: OffscreenCanvas, SharedArrayBuffer, Popover API, ES Modules in Workers, WebGL2.

No fallback - shows error if unsupported.
