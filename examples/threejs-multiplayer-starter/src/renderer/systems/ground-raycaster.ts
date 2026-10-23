import * as THREE from "three";
import type { RaycastResult } from "~/shared/types";

/**
 * GroundRaycaster - Handles raycasting to an invisible ground plane
 *
 * Used for click-to-spawn mechanics where we need to find:
 * - The point on the ground plane where the user clicked
 * - The camera origin and ray direction for projectile spawning
 */
export default class GroundRaycaster {
  private groundPlane: THREE.Plane;
  private raycaster: THREE.Raycaster;

  constructor() {
    // Invisible ground plane at Y=0, facing up
    this.groundPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.raycaster = new THREE.Raycaster();
  }

  /**
   * Raycast from screen coordinates to invisible ground plane at Y=0
   * @param normalizedX Normalized screen X (0-1, left to right)
   * @param normalizedY Normalized screen Y (0-1, top to bottom)
   * @param camera The camera to raycast from
   * @returns Hit info including point, camera origin, and ray direction, or null if no hit
   */
  raycastGround(
    normalizedX: number,
    normalizedY: number,
    camera: THREE.PerspectiveCamera,
  ): RaycastResult | null {
    // Convert normalized coords (0-1) to NDC (-1 to 1)
    const ndc = new THREE.Vector2(
      normalizedX * 2 - 1,
      -(normalizedY * 2 - 1), // Y inverted (screen Y goes down, NDC Y goes up)
    );

    // Set ray from camera through the NDC point
    this.raycaster.setFromCamera(ndc, camera);

    // Intersect with ground plane
    const target = new THREE.Vector3();
    const hit = this.raycaster.ray.intersectPlane(this.groundPlane, target);

    if (!hit) return null;

    const origin = camera.position;
    const direction = this.raycaster.ray.direction;

    return {
      point: { x: target.x, y: target.y, z: target.z },
      origin: { x: origin.x, y: origin.y, z: origin.z },
      direction: { x: direction.x, y: direction.y, z: direction.z },
    };
  }

  dispose(): void {
    // Nothing to dispose, but included for consistency
  }
}
