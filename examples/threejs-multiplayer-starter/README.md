# Three.js Multi-Worker Starter

High-performance Three.js + Rapier physics in dedicated Web Workers. Smooth 120Hz+ visuals from 60Hz physics via timestamp interpolation over SharedArrayBuffer.

## Features

- **WebGL Rendering** - Three.js WebGLRenderer in OffscreenCanvas worker
- **Rapier Physics** - 3D rigid body simulation in dedicated worker at 60Hz
- **SharedArrayBuffer** - Zero-copy transform sync between workers
- **Timestamp Interpolation** - Smooth motion at any refresh rate
- **Floating Capsule Controller** - Spring-damper character with coyote time
- **Procedural Terrain** - Deterministic heightfield with Simplex noise
- **GPU Instancing** - 1000+ physics objects in single draw call
- **Spatial Audio** - 3D positional audio with footsteps, collisions, jump/land
- **Entity System** - Factory + registry pattern
- **TypeScript** - Full type safety with branded EntityIds
- **Debug Tools** - Tweakpane, Stats.js, physics collider visualization
- **Responsive Controls** - Desktop keyboard + mobile touch (joystick, jump button)
- **CSS Design Tokens** - Centralized design system with CSS custom properties

## Quick Start

```bash
bun install
bun run dev
```

Open `http://localhost:5173`

**Desktop:** WAD to move, Space to jump, Shift to sprint  
**Mobile:** Virtual joystick (bottom-right) with analog turning, Jump button (bottom-left)

Add `#debug` for debug controls and performance stats.

## Architecture

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

### How It Works

1. **Physics Worker** - Rapier at 60Hz, writes transforms + timestamps to SharedArrayBuffer
2. **Render Worker** - Reads transforms, interpolates between physics states
3. **Main Thread** - Input capture, audio, debug UI, worker orchestration

### Key Technologies

| Technology | Purpose |
|------------|---------|
| [Three.js](https://threejs.org/) | WebGL rendering |
| [Rapier](https://rapier.rs/) | 3D physics (WASM) |
| [SharedArrayBuffer](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer) | Zero-copy memory sharing |
| [Comlink](https://github.com/GoogleChromeLabs/comlink) | Type-safe worker RPC |
| [OffscreenCanvas](https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas) | Worker canvas rendering |
| [Popover API](https://developer.mozilla.org/en-US/docs/Web/API/Popover_API) | Native tooltip/menu UI |

## Project Structure

```
src/
  main.ts                    # Entry point
  
  app/                       # Main thread
    index.ts                 # App orchestrator
    coordinators/
      worker-coordinator.ts  # Worker lifecycle
      entity-coordinator.ts  # Entity orchestration
    managers/
      audio-manager.ts       # Web Audio API
      input-manager.ts       # DOM events
      touch-input-handler.ts # Mobile touch→input
      debug/                 # Tweakpane + Stats.js
    handlers/
      resize-handler.ts
      spawn-handler.ts
    bridges/
      audio-bridge.ts        # Audio↔worker wiring
    routing/
      input-router.ts        # Input→workers
    providers/
      canvas-provider.ts     # OffscreenCanvas
    utils/
      device-detector.ts     # Mobile/touch detection
    spawners/
      box-spawner.ts, sphere-spawner.ts
      player-spawner.ts, world-spawner.ts
    ui/
      ui-manager.ts          # UI lifecycle
    components/
      loading-screen.ts      # Loading progress + start button
      error-overlay.ts       # Error display
      spawner-ui.ts          # Unified spawner (canvas + popover)
      keyboard-controls-ui.ts # Desktop controls overlay
      virtual-joystick.ts    # Mobile joystick
      jump-button.ts         # Mobile jump
      shape-preview.ts       # Three.js spawner preview
    
  renderer/                  # Three.js (worker)
    core/
      experience.ts          # Orchestrator
      renderer.ts            # WebGLRenderer
      camera.ts              # Follow camera
    world/
      world.ts               # Entities + scene
      environment.ts         # Lighting
    entities/
      types.ts
      index.ts               # Factory + Registry
      components/            # player, ground, static-mesh
    objects/
      instanced-mesh-base.ts
      instanced-boxes.ts
      instanced-spheres.ts
      fox.ts, floor.ts
    sync/
      transform-sync.ts      # Interpolation
      physics-debug-renderer.ts
    systems/                 # time, resources, debug, input-state
    
  physics/                   # Rapier (worker)
    physics-world.ts
    floating-capsule-controller.ts
    
  workers/                   # Thin entry points
    render.worker.ts
    physics.worker.ts
    
  shared/                    # Cross-worker
    config.ts
    types/, buffers/, utils/
```

## Configuration

All settings in `src/shared/config.ts`:

```typescript
config.renderer.clearColor        // "#ffffff"
config.camera.follow.distance     // 10
config.physics.gravity            // { x: 0, y: -20, z: 0 }
config.floatingCapsule.jumpForce  // 12
config.terrain.amplitude          // 5
config.audio.footsteps.volume     // 0.4
config.spawner.projectileSpeed    // 20
```

## Design System

CSS design tokens in `style.css` with 3-layer architecture:

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

Tokens cascade into Shadow DOM components for consistent styling.

## Entity System

See [docs/entities.md](docs/entities.md).

```typescript
// Register types at startup
entityRegistry.register("player", createPlayerEntity);

// Create at runtime
const entity = await entityFactory.create(id, "player", data);
```

Lifecycle hooks: `onTransformUpdate`, `onPhysicsFrame`, `onRenderFrame`, `dispose`.

## Debug Mode

Add `#debug` to URL:

- **Tweakpane UI** - Live settings adjustment
- **Stats.js** - FPS, frame time, memory
- **Physics Colliders** - Green wireframe visualization
- **Entity Spawning** - Click to spawn boxes/spheres

## Browser Support

**Required:**
- OffscreenCanvas (Chrome 69+, Firefox 105+, Safari 16.4+)
- SharedArrayBuffer (requires COOP/COEP headers)
- Popover API (Chrome 114+, Firefox 125+, Safari 17+)
- ES Modules in Workers
- WebGL2

**No fallback** - shows error overlay if unsupported.

## Deployment

### Headers Required

SharedArrayBuffer requires Cross-Origin Isolation:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Configured in `vite.config.ts` and `vercel.json`.

## Known Issues

- **First load vibration** - Worker init race, resolves on reload
- **Movement vibration** - `setTimeout` jitter in physics. See [docs/interpolation.md](docs/interpolation.md)

## Documentation

| Doc | Content |
|-----|---------|
| [architecture.md](docs/architecture.md) | System design, adding workers |
| [entities.md](docs/entities.md) | Entity system |
| [physics.md](docs/physics.md) | Floating capsule, terrain |
| [interpolation.md](docs/interpolation.md) | Transform sync |
| [audio.md](docs/audio.md) | Spatial audio system |

## Scripts

```bash
bun run dev      # Dev server with HMR
bun run build    # TypeScript check + production build
bun run preview  # Preview production build
```

## Credits

- [Bruno Simon's Three.js Journey](https://threejs-journey.com/)
- [Toyful Games](https://www.toyfulgames.com/) / [pmndrs/ecctrl](https://github.com/pmndrs/ecctrl)
- [Glenn Fiedler's "Fix Your Timestep!"](https://gafferongames.com/post/fix_your_timestep/)

## License

MIT
