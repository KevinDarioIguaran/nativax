/**
 * Entity spawn command types
 *
 * WebSocket-ready API - all commands can be serialized and sent over network
 */

import type { EntityId } from "~/shared/types";

/**
 * 3D vector for positions and velocities
 */
export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/**
 * Command to spawn a box entity
 */
export interface SpawnBoxCommand {
  entityId?: EntityId; // Optional - auto-generate if not provided
  position: Vec3;
  size?: Vec3; // Default 1x1x1
  velocity?: Vec3; // Optional initial velocity
}

/**
 * Command to spawn a sphere entity
 */
export interface SpawnSphereCommand {
  entityId?: EntityId; // Optional - auto-generate if not provided
  position: Vec3;
  radius?: number; // Default 0.5
  velocity?: Vec3; // Optional initial velocity
}

/**
 * Command to spawn the player entity
 */
export interface SpawnPlayerCommand {
  position: { x: number; y: number; z: number };
}

/**
 * Batch spawn result
 */
export interface BatchSpawnResult {
  entityIds: EntityId[];
  successCount: number;
}

/**
 * Default sizes for entity types
 */
export const DEFAULT_SIZES = {
  box: { x: 1, y: 1, z: 1 },
  sphereRadius: 0.5,
} as const;
