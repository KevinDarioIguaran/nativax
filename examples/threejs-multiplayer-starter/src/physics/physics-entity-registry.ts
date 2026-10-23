import RAPIER from "@dimforge/rapier3d-compat";
import type { EntityId } from "~/shared/types";

/**
 * PhysicsEntity - Combined physics body data
 */
export interface PhysicsEntity {
  body: RAPIER.RigidBody;
  collider: RAPIER.Collider;
  bufferIndex: number;
}

/**
 * PhysicsEntityRegistry - Unified entity storage for physics world
 *
 * Consolidates body, collider, and buffer index into single map.
 * Provides O(1) reverse lookup from collider handle to entity ID.
 */
export class PhysicsEntityRegistry {
  private entities: Map<EntityId, PhysicsEntity> = new Map();
  private colliderToEntity: Map<number, EntityId> = new Map();

  /**
   * Register an entity with its physics components
   */
  register(
    id: EntityId,
    body: RAPIER.RigidBody,
    collider: RAPIER.Collider,
    bufferIndex: number,
  ): void {
    this.entities.set(id, { body, collider, bufferIndex });
    this.colliderToEntity.set(collider.handle, id);
  }

  /**
   * Remove an entity and its physics components
   * @returns The rigid body for removal from world, or null if not found
   */
  unregister(id: EntityId, world: RAPIER.World): RAPIER.RigidBody | null {
    const entity = this.entities.get(id);
    if (!entity) return null;

    // Remove from reverse lookup
    this.colliderToEntity.delete(entity.collider.handle);

    // Remove from main registry
    this.entities.delete(id);

    // Remove from physics world
    world.removeRigidBody(entity.body);

    return entity.body;
  }

  /**
   * Get entity by ID
   */
  get(id: EntityId): PhysicsEntity | undefined {
    return this.entities.get(id);
  }

  /**
   * Get body by ID
   */
  getBody(id: EntityId): RAPIER.RigidBody | undefined {
    return this.entities.get(id)?.body;
  }

  /**
   * Get collider by ID
   */
  getCollider(id: EntityId): RAPIER.Collider | undefined {
    return this.entities.get(id)?.collider;
  }

  /**
   * Get buffer index by ID
   */
  getBufferIndex(id: EntityId): number | undefined {
    return this.entities.get(id)?.bufferIndex;
  }

  /**
   * O(1) reverse lookup: get entity ID from collider handle
   */
  getEntityIdFromCollider(collider: RAPIER.Collider): EntityId | null {
    return this.colliderToEntity.get(collider.handle) ?? null;
  }

  /**
   * Check if entity exists
   */
  has(id: EntityId): boolean {
    return this.entities.has(id);
  }

  /**
   * Iterate over all entities
   */
  forEach(
    callback: (entity: PhysicsEntity, id: EntityId) => void,
  ): void {
    this.entities.forEach((entity, id) => callback(entity, id));
  }

  /**
   * Get all entity IDs
   */
  ids(): IterableIterator<EntityId> {
    return this.entities.keys();
  }

  /**
   * Get count of registered entities
   */
  get size(): number {
    return this.entities.size;
  }

  /**
   * Clear all entities
   */
  clear(): void {
    this.entities.clear();
    this.colliderToEntity.clear();
  }
}
