import RAPIER from "@dimforge/rapier3d-compat";
import type {
  EntityId,
  Transform,
  FloatingCapsuleConfig,
  MovementInput,
  PlayerStateCallback,
} from "~/shared/types";
import type { DebugPlayerUpdate } from "~/shared/debug-config";
import { config } from "~/shared/config";

/**
 * FloatingCapsuleController - Dynamic rigidbody-based character controller
 *
 * Uses spring-damper forces to float above ground, impulse-based movement,
 * and locked rotations to stay upright. Inspired by:
 * - Toyful Games' Very Very Valet
 * - pmndrs/ecctrl library
 *
 * Key physics concepts:
 * 1. Floating Force: Spring-damper to maintain hover height
 * 2. Movement Force: Impulse-based acceleration toward target velocity
 * 3. Jump Impulse: Vertical impulse with coyote time and input buffering
 */
export default class FloatingCapsuleController {
  private world: RAPIER.World;
  private body: RAPIER.RigidBody;
  private collider: RAPIER.Collider;
  private entityId: EntityId;
  private config: FloatingCapsuleConfig;

  // Input state
  private input: MovementInput = {
    forward: false,
    backward: false,
    left: false,
    right: false,
    jump: false,
    sprint: false,
  };
  private rotationY = 0;

  // Ground detection state
  private isGrounded = false;
  private lastGroundedTime = 0;
  private jumpBufferedTime = 0;
  private hasJumped = false;
  private currentGroundDistance = 0;
  private lastVerticalVelocity = 0;

  // Grace period to prevent animation/audio jitter on bumpy terrain
  // Player must be airborne for this duration before triggering airborne state
  private readonly AIRBORNE_GRACE_MS = 100;
  private lastUngroundedTime = 0;
  private isAirborneForAnimation = false;

  // Audio callback for jump/land events
  private playerStateCallback: PlayerStateCallback | null = null;

  // Movement settings from config
  private readonly turnSpeed = config.player.turnSpeed;

  constructor(
    world: RAPIER.World,
    id: EntityId,
    transform: Transform,
    controllerConfig: FloatingCapsuleConfig,
  ) {
    this.world = world;
    this.entityId = id;
    this.config = controllerConfig;

    // Create DYNAMIC rigid body (not kinematic!)
    const bodyDesc = RAPIER.RigidBodyDesc.dynamic()
      .setTranslation(
        transform.position.x,
        transform.position.y,
        transform.position.z,
      )
      .setLinearDamping(controllerConfig.linearDamping)
      .setAngularDamping(controllerConfig.angularDamping)
      // Lock rotation on X and Z axes to prevent tipping
      .lockRotations();

    this.body = world.createRigidBody(bodyDesc);

    // Create capsule collider
    const colliderDesc = RAPIER.ColliderDesc.capsule(
      controllerConfig.halfHeight,
      controllerConfig.radius,
    )
      .setFriction(controllerConfig.friction)
      .setMass(controllerConfig.mass);

    // Offset collider so body position = feet position
    const totalHalfHeight =
      controllerConfig.halfHeight + controllerConfig.radius;
    colliderDesc.setTranslation(0, totalHalfHeight, 0);

    this.collider = world.createCollider(colliderDesc, this.body);

    // Enable collision events for audio (player collisions with objects)
    this.collider.setActiveEvents(RAPIER.ActiveEvents.COLLISION_EVENTS);

    // Initialize rotation from transform
    this.rotationY = this.quaternionToYRotation(transform.rotation);
  }

  /**
   * Set current input state
   */
  setInput(input: MovementInput): void {
    this.input = input;
  }

  /**
   * Set callback for player state events (jump/land)
   */
  setPlayerStateCallback(callback: PlayerStateCallback): void {
    this.playerStateCallback = callback;
  }

  /**
   * Update controller config from debug UI
   */
  updateConfig(update: DebugPlayerUpdate): void {
    if (update.springStrength !== undefined) {
      this.config.springStrength = update.springStrength;
    }
    if (update.springDamping !== undefined) {
      this.config.springDamping = update.springDamping;
    }
    if (update.moveForce !== undefined) {
      this.config.moveForce = update.moveForce;
    }
    if (update.jumpForce !== undefined) {
      this.config.jumpForce = update.jumpForce;
    }
    if (update.floatingDistance !== undefined) {
      this.config.floatingDistance = update.floatingDistance;
    }
    if (update.maxVelocity !== undefined) {
      this.config.maxVelocity = update.maxVelocity;
    }
  }

