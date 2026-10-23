/**
 * GroundStateTracker - Manages grounded/airborne state with grace period
 *
 * Consolidates ground detection state and provides stable animation state.
 * Grace period prevents jitter on bumpy terrain.
 */
export class GroundStateTracker {
  // Core state
  private _isGrounded = false;
  private lastGroundedTime = 0;
  private currentGroundDistance = 0;

  // Airborne grace period (prevents animation jitter on bumps)
  private lastUngroundedTime = 0;
  private isAirborneForAnimation = false;
  private readonly AIRBORNE_GRACE_MS = 100;

  // Jump state
  private jumpBufferedTime = 0;
  private hasJumped = false;

  // Config
  private readonly floatingDistance: number;
  private readonly groundedThreshold: number;
  private readonly coyoteTime: number;
  private readonly jumpBufferTime: number;
  private readonly rayLength: number;

  constructor(config: {
    floatingDistance: number;
    groundedThreshold: number;
    coyoteTime: number;
    jumpBufferTime: number;
    rayLength: number;
  }) {
    this.floatingDistance = config.floatingDistance;
    this.groundedThreshold = config.groundedThreshold;
    this.coyoteTime = config.coyoteTime;
    this.jumpBufferTime = config.jumpBufferTime;
    this.rayLength = config.rayLength;
  }

  /**
   * Update ground state from raycast result
   * @param hitDistance Distance to ground from raycast, or null if no hit
   */
  updateGroundDetection(hitDistance: number | null): void {
    if (hitDistance !== null) {
      this.currentGroundDistance = hitDistance;
      const threshold = this.floatingDistance + this.groundedThreshold;
      this._isGrounded = hitDistance <= threshold;

      if (this._isGrounded) {
        this.lastGroundedTime = performance.now();
        this.hasJumped = false;
      }
    } else {
      this._isGrounded = false;
      this.currentGroundDistance = this.rayLength;
    }
  }

  /**
   * Update airborne animation state with grace period
   * Must be called after updateGroundDetection
   * @param hasJumped Whether player initiated a jump
   * @returns True if landing just occurred (for audio)
   */
  updateAirborneState(hasJumped: boolean): boolean {
    const now = performance.now();
    const wasAirborne = this.isAirborneForAnimation;

    if (this._isGrounded) {
      this.lastUngroundedTime = 0;

      // Check for landing
      if (wasAirborne) {
        this.isAirborneForAnimation = false;
        return true; // Landing occurred
      }
    } else {
      // Start timing when leaving ground
      if (this.lastUngroundedTime === 0) {
        this.lastUngroundedTime = now;
      }

      // Only consider airborne after grace period (unless jumped)
      const airborneTime = now - this.lastUngroundedTime;
      if (hasJumped || airborneTime >= this.AIRBORNE_GRACE_MS) {
        this.isAirborneForAnimation = true;
      }
    }

    return false;
  }

  /**
   * Buffer jump input for landing
   */
  bufferJumpInput(wantsJump: boolean): void {
    if (wantsJump && !this._isGrounded && !this.hasJumped) {
      this.jumpBufferedTime = performance.now();
    }
  }

  /**
   * Check if jump should execute (grounded or coyote time, with buffer)
   */
  canJump(wantsJump: boolean): boolean {
    const now = performance.now();
    const canJump = this._isGrounded || this.isInCoyoteTime();
    const wantsToJump = wantsJump && !this.hasJumped;
    const hasBufferedJump =
      this.jumpBufferedTime > 0 &&
      now - this.jumpBufferedTime < this.jumpBufferTime;

    return canJump && (wantsToJump || hasBufferedJump);
  }

  /**
   * Mark jump as executed
   */
  onJump(): void {
    this.hasJumped = true;
    this.jumpBufferedTime = 0;
    this._isGrounded = false;
  }

  /**
   * Check if within coyote time window
   */
  isInCoyoteTime(): boolean {
    if (this._isGrounded) return false;
    return performance.now() - this.lastGroundedTime < this.coyoteTime;
  }

  // Getters
  get isGrounded(): boolean {
    return this._isGrounded;
  }

  get groundDistance(): number {
    return this.currentGroundDistance;
  }

  /**
   * Get stable grounded state for animation (uses grace period)
   */
  get isGroundedForAnimation(): boolean {
    return this._isGrounded || !this.isAirborneForAnimation;
  }

  get jumped(): boolean {
    return this.hasJumped;
  }
}
