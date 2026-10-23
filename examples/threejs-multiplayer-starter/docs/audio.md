# Audio System

This document explains the audio system architecture and how to add new sound effects.

## Overview

The audio system provides spatial 3D audio for the multi-worker Three.js application, supporting:
- **Footstep sounds** - triggered by player movement
- **Collision sounds** - triggered by physics object impacts  
- **Jump/Land sounds** - triggered by player state changes
- **Spatial audio** - 3D positioned sounds synced with camera

## Architecture

```
                              MAIN THREAD
    +------------------------------------------------------------------+
    |   App                                                            |
    |    +-- AudioBridge (callback wiring)                             |
    |           +-- AudioManager (audio orchestration)                 |
    |                  +-- AudioContext (Web Audio API)                |
    |                  +-- THREE.AudioListener                         |
    |                  +-- Sound pools (footsteps, impacts)            |
    +------------------------------------------------------------------+
                    ^                         ^
         Collision/Jump/Land       Footstep/Listener Events
         (Comlink callback)        (Comlink callback)
                    |                         |
    +---------------+-------+     +-----------+-----------+
    |   PHYSICS WORKER      |     |   RENDER WORKER       |
    |   - drainCollisionEvents   |   - PlayerEntity       |
    |   - FloatingCapsule   |     |     footstep timing   |
    |     jump/land detect  |     |   - Camera position   |
    +-----------------------+     +-----------------------+
```

## Why Audio Cannot Run in a Web Worker

Unlike the Physics and Render workers, **audio must run on the main thread**. This is not a design choice—it's a fundamental browser limitation.

### Browser Limitation

