import RAPIER from "@dimforge/rapier3d-compat";
import type {
  EntityId,
  Transform,
  PhysicsBodyConfig,
  FloatingCapsuleConfig,
  MovementInput,
  CollisionCallback,
  PlayerStateCallback,
  BatchBodyConfig,
} from "~/shared/types";
import type {
  DebugPhysicsUpdate,
  DebugPlayerUpdate,
} from "~/shared/debug-config";
import { type SharedTransformBuffer, EntityFlags } from "~/shared/buffers";
import { config } from "~/shared/config";
import FloatingCapsuleController from "./floating-capsule-controller";
import { PhysicsEntityRegistry } from "./physics-entity-registry";
import { CollisionTracker } from "./collision-tracker";
import { BodyFactory } from "./body-factory";

/**
 * PhysicsWorld - Rapier physics simulation orchestrator
 *
 * Coordinates physics simulation, entity management, and transform sync.
 * Delegates to specialized modules:
 * - PhysicsEntityRegistry: Entity storage and lookup
 * - CollisionTracker: Collision event filtering
 * - BodyFactory: Body/collider creation
 */
export default class PhysicsWorld {
  private world: RAPIER.World | null = null;
  private eventQueue: RAPIER.EventQueue | null = null;
  private sharedBuffer: SharedTransformBuffer | null = null;
  private initialized = false;

  // Specialized modules
  private entities = new PhysicsEntityRegistry();
  private collisionTracker = new CollisionTracker();
  private bodyFactory = new BodyFactory();

  // Player controller
  private floatingController: FloatingCapsuleController | null = null;
  private playerId: EntityId | null = null;

  // Simulation loop
  private running = false;
  private lastTime = 0;
  private readonly PHYSICS_INTERVAL = config.physics.interval;

  // Player state callback (stored for late-binding to controller)
  private playerStateCallback: PlayerStateCallback | null = null;

  async init(
    gravity: { x: number; y: number; z: number },
    sharedBuffer: SharedTransformBuffer,
    onProgress?: (progress: number) => void,
  ): Promise<void> {
    this.sharedBuffer = sharedBuffer;

    onProgress?.(0);
    await RAPIER.init();
    onProgress?.(1);

    this.world = new RAPIER.World(gravity);
    this.eventQueue = new RAPIER.EventQueue(true);
    this.initialized = true;
  }

  private ensureInitialized(): {
    world: RAPIER.World;
    sharedBuffer: SharedTransformBuffer;
    eventQueue: RAPIER.EventQueue;
  } {
    if (
      !this.initialized ||
      !this.world ||
      !this.sharedBuffer ||
      !this.eventQueue
    ) {
      throw new Error("PhysicsWorld not initialized - call init() first");
    }
    return {
      world: this.world,
      sharedBuffer: this.sharedBuffer,
      eventQueue: this.eventQueue,
    };
  }

  spawnEntity(
    entityId: EntityId,
    transform: Transform,
    bodyConfig: PhysicsBodyConfig,
  ): void {
    const { world, sharedBuffer } = this.ensureInitialized();

    const { body, collider } = this.bodyFactory.createEntity(
      world,
      entityId,
      transform,
      bodyConfig,
    );

    // Get buffer index and register
    sharedBuffer.rebuildEntityMap();
    const bufferIndex = sharedBuffer.getEntityIndex(entityId);
    this.entities.register(entityId, body, collider, bufferIndex);
  }

  spawnFloatingPlayer(
    id: EntityId,
    transform: Transform,
    controllerConfig: FloatingCapsuleConfig,
  ): void {
    const { world, sharedBuffer } = this.ensureInitialized();

    this.floatingController = this.bodyFactory.createFloatingPlayer(
      world,
      id,
      transform,
      controllerConfig,
    );

    // Register in entity registry
    const body = this.floatingController.getBody();
    const collider = this.floatingController.getCollider();
    sharedBuffer.rebuildEntityMap();
    const bufferIndex = sharedBuffer.getEntityIndex(id);
    this.entities.register(id, body, collider, bufferIndex);

    this.playerId = id;

    // Pass stored callback if set before player creation
    if (this.playerStateCallback) {
      this.floatingController.setPlayerStateCallback(this.playerStateCallback);
    }
  }

