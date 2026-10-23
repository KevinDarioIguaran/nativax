/**
 * SphereSpawner - Manages all sphere entities using instancing
 *
 * Handles spawning, removal, and tracking of sphere entities.
 * Uses InstancedMesh on render side for maximum performance.
 */

import * as Comlink from "comlink";
import type { PhysicsApi } from "~/shared/types/physics-api";
import type { RenderApi } from "~/shared/types/render-api";
import type { SharedTransformBuffer } from "~/shared/buffers/transform-buffer";
import { createEntityId, type EntityId } from "~/shared/types";
import { DEFAULT_SIZES, type SpawnSphereCommand } from "./types";

export default class SphereSpawner {
  private entityIds: Set<EntityId> = new Set();
  private physicsApi: Comlink.Remote<PhysicsApi>;
  private renderApi: Comlink.Remote<RenderApi>;
  private sharedBuffer: SharedTransformBuffer;

  constructor(
    physicsApi: Comlink.Remote<PhysicsApi>,
    renderApi: Comlink.Remote<RenderApi>,
    sharedBuffer: SharedTransformBuffer,
  ) {
    this.physicsApi = physicsApi;
    this.renderApi = renderApi;
    this.sharedBuffer = sharedBuffer;
  }

  /**
   * Spawn a single sphere entity
   */
  async spawn(command: SpawnSphereCommand): Promise<EntityId> {
    const entityId = command.entityId ?? createEntityId();
    const radius = command.radius ?? DEFAULT_SIZES.sphereRadius;
    const { position, velocity } = command;

    // Register in shared buffer
    this.sharedBuffer.registerEntity(entityId);

    // Create physics body with actual radius
    const positions = new Float32Array([position.x, position.y, position.z]);
    const sizes = new Float32Array([radius]);
    const velocities = velocity
      ? new Float32Array([velocity.x, velocity.y, velocity.z])
      : undefined;

    await this.physicsApi.spawnBodies(
      [entityId],
      positions,
      { type: "sphere" },
      sizes,
      velocities,
    );

    // Create render instance
    await this.renderApi.addSphere(entityId, radius);

    this.entityIds.add(entityId);
    return entityId;
  }

  /**
   * Spawn multiple spheres in a batch (more efficient)
   */
  async spawnBatch(commands: SpawnSphereCommand[]): Promise<EntityId[]> {
    if (commands.length === 0) return [];

    const entityIds: EntityId[] = [];
    const radii: number[] = [];
    const positions = new Float32Array(commands.length * 3);
    const sizes = new Float32Array(commands.length);

    for (let i = 0; i < commands.length; i++) {
      const command = commands[i];
      const entityId = command.entityId ?? createEntityId();
      const radius = command.radius ?? DEFAULT_SIZES.sphereRadius;

      entityIds.push(entityId);
      radii.push(radius);

      positions[i * 3] = command.position.x;
      positions[i * 3 + 1] = command.position.y;
      positions[i * 3 + 2] = command.position.z;

      // Per-entity radius for physics (1 float per sphere)
      sizes[i] = radius;

      // Register in shared buffer
      this.sharedBuffer.registerEntity(entityId);
      this.entityIds.add(entityId);
    }

    // Batch physics spawn with actual per-entity radii
    await this.physicsApi.spawnBodies(
      entityIds,
      positions,
      { type: "sphere" },
      sizes,
    );

    // Batch render spawn
    await this.renderApi.addSpheres(entityIds, radii);

    return entityIds;
  }

  /**
   * Remove a single sphere entity
   */
  async remove(entityId: EntityId): Promise<void> {
    if (!this.entityIds.has(entityId)) return;

    await this.physicsApi.removeBodies([entityId]);
    await this.renderApi.removeInstances([entityId]);
    this.sharedBuffer.unregisterEntity(entityId);
    this.entityIds.delete(entityId);
  }

  /**
   * Remove multiple sphere entities
   */
  async removeBatch(entityIds: EntityId[]): Promise<void> {
    const validIds = entityIds.filter((id) => this.entityIds.has(id));
    if (validIds.length === 0) return;

    await this.physicsApi.removeBodies(validIds);
    await this.renderApi.removeInstances(validIds);

    for (const id of validIds) {
      this.sharedBuffer.unregisterEntity(id);
      this.entityIds.delete(id);
    }
  }

  /**
   * Remove all sphere entities
   */
  async clear(): Promise<void> {
    const allIds = Array.from(this.entityIds);
    if (allIds.length === 0) return;

    await this.physicsApi.removeBodies(allIds);
    await this.renderApi.removeInstances(allIds);

    for (const id of allIds) {
      this.sharedBuffer.unregisterEntity(id);
    }
    this.entityIds.clear();
  }

  /**
   * Get current sphere count
   */
  getCount(): number {
    return this.entityIds.size;
  }

  /**
   * Get all sphere entity IDs
   */
  getEntityIds(): EntityId[] {
    return Array.from(this.entityIds);
  }

  /**
   * Dispose of spawner resources
   */
  dispose(): void {
    // Note: Does not remove entities - call clear() first if needed
    this.entityIds.clear();
  }
}
