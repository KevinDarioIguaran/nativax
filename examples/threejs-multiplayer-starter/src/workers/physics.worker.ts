/**
 * Physics Worker Entry Point
 *
 * Implements the PhysicsApi interface by delegating to PhysicsWorld.
 * This separation keeps the API factory at the worker boundary while
 * the domain logic lives in the physics module.
 */
import * as Comlink from "comlink";
import { SharedTransformBuffer } from "~/shared/buffers";
import type {
  PhysicsApi,
  EntityId,
  Transform,
  PhysicsBodyConfig,
  FloatingCapsuleConfig,
  MovementInput,
  EntitySpawnData,
  SharedBuffers,
  CollisionCallback,
  PlayerStateCallback,
  BatchBodyConfig,
} from "~/shared/types";
import type { DebugPhysicsUpdate, DebugPlayerUpdate } from "~/shared/debug-config";
import { assertInitialized, assertValidEntityId } from "~/shared/validation";
import { PhysicsWorld } from "../physics";

/**
 * Creates the PhysicsApi implementation
 *
 * The API wraps the PhysicsWorld class and handles:
 * - Lazy initialization (world created on init())
 * - SharedArrayBuffer wrapping
 * - Method delegation to PhysicsWorld instance
 * - Input validation at worker boundary
 */
function createPhysicsApi(): PhysicsApi {
  let physicsWorld: PhysicsWorld | null = null;
  let sharedBuffer: SharedTransformBuffer | null = null;

  /**
   * Assert that PhysicsWorld is initialized
   * @throws Error if physicsWorld is null
   */
  const assertPhysicsInitialized = (): PhysicsWorld => {
    assertInitialized(physicsWorld, "PhysicsWorld", "PhysicsApi");
    return physicsWorld;
  };

  return {
    async init(
      gravity: { x: number; y: number; z: number },
      sharedBuffers: SharedBuffers,
      onProgress?: (progress: number) => void,
    ): Promise<void> {
      // Warn if already initialized
      if (physicsWorld) {
        console.warn(
          "[PhysicsApi.init] Already initialized. Disposing and reinitializing.",
        );
        physicsWorld.dispose();
      }

      sharedBuffer = new SharedTransformBuffer(
        sharedBuffers.control,
        sharedBuffers.transform,
        sharedBuffers.timing,
        sharedBuffers.flags,
      );

      physicsWorld = new PhysicsWorld();
      await physicsWorld.init(gravity, sharedBuffer, onProgress);
    },

    async spawnEntity(
      entity: EntitySpawnData,
      bodyConfig: PhysicsBodyConfig,
    ): Promise<void> {
      assertValidEntityId(entity.id, "PhysicsApi.spawnEntity");
      assertPhysicsInitialized().spawnEntity(
        entity.id,
        entity.transform,
        bodyConfig,
      );
    },

    async spawnFloatingPlayer(
      id: EntityId,
      transform: Transform,
      controllerConfig: FloatingCapsuleConfig,
    ): Promise<void> {
      assertValidEntityId(id, "PhysicsApi.spawnFloatingPlayer");
      assertPhysicsInitialized().spawnFloatingPlayer(
        id,
        transform,
        controllerConfig,
      );
    },

    removeEntity(id: EntityId): void {
      assertValidEntityId(id, "PhysicsApi.removeEntity");
      assertPhysicsInitialized().removeEntity(id);
    },

    // ============================================
    // Batch Operations
    // ============================================

    async spawnBodies(
      entityIds: EntityId[],
      positions: Float32Array,
      config: BatchBodyConfig,
      sizes: Float32Array,
      velocities?: Float32Array,
    ): Promise<void> {
      for (const id of entityIds) {
        assertValidEntityId(id, "PhysicsApi.spawnBodies");
      }
      assertPhysicsInitialized().spawnBodies(
        entityIds,
        positions,
        config,
        sizes,
        velocities,
      );
    },

    async removeBodies(entityIds: EntityId[]): Promise<void> {
      for (const id of entityIds) {
        assertValidEntityId(id, "PhysicsApi.removeBodies");
      }
      assertPhysicsInitialized().removeBodies(entityIds);
    },

    // ============================================
    // Player Control
    // ============================================

    setPlayerInput(input: MovementInput): void {
      assertPhysicsInitialized().setPlayerInput(input);
    },

    // ============================================
    // Simulation Control
    // ============================================

    start(): void {
      assertPhysicsInitialized().start();
    },

    pause(): void {
      physicsWorld?.pause();
    },

    resume(): void {
      physicsWorld?.resume();
    },

    dispose(): void {
      physicsWorld?.dispose();
      physicsWorld = null;
    },

    // ============================================
    // Audio Callbacks
    // ============================================

    setCollisionCallback(callback: CollisionCallback): void {
      assertPhysicsInitialized().setCollisionCallback(callback);
    },

    setPlayerStateCallback(callback: PlayerStateCallback): void {
      assertPhysicsInitialized().setPlayerStateCallback(callback);
    },

    // ============================================
    // Debug Configuration
    // ============================================

    updatePhysicsConfig(config: DebugPhysicsUpdate): void {
      assertPhysicsInitialized().updatePhysicsConfig(config);
    },

    updatePlayerConfig(config: DebugPlayerUpdate): void {
      assertPhysicsInitialized().updatePlayerConfig(config);
    },
  };
}

Comlink.expose(createPhysicsApi());
