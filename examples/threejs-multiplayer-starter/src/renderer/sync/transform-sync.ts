import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import { SharedTransformBuffer } from "~/shared/buffers";
import type { RenderComponent } from "../entities";
import type InstancedBoxes from "../objects/instanced-boxes";
import type InstancedSpheres from "../objects/instanced-spheres";

/**
 * TransformSync - Physics-to-render transform interpolation
 *
 * Implements the "Fix Your Timestep!" interpolation pattern:
 * - Reads transforms and timestamps from SharedArrayBuffer
 * - Calculates interpolation alpha based on time since physics frame
 * - Interpolates between PREVIOUS and CURRENT physics states
 *
 * @see https://gafferongames.com/post/fix_your_timestep/
 */
class TransformSync {
  private sharedBuffer: SharedTransformBuffer;
  private lastPhysicsFrame = 0;

  // Instanced mesh references for batch transform updates
  private instancedBoxes: InstancedBoxes | null = null;
  private instancedSpheres: InstancedSpheres | null = null;

  // Temporary objects for interpolation (avoid allocation in render loop)
  private tempQuatPrev = new THREE.Quaternion();
  private tempQuatCurrent = new THREE.Quaternion();
  private tempPosition = new THREE.Vector3();
  private tempQuaternion = new THREE.Quaternion();

  constructor(sharedBuffer: SharedTransformBuffer) {
    this.sharedBuffer = sharedBuffer;
  }

  /**
   * Set the instanced boxes renderer for batch transform updates
   */
  setInstancedBoxes(instancedBoxes: InstancedBoxes | null): void {
    this.instancedBoxes = instancedBoxes;
  }

  /**
   * Set the instanced spheres renderer for batch transform updates
   */
  setInstancedSpheres(instancedSpheres: InstancedSpheres | null): void {
    this.instancedSpheres = instancedSpheres;
  }

  /**
   * Rebuild entity map after entities are added/removed
   */
  rebuildEntityMap(): void {
    this.sharedBuffer.rebuildEntityMap();
  }

  /**
   * Get the buffer index for an entity
   */
  getEntityIndex(id: EntityId): number {
    return this.sharedBuffer.getEntityIndex(id);
  }

  /**
   * Get the shared buffer for passing to entities that need direct access
   */
  getSharedBuffer(): SharedTransformBuffer {
    return this.sharedBuffer;
  }

  /**
   * Update transforms for all entities with interpolation
   *
   * @param entities - Map of entities to update
   * @returns true if a new physics frame was available
   */
  update(entities: Map<EntityId, RenderComponent>): boolean {
    const now = performance.now();
    const currentFrame = this.sharedBuffer.getFrameCounter();
    const newFrameAvailable = currentFrame !== this.lastPhysicsFrame;

    // Read timing information once (same for all entities)
    const timing = this.sharedBuffer.readFrameTiming();

    // Calculate interpolation alpha based on physics timestamps (once for all entities)
    const timeSincePhysicsFrame = now - timing.currentTime;

    // Handle edge case where timing hasn't been initialized yet
    const interval = timing.interval > 0 ? timing.interval : 1000 / 60;

    // Clamp alpha to [0, 1] to prevent overshooting if physics is slow
    const alpha = Math.min(Math.max(timeSincePhysicsFrame / interval, 0), 1);

    // Apply interpolated transforms to all entities with pre-calculated alpha
    for (const entity of entities.values()) {
      this.applyInterpolatedTransform(entity, alpha);
    }

    // Update all instanced mesh transforms
    this.updateInstancedBoxes(alpha);
    this.updateInstancedSpheres(alpha);

    if (newFrameAvailable) {
      this.lastPhysicsFrame = currentFrame;
    }

    return newFrameAvailable;
  }

  /**
   * Update all instanced box transforms with interpolation
   */
  private updateInstancedBoxes(alpha: number): void {
    if (!this.instancedBoxes) return;

    // Use forEachEntity to avoid array allocation in hot path
    this.instancedBoxes.forEachEntity((entityId) => {
      const bufferIndex = this.sharedBuffer.getEntityIndex(entityId);
      if (bufferIndex < 0) return;

      const transforms = this.sharedBuffer.readTransform(bufferIndex);
      this.interpolateTransformFromData(transforms, alpha);

      // Update the instance
      this.instancedBoxes!.updateInstance(
        entityId,
        this.tempPosition,
        this.tempQuaternion,
      );
    });

    // Flush all changes to GPU
    this.instancedBoxes.commitUpdates();
  }

  /**
   * Update all instanced sphere transforms with interpolation
   */
  private updateInstancedSpheres(alpha: number): void {
    if (!this.instancedSpheres) return;

    // Use forEachEntity to avoid array allocation in hot path
    this.instancedSpheres.forEachEntity((entityId) => {
      const bufferIndex = this.sharedBuffer.getEntityIndex(entityId);
      if (bufferIndex < 0) return;

      const transforms = this.sharedBuffer.readTransform(bufferIndex);
      this.interpolateTransformFromData(transforms, alpha);

      // Update the instance
      this.instancedSpheres!.updateInstance(
        entityId,
        this.tempPosition,
        this.tempQuaternion,
      );
    });

    // Flush all changes to GPU
    this.instancedSpheres.commitUpdates();
  }

  /**
   * Interpolate transform from pre-read data into temp objects
   */
  private interpolateTransformFromData(
    transforms: { current: any; previous: any },
    alpha: number,
  ): void {
    // Interpolate position
    this.tempPosition.set(
      this.lerp(transforms.previous.posX, transforms.current.posX, alpha),
      this.lerp(transforms.previous.posY, transforms.current.posY, alpha),
      this.lerp(transforms.previous.posZ, transforms.current.posZ, alpha),
    );

    // Spherical interpolation for quaternion rotation
    this.tempQuatPrev.set(
      transforms.previous.rotX,
      transforms.previous.rotY,
      transforms.previous.rotZ,
      transforms.previous.rotW,
    );
    this.tempQuatCurrent.set(
      transforms.current.rotX,
      transforms.current.rotY,
      transforms.current.rotZ,
      transforms.current.rotW,
    );
    this.tempQuaternion.slerpQuaternions(
      this.tempQuatPrev,
      this.tempQuatCurrent,
      alpha,
    );
  }

  /**
   * Interpolate transform from shared buffer into temp objects
   */
  private interpolateTransform(bufferIndex: number, alpha: number): void {
    const transforms = this.sharedBuffer.readTransform(bufferIndex);
    this.interpolateTransformFromData(transforms, alpha);
  }

  /**
   * Apply interpolated transform to a single entity
   *
   * @param entity - The entity to update
   * @param alpha - Pre-calculated interpolation factor [0, 1]
   */
  private applyInterpolatedTransform(
    entity: RenderComponent,
    alpha: number,
  ): void {
    const bufferIndex = this.sharedBuffer.getEntityIndex(entity.id);
    if (bufferIndex < 0) return;

    this.interpolateTransform(bufferIndex, alpha);

    // Apply to entity
    entity.object.position.copy(this.tempPosition);
    entity.object.quaternion.copy(this.tempQuaternion);

    // Call transform update hook
    entity.onTransformUpdate?.(this.tempPosition, this.tempQuaternion);
  }

  /**
   * Linear interpolation helper
   */
  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  /**
   * Dispose of resources
   */
  dispose(): void {
    this.lastPhysicsFrame = 0;
    this.instancedBoxes = null;
    this.instancedSpheres = null;
  }
}

export default TransformSync;