`AudioContext` cannot be created in a Web Worker. This has been a [requested feature since 2012](https://github.com/WebAudio/web-audio-api/issues/16) but remains unimplemented in all major browsers.

The [Worker support proposal (#2423)](https://github.com/WebAudio/web-audio-api/issues/2423) is marked with "Priority: Urgent" status, but as of 2024, no browser has implemented it.

### What About AudioWorklet?

`AudioWorklet` DOES run in a separate thread, but it's designed for audio **processing** (DSP, effects, synthesis), not playback. It still requires an `AudioContext` to be created on the main thread first.

```
Main Thread                    AudioWorklet Thread
     │                              │
     │ ← AudioContext (required)    │
     │                              │
     │ ──► AudioWorkletNode ───────▶│ (DSP processing only)
     │                              │
```

### THREE.js Spatial Audio

Three.js's `AudioListener` and `PositionalAudio` classes are also main-thread only, as they rely on `AudioContext` internally.

### Implications for This Project

- `AudioManager` must stay on the main thread
- Audio events are sent from workers via Comlink callbacks
- Spatial audio positioning is synced via listener updates each frame
- The `AudioBridge` module wires worker events to the `AudioManager`

This architecture is correct and cannot be changed without browser support for Web Audio in workers.

## Main Thread Components

### AudioBridge

The `AudioBridge` module is a thin connector that wires worker callbacks to `AudioManager`:

```typescript
// src/app/audio-bridge.ts
export default class AudioBridge {
  private audioManager: AudioManager;

  async init(): Promise<void> {
    await this.audioManager.init();
  }

  setupCallbacks(physicsApi, renderApi): void {
    // Physics events
    physicsApi.setCollisionCallback(Comlink.proxy(event => 
      this.audioManager.onCollision(event)
    ));
    physicsApi.setPlayerStateCallback(Comlink.proxy(event => 
      // jump or land
    ));
    
    // Render events
    renderApi.setFootstepCallback(Comlink.proxy(event => 
      this.audioManager.onFootstep(event)
    ));
    renderApi.setListenerCallback(Comlink.proxy(update => 
      this.audioManager.updateListener(update)
    ));
  }

  async unlockAudio(): Promise<void> {
    await this.audioManager.resume();
  }
}
```

### AudioManager

The `AudioManager` handles all audio playback:

```typescript
// src/app/audio-manager.ts
export default class AudioManager {
  private context: AudioContext;
  private listener: THREE.AudioListener;
  private scene: THREE.Scene;
  
  private footstepPool: SoundPool;
  private collisionPool: SoundPool;
  private jumpSound: THREE.PositionalAudio;
  private landSound: THREE.PositionalAudio;
}
```

## Event Flow

### Footsteps

```
PlayerEntity.onPhysicsFrame()
    │
    │ (movement input + timing check)
    ▼
footstepCallback (Comlink proxy)
    │
    ▼
AudioBridge → AudioManager.onFootstep()
    │
    ▼
SoundPool.play(playerPosition)
```

Footsteps are triggered based on:
- Whether player is moving (WASD keys)
- Timing interval (walk: 400ms, run: 250ms)
- Movement intensity (walk: 0.6, run: 1.0)

### Collisions

```
PhysicsWorld.step()
    │
    ▼
world.step(eventQueue)
    │
    ▼
drainCollisionEvents()
    │
    │ (filter by impulse threshold)
    ▼
collisionCallback (Comlink proxy)
    │
    ▼
AudioBridge → AudioManager.onCollision()
    │
    ▼
SoundPool.play(collisionPosition, { volume: impulse })
```

Collisions are filtered by:
- Minimum impulse threshold (config.audio.collisions.minImpulse)
- Cooldown per entity pair (350ms)
- Per-frame limit (12 collisions max)
- Ground collisions use vertical velocity as impulse metric

### Jump/Land

```
FloatingCapsuleController.update()
    │
    ▼
detectGround() → isGrounded state
    │
    │ (state change detection)
    ▼
emitJumpEvent() / emitLandEvent()
    │
    ▼
playerStateCallback (Comlink proxy)
    │
    ▼
AudioBridge → AudioManager.onJump() / onLand()
```

### Listener Sync

```
Experience.update()
    │
    ▼
Camera.update()
    │
    ▼
emitListenerUpdate({ position, forward, up })
    │
    ▼
listenerCallback (Comlink proxy)
    │
    ▼
AudioBridge → AudioManager.updateListener()
```

The listener position syncs every frame for accurate spatial audio positioning.

## Configuration

All audio settings are in `src/shared/config.ts`:

```typescript
audio: {
  master: {
    volume: 1.0,
  },
  footsteps: {
    volume: 0.4,
    walkInterval: 400,  // ms between steps when walking
    runInterval: 250,   // ms between steps when running
    poolSize: 4,        // reusable audio sources
  },
  collisions: {
    volume: 0.4,
    minImpulse: 4.0,    // minimum collision strength (filters rolling)
    poolSize: 8,
  },
  player: {
    jumpVolume: 0.5,
    landVolume: 0.6,
    landIntensityThreshold: 2.0,  // fall speed for max volume
  },
  spatial: {
    refDistance: 5,     // distance at which volume is full
    maxDistance: 50,    // distance beyond which sound is inaudible
    rolloffFactor: 1,
  },
}
```

## Audio Assets

Place audio files in `public/audio/`:

```
public/audio/
  footstep_01.ogg
  footstep_02.ogg
  footstep_03.ogg
  impact_01.ogg
  impact_02.ogg
  jump.ogg
  land.ogg
```

The AudioManager loads these on initialization. Multiple files for the same sound type (e.g., footstep_01, footstep_02) are randomly selected for variation.

## Adding New Sound Effects

### 1. Add Audio Files

Place your `.ogg` files in `public/audio/`.

### 2. Update AudioManager

Add the new sound to the asset loading in `src/app/audio-manager.ts`:

```typescript
private async loadAssets(): Promise<void> {
  const assetGroups = [
    // ... existing assets
    {
      name: "my_new_sound",
      paths: ["audio/my_sound_01.ogg", "audio/my_sound_02.ogg"],
    },
  ];
  // ...
}
```

### 3. Create Event Type (if needed)

If you need a new event type, add it to `src/shared/types/audio.ts`:

```typescript
export interface MyNewEvent {
  type: "my_new_sound";
  entityId: EntityId;
  position: { x: number; y: number; z: number };
  // ... additional properties
}
```

### 4. Add Handler Method

Add a handler in AudioManager:

```typescript
onMyNewSound(event: MyNewEvent): void {
  if (!this.canPlay() || !this.myNewSoundPool) return;
  
  this.myNewSoundPool.play(event.position, {
    volume: event.intensity,
  });
}
```

### 5. Wire Up Callback

In `AudioBridge.setupCallbacks()`, add the new callback:

```typescript
someWorkerApi.setMyNewSoundCallback(
  Comlink.proxy((event: MyNewEvent) => {
    this.audioManager.onMyNewSound(event);
  }),
);
```

## Sound Pooling

The `SoundPool` class manages reusable `THREE.PositionalAudio` instances to prevent garbage collection stalls:

```typescript
const pool = new SoundPool(listener, scene, {
  poolSize: 4,
  volume: 0.5,
  refDistance: 5,
  maxDistance: 50,
  rolloffFactor: 1,
});

pool.setBuffers([buffer1, buffer2, buffer3]);  // Random selection
pool.play(position, { volume: 0.8, playbackRate: 1.1 });
```

Features:
- Round-robin allocation of audio sources
- Random buffer selection for variation
- Automatic slight pitch variation (0.95-1.05)
- Spatial audio with configurable rolloff

## Browser Autoplay Policy

Browsers require user interaction before playing audio. The loading screen start button satisfies this requirement:

```typescript
// In LoadingScreen component
this.loadingScreen.setOnStart(() => {
  this.audioBridge.unlockAudio();
});
```

The `unlockAudio()` method resumes the suspended AudioContext:

```typescript
async unlockAudio(): Promise<void> {
  await this.audioManager.resume();
}
```

## File Structure

```
src/
  app/
    audio-manager.ts          # Main thread audio orchestrator
    audio-bridge.ts           # Worker callback wiring
    components/
      loading-screen.ts       # Audio unlock via start button
    
  audio/
    sound-pool.ts             # Pooled PositionalAudio instances
    
  shared/
    types/
      audio.ts                # Event interfaces
    config.ts                 # Audio configuration
    
  physics/
    physics-world.ts          # Collision event draining
    floating-capsule-controller.ts  # Jump/land detection
    
  renderer/
    index.ts                  # Listener sync (Experience)
    entities/components/player.ts   # Footstep emission
```

## Debugging

1. Check browser console for audio loading errors
2. Verify AudioContext state: `audioManager.context.state`
3. Test with `#debug` URL to see entity positions
4. Add console logs in audio event handlers

Common issues:
- **No sound**: Check that audio files exist in `public/audio/`
- **Sounds don't play initially**: Click the start button on loading screen
- **Spatial audio wrong**: Verify listener position is being updated (check `updateListener` calls)
- **Rolling objects too noisy**: Increase `config.audio.collisions.minImpulse`
