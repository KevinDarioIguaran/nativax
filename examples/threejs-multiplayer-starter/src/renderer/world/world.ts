import * as THREE from "three";
import type { EntityId, DebugCollider, FootstepCallback } from "~/shared/types";
import type Resources from "../systems/resources";
import type Time from "../systems/time";
import type Debug from "../systems/debug";
import type InputState from "../systems/input-state";
import type Camera from "../core/camera";
import type TransformSync from "../sync/transform-sync";

// Entity system
import {
  EntityFactory,
  type RenderComponent,
  type EntityContext,
} from "../entities";
import { PlayerEntity } from "../entities/components/player";

// Scene objects (non-entity visuals)
import Floor from "../objects/floor";
import Environment from "./environment";
import PhysicsDebugRenderer from "../sync/physics-debug-renderer";
import InstancedBoxes from "../objects/instanced-boxes";
import InstancedSpheres from "../objects/instanced-spheres";

/**
 * Context passed to World for creating entities and scene objects
 */
export interface WorldContext {
  scene: THREE.Scene;
  resources: Resources;
  time: Time;
  debug: Debug;
  inputState: InputState;
  camera: Camera;
}

/**
 * World - Entity and scene object management
 *
 * Responsible for:
 * - Creating and managing entities via EntityFactory
 * - Creating static scene objects (floor, plane, environment)
 * - Entity lifecycle (spawn, remove, update)
 * - Calling entity lifecycle hooks (onRenderFrame, onPhysicsFrame)
 * - Tracking player entity for camera following
 * - Managing instanced boxes and spheres for performance
 */
class World {
  private context: WorldContext;

  // Entity management
  private entities: Map<EntityId, RenderComponent> = new Map();
  private entityFactory: EntityFactory | null = null;
  private playerEntityId: EntityId | null = null;

  // Debug colliders for physics visualization
  private debugColliders: Map<EntityId, DebugCollider> = new Map();
  private physicsDebugRenderer: PhysicsDebugRenderer;

  // Instanced meshes for performance (single draw call per type)
  private instancedBoxes: InstancedBoxes | null = null;
  private instancedSpheres: InstancedSpheres | null = null;
  private transformSync: TransformSync | null = null;

  // Scene objects (non-entity visuals that don't need physics sync)
  private sceneObjects: {
    floor: Floor | null;
    environment: Environment | null;
  } = { floor: null, environment: null };

  // Audio callback for footsteps
  private footstepCallback: FootstepCallback | null = null;

  constructor(context: WorldContext) {
    this.context = context;
    this.physicsDebugRenderer = new PhysicsDebugRenderer(
      context.scene,
      context.debug,
    );
  }

  /**
   * Set the transform sync reference for instanced mesh updates
   */
  setTransformSync(transformSync: TransformSync): void {
    this.transformSync = transformSync;
  }

  /**
   * Create scene objects after resources are loaded
   * Should be called when resources emit 'ready'
   * Requires setTransformSync() to be called first for entity context
   */
  createSceneObjects(): void {
    const { scene, resources, time, debug, inputState } = this.context;

    if (!this.transformSync) {
      throw new Error(
        "World.createSceneObjects requires setTransformSync() to be called first",
      );
    }

    // Create entity context and factory
    const entityContext: EntityContext = {
      scene,
      resources,
      time,
      debug,
      inputState,
      sharedBuffer: this.transformSync.getSharedBuffer(),
    };
    this.entityFactory = new EntityFactory(entityContext);

    // Create non-entity scene objects
    this.sceneObjects.floor = new Floor(scene, resources, debug);
    this.sceneObjects.environment = new Environment(scene, resources, debug);

    // Create instanced mesh managers (lazy initialization moved to createSceneObjects for consistency)
    this.instancedBoxes = new InstancedBoxes(scene, 1000);
    this.instancedSpheres = new InstancedSpheres(scene, 1000);

    // Wire to TransformSync
    if (this.transformSync) {
      this.transformSync.setInstancedBoxes(this.instancedBoxes);
      this.transformSync.setInstancedSpheres(this.instancedSpheres);
    }
  }

