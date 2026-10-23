import type { SerializedInputEvent } from "~/shared/types";

/**
 * InputState - Tracks current input state in worker
 *
 * Maintains a snapshot of pressed keys that can be queried
 * during the update loop, rather than reacting to individual events.
 */
export default class InputState {
  private keys: Set<string> = new Set();

  /**
   * Handle an input event and update state
   */
  handleEvent(event: SerializedInputEvent): void {
    if (event.type === "keydown") {
      this.keys.add(event.key.toLowerCase());
    } else if (event.type === "keyup") {
      this.keys.delete(event.key.toLowerCase());
    }
  }

  /**
   * Check if a key is currently pressed
   */
  isKeyDown(key: string): boolean {
    return this.keys.has(key.toLowerCase());
  }

  /**
   * Get normalized movement vector from WASD keys
   * Returns values in range [-1, 1] for x and z
   */
  getMovementVector(): { x: number; z: number } {
    let x = 0;
    let z = 0;

    if (this.isKeyDown("w")) z -= 1;
    if (this.isKeyDown("s")) z += 1;
    if (this.isKeyDown("a")) x -= 1;
    if (this.isKeyDown("d")) x += 1;

    // Normalize diagonal movement
    if (x !== 0 && z !== 0) {
      const length = Math.sqrt(x * x + z * z);
      x /= length;
      z /= length;
    }

    return { x, z };
  }

  /**
   * Check if any movement key is pressed
   */
  isMoving(): boolean {
    return (
      this.isKeyDown("w") ||
      this.isKeyDown("a") ||
      this.isKeyDown("s") ||
      this.isKeyDown("d")
    );
  }

  /**
   * Clear all pressed keys
   */
  clear(): void {
    this.keys.clear();
  }
}
