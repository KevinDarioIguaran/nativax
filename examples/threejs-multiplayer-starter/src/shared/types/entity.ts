// ============================================
// Entity System Types
// ============================================

/**
 * EntityId - unique identifier for entities across workers
 * Using branded type for type safety
 */
export type EntityId = number & { readonly __brand: "EntityId" };

let nextEntityId = 1;
export function createEntityId(): EntityId {
  return nextEntityId++ as EntityId;
}

/**
 * Transform data shared between physics and render workers
 */
export interface Transform {
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number; w: number }; // Quaternion
  scale: { x: number; y: number; z: number };
}

/**
 * Entity definition for spawning
 */
export interface EntitySpawnData {
  id: EntityId;
  type: EntityType;
  transform: Transform;
  data?: Record<string, unknown>;
}

/**
 * Known entity types
 */
export type EntityType = "player" | "static" | "dynamic" | "kinematic";