  /**
   * Spawn a new entity
   */
  async spawnEntity(
    id: EntityId,
    type: string,
    data?: Record<string, unknown>,
    debugCollider?: DebugCollider,
  ): Promise<void> {
    if (!this.entityFactory) {
      throw new Error("World not initialized - call createSceneObjects first");
    }

    // Create entity via factory
    const entity = await this.entityFactory.create(id, type, data);
    this.entities.set(id, entity);

    // Store debug collider and add debug mesh
    if (debugCollider) {
      this.debugColliders.set(id, debugCollider);
      this.physicsDebugRenderer.addEntity(id, debugCollider);
    }

    // Track player entity for camera following
    if (type === "player") {
      this.playerEntityId = id;
      this.context.camera.setTarget(entity.object);

      // Pass footstep callback to player entity
      if (this.footstepCallback && entity instanceof PlayerEntity) {
        entity.setFootstepCallback(this.footstepCallback);
      }
    }
  }

  /**
   * Set callback for footstep events
   */
  setFootstepCallback(callback: FootstepCallback): void {
    this.footstepCallback = callback;

    // If player already exists, update its callback
    if (this.playerEntityId) {
      const playerEntity = this.entities.get(this.playerEntityId);
      if (playerEntity && playerEntity instanceof PlayerEntity) {
        playerEntity.setFootstepCallback(callback);
      }
    }
  }

  /**
   * Remove an entity
   */
  removeEntity(id: EntityId): void {
    const entity = this.entities.get(id);
    if (!entity) return;

    // Use entity's own dispose method
    entity.dispose();
    this.entities.delete(id);
    this.debugColliders.delete(id);
    this.physicsDebugRenderer.removeEntity(id);

    if (this.playerEntityId === id) {
      this.playerEntityId = null;
      this.context.camera.setTarget(null);
    }
  }

  /**
   * Get the player entity ID
   */
  getPlayerEntityId(): EntityId | null {
    return this.playerEntityId;
  }

  /**
   * Get all entities (for TransformSync)
   */
  getEntities(): Map<EntityId, RenderComponent> {
    return this.entities;
  }

  // ============================================
  // Instanced Boxes
  // ============================================

  /**
   * Add a single box to the instanced mesh
   */
  addBox(
    entityId: EntityId,
    scale?: { x: number; y: number; z: number },
  ): void {
    if (!this.instancedBoxes) return;
    this.instancedBoxes.addBox(entityId, scale);
  }

  /**
   * Add multiple boxes to the instanced mesh
   */
  addBoxes(
    entityIds: EntityId[],
    scales?: Array<{ x: number; y: number; z: number }>,
  ): void {
    if (!this.instancedBoxes) return;
    this.instancedBoxes.addBoxes(entityIds, scales);
  }

  /**
   * Remove boxes from the instanced mesh
   */
  removeBoxes(entityIds: EntityId[]): void {
    if (!this.instancedBoxes) return;
    this.instancedBoxes.removeBoxes(entityIds);
  }

  /**
   * Clear all instanced boxes
   */
  clearBoxes(): void {
    if (!this.instancedBoxes) return;
    this.instancedBoxes.clear();
  }

  /**
   * Get box count
   */
  getBoxCount(): number {
    return this.instancedBoxes?.getCount() ?? 0;
  }

  // ============================================
  // Instanced Spheres
  // ============================================

  /**
   * Add a single sphere to the instanced mesh
   */
  addSphere(entityId: EntityId, radius?: number): void {
    if (!this.instancedSpheres) return;
    this.instancedSpheres.addSphere(entityId, radius);
  }

