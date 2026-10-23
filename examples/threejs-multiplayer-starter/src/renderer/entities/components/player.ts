import * as THREE from "three";
import type { EntityId, FootstepCallback } from "~/shared/types";
import type { SharedTransformBuffer } from "~/shared/buffers";
import { EntityFlags } from "~/shared/buffers";
import type { RenderComponent, EntityContext } from "../types";
import type InputState from "../../systems/input-state";
import { config } from "~/shared/config";
import Fox from "../../objects/fox";

/**
 * PlayerEntity - Player character with Fox model and animations
 *
 * Wraps Fox class with entity lifecycle hooks.
 * Handles animation state transitions based on input.
 */
export class PlayerEntity implements RenderComponent {
  readonly id: EntityId;
  readonly type = "player";
  readonly object: THREE.Object3D;
  readonly mixer: THREE.AnimationMixer;

  private fox: Fox;

  // Shared buffer for reading grounded state from physics
  private sharedBuffer: SharedTransformBuffer;

  // Footstep audio
  private footstepCallback: FootstepCallback | null = null;
  private lastFootstepTime = 0;
  private isMoving = false;
  private isRunning = false;

  constructor(id: EntityId, context: EntityContext) {
    this.id = id;
    this.fox = new Fox(context.scene, context.resources, context.debug);
    this.object = this.fox.model;
    this.mixer = this.fox.mixer;

    // Store buffer reference for reading grounded state
    this.sharedBuffer = context.sharedBuffer;
  }

  /**
   * Set callback for footstep events
   */
  setFootstepCallback(callback: FootstepCallback): void {
    this.footstepCallback = callback;
  }

  /**
   * Update animation state based on input and grounded state
   */
  onPhysicsFrame(inputState: InputState): void {
    // Read grounded state from physics via shared buffer
    // Look up index dynamically since entity map may not be built at construction time
    const entityIndex = this.sharedBuffer.getEntityIndex(this.id);
    const flags =
      entityIndex >= 0
        ? this.sharedBuffer.readEntityFlags(entityIndex)
        : EntityFlags.GROUNDED;
    const isGrounded = (flags & EntityFlags.GROUNDED) !== 0;

    const isForward = inputState.isKeyDown("w");
    // Note: backward (S key) intentionally disabled - forward-only movement
    const isTurnLeft = inputState.isKeyDown("a");
    const isTurnRight = inputState.isKeyDown("d");
    const isRunning = inputState.isKeyDown("shift");

    const isMoving = isForward;
    const isTurning = isTurnLeft || isTurnRight;

    // Track state for footsteps (only emit when grounded)
    this.isMoving = isGrounded && (isMoving || isTurning);
    this.isRunning = isRunning && isMoving;

    // Emit footstep events
    this.emitFootstepIfNeeded();

    // If airborne, play jumping animation (slow run)
    if (!isGrounded) {
      this.fox.play("jumping");
      return;
    }

    // Grounded animation logic
    if (isMoving) {
      this.fox.play(isRunning ? "running" : "walking");
    } else if (isTurning) {
      this.fox.play("walking");
    } else {
      this.fox.play("idle");
    }
  }

  /**
   * Emit footstep event based on movement timing
   */
  private emitFootstepIfNeeded(): void {
    if (!this.footstepCallback || !this.isMoving) return;

    const now = performance.now();
    const interval = this.isRunning
      ? config.audio.footsteps.runInterval
      : config.audio.footsteps.walkInterval;

    if (now - this.lastFootstepTime >= interval) {
      this.lastFootstepTime = now;

      const pos = this.object.position;
      this.footstepCallback({
        type: "footstep",
        entityId: this.id,
        position: { x: pos.x, y: pos.y, z: pos.z },
        intensity: this.isRunning ? 1.0 : 0.6,
      });
    }
  }

  dispose(): void {
    this.fox.dispose();
  }
}

/**
 * Factory function for creating PlayerEntity
 */
export function createPlayerEntity(
  id: EntityId,
  context: EntityContext,
): RenderComponent {
  return new PlayerEntity(id, context);
}
