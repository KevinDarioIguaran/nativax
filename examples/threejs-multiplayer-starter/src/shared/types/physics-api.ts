import type { EntityId, EntitySpawnData, Transform } from "./entity";
import type { CollisionCallback, PlayerStateCallback } from "./audio-events";
import type { DebugPhysicsUpdate, DebugPlayerUpdate } from "../debug-config";

// ============================================
// Physics Worker API - exposed via Comlink
// ============================================

/**
 * Physics body configuration
 */
export interface PhysicsBodyConfig {
  type: "static" | "dynamic" | "kinematic";
  colliderType: "cuboid" | "capsule" | "ball" | "heightfield";
  dimensions: { x: number; y: number; z: number }; // For cuboid
  radius?: number; // For capsule/ball
  height?: number; // For capsule
  mass?: number;
  friction?: number;
  restitution?: number;
}

// ============================================
// Debug Collider - for physics visualization
// ============================================

/**
 * Debug collider shape for visualization in render worker
 */
export type DebugColliderShape =
  | { type: "cuboid"; halfExtents: { x: number; y: number; z: number } }
  | { type: "capsule"; radius: number; halfHeight: number }
  | { type: "ball"; radius: number };

/**
 * Debug collider info passed to render worker for visualization
 */
export interface DebugCollider {
  shape: DebugColliderShape;
  /** Optional offset from the entity's position (e.g., for colliders offset from body) */
  offset?: { x: number; y: number; z: number };
}

/**
 * Floating capsule controller configuration
 *
 * Dynamic rigidbody-based controller using spring-damper forces to float above ground.
 * Provides natural physics interactions with impulse-based movement.
 * Inspired by Toyful Games' Very Very Valet and pmndrs/ecctrl.
 */
export interface FloatingCapsuleConfig {
  // Capsule dimensions
  radius: number;
  halfHeight: number;

  // Floating spring-damper system
  floatingDistance: number;
  rayLength: number;
  springStrength: number;
  springDamping: number;

  // Movement
  moveForce: number;
  sprintMultiplier: number;
  airControlMultiplier: number;
  maxVelocity: number;
  sprintMaxVelocity: number;

  // Jump
  jumpForce: number;
  coyoteTime: number;
  jumpBufferTime: number;

  // Ground detection
  groundedThreshold: number;
  slopeLimit: number;

  // Physics properties
  mass: number;
  friction: number;
  linearDamping: number;
  angularDamping: number;
}

/**
 * Movement input from main thread
 */
export interface MovementInput {
  forward: boolean;
  backward: boolean;
  left: boolean;
  right: boolean;
  jump: boolean;
  sprint: boolean;
  /** Analog turn axis for mobile joystick: -1 (full left) to 1 (full right) */
  turnAxis?: number;
}

/**
 * Shared buffer references for zero-copy transform sync
 */
export interface SharedBuffers {
  control: SharedArrayBuffer;
  transform: SharedArrayBuffer;
  timing: SharedArrayBuffer;
  flags: SharedArrayBuffer;
}

/**
 * Batch body spawn configuration
 * Per-entity sizes are passed separately via Float32Array
 */
export interface BatchBodyConfig {
  type: "box" | "sphere";
}

/**
 * Physics Worker API
 */
export interface PhysicsApi {
  /**
   * Initialize the physics world with shared buffers for transform sync
   * @param onProgress Optional callback for WASM loading progress (0-1)
   */
  init(
    gravity: { x: number; y: number; z: number },
    sharedBuffers: SharedBuffers,
    onProgress?: (progress: number) => void,
  ): Promise<void>;

  /**
   * Spawn an entity with physics body
   */
  spawnEntity(
    entity: EntitySpawnData,
    bodyConfig: PhysicsBodyConfig,
  ): Promise<void>;

  /**
   * Spawn the player character with floating capsule controller
   */
  spawnFloatingPlayer(
    id: EntityId,
    transform: Transform,
    config: FloatingCapsuleConfig,
  ): Promise<void>;

  /**
   * Remove an entity
   */
  removeEntity(id: EntityId): void;

  // ============================================
  // Batch Operations (for instanced entities)
  // ============================================

  /**
   * Spawn multiple physics bodies at once
   * Supports both boxes and spheres
   * Entity IDs must already be registered in the shared buffer
   * @param sizes Per-entity sizes: boxes = 3 floats (x,y,z), spheres = 1 float (radius)
   * @param velocities Optional initial velocities (3 floats per entity: vx, vy, vz)
   */
  spawnBodies(
    entityIds: EntityId[],
    positions: Float32Array,
    config: BatchBodyConfig,
    sizes: Float32Array,
    velocities?: Float32Array,
  ): Promise<void>;

  /**
   * Remove multiple physics bodies at once
   */
  removeBodies(entityIds: EntityId[]): Promise<void>;

  // ============================================
  // Player Control
  // ============================================

  /**
   * Update player movement input
   */
  setPlayerInput(input: MovementInput): void;

  // ============================================
  // Simulation Control
  // ============================================

  /**
   * Start the physics simulation loop
   * Transforms are written directly to SharedArrayBuffer
   */
  start(): void;

  /**
   * Pause the physics simulation
   */
  pause(): void;

  /**
   * Resume the physics simulation
   */
  resume(): void;

  /**
   * Clean up and dispose
   */
  dispose(): void;

  // ============================================
  // Audio Event Callbacks
  // ============================================

  /**
   * Set callback for collision events (for audio)
   * Called when significant physics collisions occur
   */
  setCollisionCallback(callback: CollisionCallback): void;

  /**
   * Set callback for player state events (jump/land)
   * Called when player jumps or lands
   */
  setPlayerStateCallback(callback: PlayerStateCallback): void;

  // ============================================
  // Debug Configuration (runtime tweaking)
  // ============================================

  /**
   * Update physics world config (density, gravity)
   * Applied to newly spawned bodies
   */
  updatePhysicsConfig(config: DebugPhysicsUpdate): void;

  /**
   * Update player controller config
   * Applied immediately to movement
   */
  updatePlayerConfig(config: DebugPlayerUpdate): void;
}