  spawnBodies(
    entityIds: EntityId[],
    positions: Float32Array,
    bodyConfig: BatchBodyConfig,
    sizes: Float32Array,
    velocities?: Float32Array,
  ): void {
    const { world, sharedBuffer } = this.ensureInitialized();

    sharedBuffer.rebuildEntityMap();

    const results = this.bodyFactory.createBatch(
      world,
      entityIds,
      positions,
      bodyConfig,
      sizes,
      velocities,
    );

    // Register all created bodies
    for (const { id, body, collider } of results) {
      const bufferIndex = sharedBuffer.getEntityIndex(id);
      this.entities.register(id, body, collider, bufferIndex);
    }
  }

  removeBodies(entityIds: EntityId[]): void {
    for (const id of entityIds) {
      this.removeEntity(id);
    }
  }

  removeEntity(id: EntityId): void {
    if (!this.world) return;

    this.entities.unregister(id, this.world);

    if (this.playerId === id) {
      this.playerId = null;
      this.floatingController = null;
    }
  }

  setPlayerInput(input: MovementInput): void {
    this.floatingController?.setInput(input);
  }

  updatePhysicsConfig(update: DebugPhysicsUpdate): void {
    if (update.density !== undefined) {
      this.bodyFactory.setDensity(update.density);
    }
    if (update.gravity !== undefined && this.world) {
      this.world.gravity = { x: 0, y: update.gravity, z: 0 };
    }
  }

  updatePlayerConfig(update: DebugPlayerUpdate): void {
    this.floatingController?.updateConfig(update);
  }

  setCollisionCallback(callback: CollisionCallback): void {
    this.collisionTracker.setCollisionCallback(callback);
  }

  setPlayerStateCallback(callback: PlayerStateCallback): void {
    this.playerStateCallback = callback;
    this.floatingController?.setPlayerStateCallback(callback);
  }

  start(): void {
    this.running = true;
    this.lastTime = performance.now();
    this.step();
  }

  pause(): void {
    this.running = false;
  }

  resume(): void {
    if (!this.running) {
      this.running = true;
      this.lastTime = performance.now();
      this.step();
    }
  }

  private step = (): void => {
    if (!this.running || !this.world || !this.sharedBuffer || !this.eventQueue)
      return;

    const now = performance.now();
    const deltaMs = now - this.lastTime;
    this.lastTime = now;

    const deltaSeconds = Math.min(deltaMs / 1000, 0.1);

    // Update player movement
    this.floatingController?.update(deltaSeconds);

    // Write player grounded state to flags buffer
    if (this.floatingController && this.playerId !== null) {
      const bufferIndex = this.entities.getBufferIndex(this.playerId);
      if (bufferIndex !== undefined) {
        const flags = this.floatingController.getIsGrounded()
          ? EntityFlags.GROUNDED
          : 0;
        this.sharedBuffer.writeEntityFlags(bufferIndex, flags);
      }
    }

    // Step physics
    this.world.step(this.eventQueue);

    // Process collision events
    this.collisionTracker.drainCollisionEvents(
      this.eventQueue,
      this.world,
      (collider) => this.entities.getEntityIdFromCollider(collider),
      this.playerId,
    );

    // Write transforms
    this.writeTransformsToSharedBuffer();

    // Write timing
    this.sharedBuffer.writeFrameTiming(now, this.PHYSICS_INTERVAL);
    this.sharedBuffer.signalFrameComplete();

    // Schedule next step
    setTimeout(this.step, this.PHYSICS_INTERVAL);
  };

  private writeTransformsToSharedBuffer(): void {
    if (!this.sharedBuffer) return;

    this.entities.forEach((entity, id) => {
      const { body, bufferIndex } = entity;

      const validation = this.sharedBuffer!.validateIndex(bufferIndex);
      if (!validation.success) {
        console.error(
          `[PhysicsWorld] Entity ${id} invalid buffer index ${bufferIndex}: ${validation.error}`,
        );
        return;
      }

      const pos = body.translation();
      const rot = body.rotation();

      this.sharedBuffer!.writeTransform(
        bufferIndex,
        pos.x,
        pos.y,
        pos.z,
        rot.x,
        rot.y,
        rot.z,
        rot.w,
      );
    });
  }

  dispose(): void {
    this.running = false;
    this.entities.clear();
    this.collisionTracker.dispose();
    this.floatingController = null;
    this.playerId = null;
    this.world = null;
    this.eventQueue = null;
    this.sharedBuffer = null;
    this.initialized = false;
  }
}
