import * as THREE from "three";
import type Resources from "../../systems/resources";
import type Debug from "../../systems/debug";
import type { DebugFolder } from "../../systems/debug";

// Environment components
import Fog from "./fog";
import SunLight from "./sun-light";
import EnvironmentMap from "./environment-map";

/**
 * Environment - Orchestrates scene environment components
 *
 * Creates and manages:
 * - Fog (atmospheric distance fade)
 * - SunLight (directional light with shadows)
 * - EnvironmentMap (reflections and ambient lighting)
 *
 * Each component is a separate class with its own debug controls,
 * following the dependency injection pattern.
 */
export default class Environment {
  private debugFolder: DebugFolder | null = null;

  // Environment components
  private fog: Fog;
  private sunLight: SunLight;
  private environmentMap: EnvironmentMap;

  constructor(scene: THREE.Scene, resources: Resources, debug: Debug) {
    // Create debug folder
    if (debug.active && debug.ui) {
      this.debugFolder = debug.ui.addFolder({ title: "Environment" });
    }

    // Create environment components with dependency injection
    this.fog = new Fog(scene, this.debugFolder);
    this.sunLight = new SunLight(scene, this.debugFolder);
    this.environmentMap = new EnvironmentMap(
      scene,
      resources,
      this.debugFolder,
    );
  }

  /**
   * Update sun light to follow a target position
   * Call this each frame with the player/camera target position
   */
  updateShadowTarget(targetPosition: THREE.Vector3): void {
    this.sunLight.updateTarget(targetPosition);
  }

  dispose(): void {
    this.fog.dispose();
    this.sunLight.dispose();
    this.environmentMap.dispose();
    this.debugFolder?.dispose();
  }
}
