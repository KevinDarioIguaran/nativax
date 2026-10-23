# Entity System

Factory + registry pattern for extensible entity types.

## Overview

```
EntityRegistry: "player" → createPlayerEntity()
                "ground" → createGroundEntity()
                     ↓
EntityFactory.create(id, "player") → PlayerEntity
```

## Main Thread Coordination

```
EntityCoordinator
├── WorldSpawner  (ground/terrain)
├── PlayerSpawner (player character)
├── BoxSpawner    (instanced boxes)
└── SphereSpawner (instanced spheres)
     ↓
PhysicsApi + RenderApi + SharedBuffer
```

### Instanced Entities

Boxes/spheres use InstancedMesh for performance:

```typescript
await boxSpawner.spawnBatch([
  { position: { x: 0, y: 5, z: 0 } },
  { position: { x: 1, y: 5, z: 0 }, size: { x: 1.5, y: 1.5, z: 1.5 } },
]);
```

Benefits: 1 draw call, O(1) removal, per-instance scales.

## Directory Structure

```
src/app/
  coordinators/entity-coordinator.ts
  spawners/
    world-spawner.ts
    player-spawner.ts
    box-spawner.ts
    sphere-spawner.ts

src/renderer/
  entities/
    types.ts
    index.ts              # Factory + Registry
    components/
      player.ts
      ground.ts
      static-mesh.ts
  objects/
    instanced-mesh-base.ts
    instanced-boxes.ts
    instanced-spheres.ts
```

## RenderComponent Interface

```typescript
interface RenderComponent {
  readonly id: EntityId;
  readonly type: string;
  readonly object: THREE.Object3D;
  readonly mixer?: THREE.AnimationMixer;
  
  onTransformUpdate?(pos, quat): void;
  onPhysicsFrame?(inputState): void;
  onRenderFrame?(delta, elapsed): void;
  dispose(): void;
}
```

## Lifecycle Hooks

| Hook | When | Use |
|------|------|-----|
| `onTransformUpdate` | After interpolated transform | Custom transform logic |
| `onPhysicsFrame` | New physics data (~60Hz) | Animation state |
| `onRenderFrame` | Every render frame | Shader uniforms |
| `dispose` | Entity removed | Cleanup |

## Adding Entity Types

### 1. Create Component

```typescript
// renderer/entities/components/tree.ts
export function createTreeEntity(id, context, data?): RenderComponent {
  const mesh = new THREE.Mesh(geometry, material);
  context.scene.add(mesh);
  
  return {
    id,
    type: "tree",
    object: mesh,
    onRenderFrame(delta, elapsed) { /* animate */ },
    dispose() { /* cleanup */ },
  };
}
```

### 2. Register

```typescript
// renderer/entities/index.ts
entityRegistry.register("tree", createTreeEntity);
```

### 3. Spawn

```typescript
const id = createEntityId();
sharedBuffer.registerEntity(id);
await physicsApi.spawnEntity(entity, config);
await renderApi.spawnEntity(id, "tree");
```

## Entities vs Objects

| | Entities | Objects |
|-|----------|---------|
| Location | `entities/` | `objects/` |
| Physics sync | Yes | No |
| Lifecycle hooks | Yes | No |
| Managed by | EntityFactory | Manual |

**Entities**: physics-synced, dynamic spawn/despawn.
**Objects**: static decoration, always present.

## Troubleshooting

- **Not appearing**: Check registry, verify `registerEntity()` before spawn
- **Animations not playing**: Set `mixer`, update state in `onPhysicsFrame`
- **Transform not updating**: Verify ID match, check `rebuildEntityMap()` called