  /**
   * Add multiple spheres to the instanced mesh
   */
  addSpheres(entityIds: EntityId[], radii?: number[]): void {
    if (!this.instancedSpheres) return;
    this.instancedSpheres.addSpheres(entityIds, radii);
  }

  /**
   * Remove spheres from the instanced mesh
   */
  removeSpheres(entityIds: EntityId[]): void {
    if (!this.instancedSpheres) return;
    this.instancedSpheres.removeSpheres(entityIds);
  }

  /**
   * Clear all instanced spheres
   */
  clearSpheres(): void {
    if (!this.instancedSpheres) return;
    this.instancedSpheres.clear();
  }

  /**
   * Get sphere count
   */
  getSphereCount(): number {
    return this.instancedSpheres?.getCount() ?? 0;
  }

  // ============================================
  // Combined Instance Operations
  // ============================================

  /**
   * Remove instances by entity IDs (auto-detects type)
   */
  removeInstances(entityIds: EntityId[]): void {
    // Check each entity ID and remove from appropriate instanced mesh
    for (const id of entityIds) {
      if (this.instancedBoxes?.hasEntity(id)) {
        this.instancedBoxes.removeBox(id);
      } else if (this.instancedSpheres?.hasEntity(id)) {
        this.instancedSpheres.removeSphere(id);
      }
    }
  }

  /**
   * Clear all instanced meshes
   */
  clearAllInstances(): void {
    this.clearBoxes();
    this.clearSpheres();
  }

  /**
   * Get all debug colliders (for PhysicsDebugRenderer)
   */
  getDebugColliders(): Map<EntityId, DebugCollider> {
    return this.debugColliders;
  }

  /**
   * Update all entities
   *
   * @param delta - Time since last frame in milliseconds
   * @param elapsed - Total elapsed time in milliseconds
   * @param newPhysicsFrame - Whether a new physics frame is available
   */
  update(delta: number, elapsed: number, newPhysicsFrame: boolean): void {
    const deltaSeconds = delta * 0.001;

    for (const entity of this.entities.values()) {
      // Update animation mixers for any entity that has one
      if (entity.mixer) {
        entity.mixer.update(deltaSeconds);
      }

      // Call render frame hook (for time-based updates like shaders)
      entity.onRenderFrame?.(delta, elapsed);

      // Call physics frame hook when new physics data arrives
      if (newPhysicsFrame) {
        entity.onPhysicsFrame?.(this.context.inputState);
      }
    }

    // Update physics debug visualization positions
    this.physicsDebugRenderer.update(this.entities);

    // Update shadow camera to follow player
    if (this.playerEntityId && this.sceneObjects.environment) {
      const playerEntity = this.entities.get(this.playerEntityId);
      if (playerEntity) {
        this.sceneObjects.environment.updateShadowTarget(
          playerEntity.object.position,
        );
      }
    }
  }

  /**
   * Toggle physics debug visualization
   */
  setPhysicsDebugVisible(visible: boolean): void {
    this.physicsDebugRenderer.setVisible(visible);
  }

  /**
   * Get physics debug visibility state
   */
  isPhysicsDebugVisible(): boolean {
    return this.physicsDebugRenderer.isVisible();
  }

  /**
   * Toggle physics debug visualization
   */
  togglePhysicsDebug(): void {
    this.physicsDebugRenderer.toggle();
  }

  /**
   * Dispose of all entities and scene objects
   */
  dispose(): void {
    // Dispose all entities
    for (const entity of this.entities.values()) {
      entity.dispose();
    }
    this.entities.clear();

    // Dispose instanced meshes
    this.instancedBoxes?.dispose();
    this.instancedBoxes = null;
    this.instancedSpheres?.dispose();
    this.instancedSpheres = null;

    // Dispose scene objects
    this.sceneObjects.floor?.dispose();
    this.sceneObjects.environment?.dispose();

    // Dispose physics debug renderer
    this.physicsDebugRenderer.dispose();
  }
}

export default World;
