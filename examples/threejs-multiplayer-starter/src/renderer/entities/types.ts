import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import type { SharedTransformBuffer } from "~/shared/buffers";
import type Resources from "../systems/resources";
import type Time from "../systems/time";
import type Debug from "../systems/debug";
import type InputState from "../systems/input-state";

/**
 * EntityContext - Shared context passed to entity components
 *
 * Provides access to core systems without tight coupling.
 */
export interface EntityContext {
  /** Three.js scene to add objects to */
  scene: THREE.Scene;

  /** Resource manager for loading assets */
  resources: Resources;

  /** Time manager for tick events */
  time: Time;

  /** Debug UI manager */
  debug: Debug;

  /** Input state for keyboard/mouse tracking */
  inputState: InputState;

  /** Shared transform buffer for reading entity state flags */
  sharedBuffer: SharedTransformBuffer;
}

/**
 * RenderComponent - Interface for all renderable entities
 *
 * Defines lifecycle hooks that the Renderer calls during entity management.
 * Implementations handle their own Three.js objects internally.
 *
 * Lifecycle:
 * 1. Factory creates component with EntityContext
 * 2. Renderer calls onTransformUpdate() each frame with interpolated physics data
 * 3. Renderer calls onPhysicsFrame() when new physics frame arrives
 * 4. Renderer calls onRenderFrame() each render frame
 * 5. Renderer calls dispose() when entity is removed
 */
export interface RenderComponent {
  /** Unique entity identifier */
  readonly id: EntityId;

  /** Entity type string (e.g., "player", "ground", "tree") */
  readonly type: string;

  /** Root Three.js object for transform updates */
  readonly object: THREE.Object3D;

  /** Optional animation mixer for animated entities */
  readonly mixer?: THREE.AnimationMixer;

  /**
   * Called each frame with interpolated transform from physics
   * Entity can apply additional logic after transform is set
   */
  onTransformUpdate?(
    position: THREE.Vector3,
    quaternion: THREE.Quaternion,
  ): void;

  /**
   * Called when new physics frame arrives
   * Use for input-based state changes (e.g., animation transitions)
   */
  onPhysicsFrame?(inputState: InputState): void;

  /**
   * Called each render frame
   * Use for time-based updates (e.g., shader uniforms)
   */
  onRenderFrame?(delta: number, elapsed: number): void;

  /**
   * Clean up all resources (geometry, materials, event listeners)
   */
  dispose(): void;
}

/**
 * Factory function signature for creating render components
 */
export type RenderComponentFactory = (
  id: EntityId,
  context: EntityContext,
  data?: Record<string, unknown>,
) => RenderComponent | Promise<RenderComponent>;
