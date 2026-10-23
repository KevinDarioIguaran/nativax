/**
 * WorldSpawner - Manages world/terrain entities
 *
 * Handles ground, terrain, and initial scene setup.
 * Coordinates with other spawners for test objects.
 */

import * as Comlink from "comlink";
import type { PhysicsApi } from "~/shared/types/physics-api";
import type { RenderApi } from "~/shared/types/render-api";
import type { SharedTransformBuffer } from "~/shared/buffers/transform-buffer";
import { createEntityId, type EntityId } from "~/shared/types";
import { config } from "~/shared/config";

export default class WorldSpawner {
  private groundId: EntityId | null = null;
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
   * Spawn the ground/terrain with heightfield physics
   */
  async spawnGround(): Promise<EntityId> {
    if (this.groundId !== null) {
      throw new Error("Ground already exists. Call removeGround() first.");
    }

    const entityId = createEntityId();

    // Register in shared buffer
    this.sharedBuffer.registerEntity(entityId);

    // Create physics body with heightfield collider
    await this.physicsApi.spawnEntity(
      {
        id: entityId,
        type: "static",
        transform: {
          position: { x: 0, y: 0, z: 0 },
          rotation: { x: 0, y: 0, z: 0, w: 1 },
          scale: { x: 1, y: 1, z: 1 },
        },
      },
      {
        type: "static",
        colliderType: "heightfield",
        dimensions: {
          x: config.terrain.size,
          y: 1,
          z: config.terrain.size,
        },
        friction: 0.8,
      },
    );

    // Create render entity
    await this.renderApi.spawnEntity(entityId, "ground");

    this.groundId = entityId;
    return entityId;
  }

  /**
   * Remove the ground
   */
  async removeGround(): Promise<void> {
    if (this.groundId === null) return;

    await this.physicsApi.removeEntity(this.groundId);
    await this.renderApi.removeEntity(this.groundId);
    this.sharedBuffer.unregisterEntity(this.groundId);

    this.groundId = null;
  }

  /**
   * Get the ground entity ID
   */
  getGroundId(): EntityId | null {
    return this.groundId;
  }

  /**
   * Check if ground exists
   */
  hasGround(): boolean {
    return this.groundId !== null;
  }

  /**
   * Dispose of spawner resources
   */
  dispose(): void {
    // Note: Does not remove ground - call removeGround() first if needed
    this.groundId = null;
  }
}
