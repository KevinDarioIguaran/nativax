import * as THREE from "three";
import { config } from "~/shared/config";
import type { DebugFolder } from "../../systems/debug";

/**
 * Fog - Scene fog with debug controls
 *
 * Creates linear fog that fades objects between near and far distances.
 * Uses the same color as the clear color for seamless blending.
 */
export default class Fog {
  private scene: THREE.Scene;
  private fog: THREE.Fog | null = null;

  // Debug-tunable values
  near = config.fog.near;
  far = config.fog.far;

  constructor(scene: THREE.Scene, debugFolder: DebugFolder | null) {
    this.scene = scene;

    if (!config.fog.enabled) return;

    // Create fog
    this.fog = new THREE.Fog(config.fog.color, this.near, this.far);
    this.scene.fog = this.fog;

    // Add debug controls
    this.addDebug(debugFolder);
  }

  private addDebug(debugFolder: DebugFolder | null): void {
    if (!debugFolder || !this.fog) return;

    debugFolder
      .addBinding(this, "near", {
        label: "Fog Near",
        min: 0,
        max: 200, // Scaled for larger terrain
        step: 5,
      })
      .on("change", () => {
        if (this.fog) this.fog.near = this.near;
      });

    debugFolder
      .addBinding(this, "far", {
        label: "Fog Far",
        min: 50,
        max: 500, // Scaled for larger terrain
        step: 10,
      })
      .on("change", () => {
        if (this.fog) this.fog.far = this.far;
      });
  }

  dispose(): void {
    this.scene.fog = null;
  }
}