  /**
   * Main update - called each physics step
   */
  update(deltaSeconds: number): void {
    const now = performance.now();
    const vel = this.body.linvel();

    // 1. Ground detection via raycast
    this.detectGround();

    // 2. Update airborne state with grace period (prevents jitter on bumps)
    this.updateAirborneState(now);

    // 3. Detect landing (was airborne for animation, now grounded)
    if (this.isGrounded && this.isAirborneForAnimation) {
      this.isAirborneForAnimation = false;
      this.emitLandEvent();
    }

    // 4. Handle jump input buffering
    this.handleJumpBuffer(now);

    // 5. Apply floating force (spring-damper)
    this.applyFloatingForce();

    // 6. Apply movement forces
    this.applyMovementForces();

    // 7. Handle jump
    this.handleJump(now);

    // 8. Apply rotation
    this.applyRotation(deltaSeconds);

    // 9. Clamp velocity
    this.clampVelocity();

    // Update state for next frame
    this.lastVerticalVelocity = vel.y;
  }

  /**
   * Update airborne state with grace period to prevent jitter on bumpy terrain.
   * Player must be ungrounded for AIRBORNE_GRACE_MS before being considered airborne.
   * This prevents animation flickering and false landing sounds on small bumps.
   */
  private updateAirborneState(now: number): void {
    if (this.isGrounded) {
      // Reset ungrounded timer when on ground
      this.lastUngroundedTime = 0;
    } else {
      // Start timing when we leave ground
      if (this.lastUngroundedTime === 0) {
        this.lastUngroundedTime = now;
      }

      // Only consider airborne after grace period (unless we jumped)
      const airborneTime = now - this.lastUngroundedTime;
      if (this.hasJumped || airborneTime >= this.AIRBORNE_GRACE_MS) {
        this.isAirborneForAnimation = true;
      }
    }
  }

  /**
   * Emit landing event for audio
   */
  private emitLandEvent(): void {
    if (!this.playerStateCallback) return;

    const pos = this.body.translation();
    // Calculate intensity based on how fast we were falling
    const fallSpeed = Math.abs(this.lastVerticalVelocity);
    const intensity = Math.min(
      fallSpeed / config.audio.player.landIntensityThreshold,
      1.0,
    );

    // Only emit if we had significant falling velocity
    if (fallSpeed > 0.5) {
      this.playerStateCallback({
        type: "land",
        entityId: this.entityId,
        position: { x: pos.x, y: pos.y, z: pos.z },
        intensity,
      });
    }
  }

  /**
   * Emit jump event for audio
   */
  private emitJumpEvent(): void {
    if (!this.playerStateCallback) return;

    const pos = this.body.translation();
    this.playerStateCallback({
      type: "jump",
      entityId: this.entityId,
      position: { x: pos.x, y: pos.y, z: pos.z },
    });
  }

  /**
   * Ground detection using raycast
   */
  private detectGround(): void {
    const pos = this.body.translation();
    const rayOrigin = new RAPIER.Vector3(pos.x, pos.y, pos.z);
    const rayDir = new RAPIER.Vector3(0, -1, 0);

    const ray = new RAPIER.Ray(rayOrigin, rayDir);

    const rayResult = this.world.castRay(
      ray,
      this.config.rayLength,
      true, // solid
      RAPIER.QueryFilterFlags.EXCLUDE_SENSORS,
      undefined,
      this.collider, // exclude self
    );

    if (rayResult) {
      const hitDistance = rayResult.timeOfImpact;
      this.currentGroundDistance = hitDistance;
      const threshold =
        this.config.floatingDistance + this.config.groundedThreshold;

      this.isGrounded = hitDistance <= threshold;

      if (this.isGrounded) {
        this.lastGroundedTime = performance.now();
        this.hasJumped = false;
      }
    } else {
      this.isGrounded = false;
      this.currentGroundDistance = this.config.rayLength;
    }
  }

  /**
   * Floating Force - Spring-Damper System
   *
   * Formula: F = springK * (targetDist - currentDist) - dampingC * velocityY
   */
  private applyFloatingForce(): void {
    // Only apply floating force when within ray range
    if (this.currentGroundDistance >= this.config.rayLength) return;

    const vel = this.body.linvel();

    const currentDistance = this.currentGroundDistance;
    const targetDistance = this.config.floatingDistance;

    // Spring force: push up when too close, pull down when too far
    const displacement = targetDistance - currentDistance;
    const springForce = this.config.springStrength * displacement;

    // Damping force: resist vertical velocity
    const dampingForce = -this.config.springDamping * vel.y;

    // Combined floating force
    const floatingForce = springForce + dampingForce;

    // Apply as impulse
    this.body.applyImpulse(new RAPIER.Vector3(0, floatingForce, 0), true);
  }

