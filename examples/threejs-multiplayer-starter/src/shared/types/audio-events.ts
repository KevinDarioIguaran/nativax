import type { EntityId } from "./entity";

/**
 * Audio Event Types
 *
 * Events sent from workers to main thread for audio playback.
 * Audio lives on main thread because AudioContext cannot be created in workers.
 */

/**
 * Footstep audio event - triggered by player movement
 */
export interface FootstepEvent {
  type: "footstep";
  entityId: EntityId;
  position: { x: number; y: number; z: number };
  intensity: number; // 0-1, based on walk (0.6) vs run (1.0)
}

/**
 * Collision audio event - triggered by physics impacts
 * Entity IDs can be null for ground/static objects without tracked IDs
 */
export interface CollisionEvent {
  type: "collision";
  entityA: EntityId | null;
  entityB: EntityId | null;
  position: { x: number; y: number; z: number };
  impulse: number; // Collision strength for volume scaling
}

/**
 * Jump audio event - triggered when player jumps
 */
export interface JumpEvent {
  type: "jump";
  entityId: EntityId;
  position: { x: number; y: number; z: number };
}

/**
 * Land audio event - triggered when player lands
 */
export interface LandEvent {
  type: "land";
  entityId: EntityId;
  position: { x: number; y: number; z: number };
  intensity: number; // 0-1, based on fall speed
}

/**
 * Listener position update - for 3D spatial audio positioning
 */
export interface ListenerUpdate {
  position: { x: number; y: number; z: number };
  forward: { x: number; y: number; z: number };
  up: { x: number; y: number; z: number };
}

/**
 * Union type for all audio events from physics worker
 */
export type PhysicsAudioEvent = CollisionEvent | JumpEvent | LandEvent;

/**
 * Union type for all audio events from render worker
 */
export type RenderAudioEvent = FootstepEvent;

/**
 * Callback types for worker APIs
 */
export type CollisionCallback = (event: CollisionEvent) => void;
export type PlayerStateCallback = (event: JumpEvent | LandEvent) => void;
export type FootstepCallback = (event: FootstepEvent) => void;
export type ListenerCallback = (update: ListenerUpdate) => void;
