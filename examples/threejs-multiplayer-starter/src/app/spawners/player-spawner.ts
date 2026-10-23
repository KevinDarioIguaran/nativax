/**
 * PlayerSpawner - Manages the unique player entity
 *
 * Handles spawning and tracking of the player.
 * Only one player can exist at a time.
 */

import * as Comlink from "comlink";
import type { PhysicsApi, DebugCollider } from "~/shared/types/physics-api";
import type { RenderApi } from "~/shared/types/render-api";
import type { SharedTransformBuffer } from "~/shared/buffers/transform-buffer";
import { createEntityId, type EntityId } from "~/shared/types";
import { config } from "~/shared/config";
import type { SpawnPlayerCommand } from "./types";

export default class PlayerSpawner {
  private playerId: EntityId | null = null;
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
   * Spawn the player entity
   * @throws Error if player already exists
   */
  async spawn(command: SpawnPlayerCommand): Promise<EntityId> {
    if (this.playerId !== null) {
      throw new Error("Player already exists. Call remove() first.");
    }

    const entityId = createEntityId();
    const { position } = command;
    const capsuleConfig = config.floatingCapsule;

    // Register in shared buffer
    this.sharedBuffer.registerEntity(entityId);

    // Create physics body (floating player with character controller)
    await this.physicsApi.spawnFloatingPlayer(
      entityId,
      {
        position: { x: position.x, y: position.y, z: position.z },
        rotation: { x: 0, y: 0, z: 0, w: 1 },
        scale: { x: 1, y: 1, z: 1 },
      },
      {
        radius: capsuleConfig.radius,
        halfHeight: capsuleConfig.halfHeight,
        floatingDistance: capsuleConfig.floatingDistance,
        rayLength: capsuleConfig.rayLength,
        springStrength: capsuleConfig.springStrength,
        springDamping: capsuleConfig.springDamping,
        moveForce: capsuleConfig.moveForce,
        sprintMultiplier: capsuleConfig.sprintMultiplier,
        airControlMultiplier: capsuleConfig.airControlMultiplier,
        maxVelocity: capsuleConfig.maxVelocity,
        sprintMaxVelocity: capsuleConfig.sprintMaxVelocity,
        jumpForce: capsuleConfig.jumpForce,
        coyoteTime: capsuleConfig.coyoteTime,
        jumpBufferTime: capsuleConfig.jumpBufferTime,
        groundedThreshold: capsuleConfig.groundedThreshold,
        slopeLimit: capsuleConfig.slopeLimit,
        mass: capsuleConfig.mass,
        friction: capsuleConfig.friction,
        linearDamping: capsuleConfig.linearDamping,
        angularDamping: capsuleConfig.angularDamping,
      },
    );

    // Player debug collider for visualization
    const totalHalfHeight = capsuleConfig.halfHeight + capsuleConfig.radius;
    const playerDebugCollider: DebugCollider = {
      shape: {
        type: "capsule",
        radius: capsuleConfig.radius,
        halfHeight: capsuleConfig.halfHeight,
      },
      offset: { x: 0, y: totalHalfHeight, z: 0 },
    };

    // Create render entity
    await this.renderApi.spawnEntity(
      entityId,
      "player",
      undefined,
      playerDebugCollider,
    );

    this.playerId = entityId;
    return entityId;
  }

  /**
   * Remove the player entity
   */
  async remove(): Promise<void> {
    if (this.playerId === null) return;

    await this.physicsApi.removeEntity(this.playerId);
    await this.renderApi.removeEntity(this.playerId);
    this.sharedBuffer.unregisterEntity(this.playerId);

    this.playerId = null;
  }

  /**
   * Get the player entity ID
   */
  getPlayerId(): EntityId | null {
    return this.playerId;
  }

  /**
   * Check if player exists
   */
  hasPlayer(): boolean {
    return this.playerId !== null;
  }

  /**
   * Dispose of spawner resources
   */
  dispose(): void {
    // Note: Does not remove player - call remove() first if needed
    this.playerId = null;
  }
}
