import RAPIER from "@dimforge/rapier3d-compat";
import type { EntityId, CollisionCallback } from "~/shared/types";
import { config } from "~/shared/config";

/**
 * CollisionTracker - Manages collision event filtering and cooldowns
 *
 * Key features:
 * - Uses vertical velocity for ground collisions (filters rolling)
 * - Per-frame collision limit prevents audio overload
 * - Cooldown reduces spam from continuous contact
 * - Numeric pair keys for efficiency (no string allocation)
 */
export class CollisionTracker {
  private collisionCooldowns: Map<number, number> = new Map();
  private readonly COLLISION_COOLDOWN_MS = 350;
  private readonly MAX_COLLISIONS_PER_FRAME = 12;
  private readonly MAX_COOLDOWN_AGE_MS = 5000;

  private collisionCallback: CollisionCallback | null = null;
  private lastCleanupTime = 0;

  setCollisionCallback(callback: CollisionCallback): void {
    this.collisionCallback = callback;
  }

  /**
   * Process collision events from Rapier event queue
   */
  drainCollisionEvents(
    eventQueue: RAPIER.EventQueue,
    world: RAPIER.World,
    getEntityId: (collider: RAPIER.Collider) => EntityId | null,
    playerId: EntityId | null,
  ): void {
    if (!this.collisionCallback) return;

    const now = performance.now();
    let collisionsThisFrame = 0;

    // Periodic cleanup of old cooldowns
    if (now - this.lastCleanupTime > this.MAX_COOLDOWN_AGE_MS) {
      this.cleanupOldCooldowns(now);
      this.lastCleanupTime = now;
    }

    eventQueue.drainCollisionEvents((handle1, handle2, started) => {
      // Only process collision start events
      if (!started) return;

      // Limit collisions per frame
      if (collisionsThisFrame >= this.MAX_COLLISIONS_PER_FRAME) return;

      const collider1 = world.getCollider(handle1);
      const collider2 = world.getCollider(handle2);
      if (!collider1 || !collider2) return;

      const entityA = getEntityId(collider1);
      const entityB = getEntityId(collider2);

      // Skip if both entities are unknown
      if (entityA === null && entityB === null) return;

      // Skip player collisions (player has its own audio)
      if (entityA === playerId || entityB === playerId) return;

      // Check cooldown with numeric key
      const pairKey = this.getPairKey(entityA, entityB);
      const lastCollision = this.collisionCooldowns.get(pairKey);
      if (lastCollision && now - lastCollision < this.COLLISION_COOLDOWN_MS) {
        return;
      }

      // Calculate impulse
      const impulse = this.calculateImpulse(
        collider1,
        collider2,
        entityA,
        entityB,
      );

      // Filter weak collisions
      if (impulse < config.audio.collisions.minImpulse) return;

      // Get collision position
      const pos1 = collider1.translation();
      const pos2 = collider2.translation();

      // Update cooldown and emit
      this.collisionCooldowns.set(pairKey, now);
      collisionsThisFrame++;

      this.collisionCallback!({
        type: "collision",
        entityA,
        entityB,
        position: {
          x: (pos1.x + pos2.x) / 2,
          y: (pos1.y + pos2.y) / 2,
          z: (pos1.z + pos2.z) / 2,
        },
        impulse,
      });
    });
  }

  /**
   * Generate numeric key for entity pair
   * Uses bitwise operations to avoid string allocation
   * Ground (null) entities use ID 0
   */
  private getPairKey(a: EntityId | null, b: EntityId | null): number {
    const idA = a === null ? 0 : (a as number);
    const idB = b === null ? 0 : (b as number);
    const min = Math.min(idA, idB);
    const max = Math.max(idA, idB);
    // Combine into single number (works for IDs up to 65535)
    return (min << 16) | max;
  }

  /**
   * Calculate collision impulse based on collision type
   * Ground collisions use vertical velocity (filters rolling)
   * Object collisions use relative velocity magnitude
   */
  private calculateImpulse(
    collider1: RAPIER.Collider,
    collider2: RAPIER.Collider,
    entityA: EntityId | null,
    entityB: EntityId | null,
  ): number {
    const body1 = collider1.parent();
    const body2 = collider2.parent();

    const isGroundCollision = entityA === null || entityB === null;

    if (isGroundCollision) {
      // Ground collision: use vertical velocity
      const dynamicBody = entityA === null ? body2 : body1;
      if (dynamicBody) {
        const vel = dynamicBody.linvel();
        return Math.abs(vel.y);
      }
      return 1.0;
    }

    // Object-object: use relative velocity magnitude
    if (body1 && body2) {
      const vel1 = body1.linvel();
      const vel2 = body2.linvel();
      return Math.sqrt(
        Math.pow(vel1.x - vel2.x, 2) +
          Math.pow(vel1.y - vel2.y, 2) +
          Math.pow(vel1.z - vel2.z, 2),
      );
    }

    return 1.0;
  }

  /**
   * Clean up old cooldown entries to prevent memory growth
   */
  private cleanupOldCooldowns(now: number): void {
    for (const [key, time] of this.collisionCooldowns) {
      if (now - time > this.MAX_COOLDOWN_AGE_MS) {
        this.collisionCooldowns.delete(key);
      }
    }
  }

  dispose(): void {
    this.collisionCooldowns.clear();
    this.collisionCallback = null;
  }
}
