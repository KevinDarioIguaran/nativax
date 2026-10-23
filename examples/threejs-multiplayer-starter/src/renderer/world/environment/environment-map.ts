import * as THREE from "three";
import { config } from "~/shared/config";
import type Resources from "../../systems/resources";
import type { DebugFolder } from "../../systems/debug";

/**
 * EnvironmentMap - Scene environment map for reflections and ambient lighting
 *
 * Applies a cube texture as the scene environment, affecting all PBR materials.
 * Controls the intensity of environment reflections.
 */
export default class EnvironmentMap {
  private scene: THREE.Scene;

  readonly texture: THREE.CubeTexture;

  // Debug-tunable intensity
  intensity = config.environmentMap.intensity;

  constructor(
    scene: THREE.Scene,
    resources: Resources,
    debugFolder: DebugFolder | null,
  ) {
    this.scene = scene;

    // Get environment map texture from resources
    this.texture = resources.items.environmentMapTexture as THREE.CubeTexture;
    this.texture.colorSpace = THREE.SRGBColorSpace;

    // Apply to scene
    this.scene.environment = this.texture;
    this.scene.environmentIntensity = this.intensity;

    // Update existing materials
    this.updateMaterials();

    // Add debug controls
    this.addDebug(debugFolder);
  }

  /**
   * Update all materials with current environment map settings
   */
  updateMaterials(): void {
    // Update global scene environment intensity (affects all PBR materials)
    this.scene.environmentIntensity = this.intensity;

    // Also update individual materials for any that override envMapIntensity
    this.scene.traverse((child) => {
      if (
        child instanceof THREE.Mesh &&
        child.material instanceof THREE.MeshStandardMaterial
      ) {
        child.material.envMap = this.texture;
        child.material.envMapIntensity = this.intensity;
        child.material.needsUpdate = true;
      }
    });
  }

  private addDebug(debugFolder: DebugFolder | null): void {
    if (!debugFolder) return;

    debugFolder
      .addBinding(this, "intensity", {
        label: "Env Map Intensity",
        min: 0,
        max: 4,
        step: 0.01,
      })
      .on("change", () => this.updateMaterials());
  }

  dispose(): void {
    this.scene.environment = null;
  }
}
