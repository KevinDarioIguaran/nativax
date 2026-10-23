/**
 * Mutable debug configuration
 *
 * These values can be modified at runtime via Tweakpane debug UI.
 * Initial values are copied from config.ts but can be changed live.
 */

import { config } from "./config";

/**
 * Mutable physics config for debug tweaking
 */
export const debugPhysicsConfig = {
  density: config.physics.density,
  gravity: config.physics.gravity.y,
};

/**
 * Mutable player config for debug tweaking
 */
export const debugPlayerConfig = {
  springStrength: config.floatingCapsule.springStrength,
  springDamping: config.floatingCapsule.springDamping,
  moveForce: config.floatingCapsule.moveForce,
  jumpForce: config.floatingCapsule.jumpForce,
  floatingDistance: config.floatingCapsule.floatingDistance,
  maxVelocity: config.floatingCapsule.maxVelocity,
};

/**
 * Mutable spawner config for debug tweaking
 */
export const debugSpawnerConfig = {
  size: config.spawner.defaultSize,
  projectileSpeed: config.spawner.projectileSpeed,
};

/**
 * Debug update types for passing to physics worker
 */
export interface DebugPhysicsUpdate {
  density?: number;
  gravity?: number;
}

export interface DebugPlayerUpdate {
  springStrength?: number;
  springDamping?: number;
  moveForce?: number;
  jumpForce?: number;
  floatingDistance?: number;
  maxVelocity?: number;
}