  /**
   * Movement Forces - Impulse-based with acceleration
   */
  private applyMovementForces(): void {
    const vel = this.body.linvel();

    // Calculate desired movement direction (world space)
    let moveX = 0;
    let moveZ = 0;

    if (this.input.forward) {
      moveX += Math.sin(this.rotationY);
      moveZ += Math.cos(this.rotationY);
    }
    // Note: backward movement intentionally disabled - forward-only movement

    // Normalize if moving diagonally
    const length = Math.sqrt(moveX * moveX + moveZ * moveZ);
    if (length > 0) {
      moveX /= length;
      moveZ /= length;
    }

    // Calculate target velocity
    let speed = this.config.moveForce;
    if (this.input.sprint) {
      speed *= this.config.sprintMultiplier;
    }

    // Reduce control in air
    if (!this.isGrounded && !this.isInCoyoteTime()) {
      speed *= this.config.airControlMultiplier;
    }

    const targetVelX = moveX * speed;
    const targetVelZ = moveZ * speed;

    // Calculate required acceleration (difference from current velocity)
    const accX = targetVelX - vel.x;
    const accZ = targetVelZ - vel.z;

    // Apply force: F = m * a (using impulse directly with tuning factor)
    const forceMultiplier = this.config.mass * 0.1;
    this.body.applyImpulse(
      new RAPIER.Vector3(accX * forceMultiplier, 0, accZ * forceMultiplier),
      true,
    );
  }

  /**
   * Handle jump with coyote time and input buffering
   */
  private handleJump(now: number): void {
    const canJump = this.isGrounded || this.isInCoyoteTime();
    const wantsToJump = this.input.jump && !this.hasJumped;
    const hasBufferedJump =
      this.jumpBufferedTime > 0 &&
      now - this.jumpBufferedTime < this.config.jumpBufferTime;

    if (canJump && (wantsToJump || hasBufferedJump)) {
      // Reset vertical velocity before jumping for consistent height
      const vel = this.body.linvel();
      this.body.setLinvel(new RAPIER.Vector3(vel.x, 0, vel.z), true);

      // Apply jump impulse
      const jumpImpulse = this.config.jumpForce * this.config.mass;
      this.body.applyImpulse(new RAPIER.Vector3(0, jumpImpulse, 0), true);

      this.hasJumped = true;
      this.jumpBufferedTime = 0;
      this.isGrounded = false;

      // Emit jump audio event
      this.emitJumpEvent();
    }
  }

  /**
   * Buffer jump input for landing
   */
  private handleJumpBuffer(now: number): void {
    if (this.input.jump && !this.isGrounded && !this.hasJumped) {
      this.jumpBufferedTime = now;
    }
  }

  /**
   * Check if within coyote time window
   */
  private isInCoyoteTime(): boolean {
    if (this.isGrounded) return false;
    return performance.now() - this.lastGroundedTime < this.config.coyoteTime;
  }

  /**
   * Apply rotation based on input
   * Uses analog turnAxis for mobile joystick, falls back to boolean for keyboard
   */
  private applyRotation(deltaSeconds: number): void {
    let turn = 0;

    // Use analog turnAxis if provided (mobile joystick)
    if (this.input.turnAxis !== undefined && this.input.turnAxis !== 0) {
      turn = -this.input.turnAxis; // Negative because positive = right = decrease rotationY
    } else {
      // Fall back to boolean for keyboard (desktop)
      if (this.input.left) turn = 1;
      if (this.input.right) turn = -1;
    }

    this.rotationY += this.turnSpeed * turn * deltaSeconds;

    // Set rotation directly (Y-axis only)
    const halfAngle = this.rotationY / 2;
    this.body.setRotation(
      { x: 0, y: Math.sin(halfAngle), z: 0, w: Math.cos(halfAngle) },
      true,
    );
  }

  /**
   * Clamp horizontal velocity to max (higher when sprinting)
   */
  private clampVelocity(): void {
    const vel = this.body.linvel();
    const horizontalSpeed = Math.sqrt(vel.x * vel.x + vel.z * vel.z);

    // Use higher max velocity when sprinting
    const maxVel = this.input.sprint
      ? this.config.sprintMaxVelocity
      : this.config.maxVelocity;

    if (horizontalSpeed > maxVel) {
      const scale = maxVel / horizontalSpeed;
      this.body.setLinvel(
        new RAPIER.Vector3(vel.x * scale, vel.y, vel.z * scale),
        true,
      );
    }
  }

  /**
   * Get the rigid body
   */
  getBody(): RAPIER.RigidBody {
    return this.body;
  }

  /**
   * Get the collider
   */
  getCollider(): RAPIER.Collider {
    return this.collider;
  }

  /**
   * Get the entity ID
   */
  getEntityId(): EntityId {
    return this.entityId;
  }

  /**
   * Get grounded state for animation/audio (uses grace period to prevent jitter)
   */
  getIsGrounded(): boolean {
    // Return stable state: grounded OR not yet confirmed airborne
    return this.isGrounded || !this.isAirborneForAnimation;
  }

  /**
   * Convert quaternion to Y-axis rotation (yaw)
   */
  private quaternionToYRotation(q: {
    x: number;
    y: number;
    z: number;
    w: number;
  }): number {
    const siny_cosp = 2 * (q.w * q.y + q.z * q.x);
    const cosy_cosp = 1 - 2 * (q.x * q.x + q.y * q.y);
    return Math.atan2(siny_cosp, cosy_cosp);
  }
}
