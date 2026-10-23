import * as THREE from "three";
import { config } from "~/shared/config";
import type { DebugFolder } from "../../systems/debug";

/**
 * SunLight - Directional light with shadows that follows a target
 *
 * Creates a directional light positioned at an offset from a target position.
 * The light and its shadow camera follow the target to maintain consistent
 * shadow coverage as the player moves through the scene.
 */
export default class SunLight {
  private scene: THREE.Scene;

  readonly light: THREE.DirectionalLight;

  // Light offset from target (public for debug binding)
  offset = new THREE.Vector3(
    config.sunLight.offset.x,
    config.sunLight.offset.y,
    config.sunLight.offset.z,
  );

  // Shadow settings (public for debug binding)
  shadowCameraSize = config.sunLight.shadow.cameraSize;
  shadowNormalBias = config.sunLight.shadow.normalBias;

  constructor(scene: THREE.Scene, debugFolder: DebugFolder | null) {
    this.scene = scene;

    // Create directional light
    this.light = new THREE.DirectionalLight(
      config.sunLight.color,
      config.sunLight.intensity,
    );

    // Configure shadows
    if (config.sunLight.shadow.enabled) {
      this.light.castShadow = true;
      this.light.shadow.mapSize.set(
        config.sunLight.shadow.mapSize,
        config.sunLight.shadow.mapSize,
      );
      this.light.shadow.normalBias = this.shadowNormalBias;
      this.updateShadowCamera();
    }

    // Position light at offset
    this.light.position.copy(this.offset);

    // Add target for shadow to follow (will be updated each frame)
    this.light.target = new THREE.Object3D();
    this.scene.add(this.light.target);
    this.scene.add(this.light);

    // Add debug controls
    this.addDebug(debugFolder);
  }

  /**
   * Update shadow camera frustum based on current settings
   */
  updateShadowCamera(): void {
    this.light.shadow.camera.left = -this.shadowCameraSize;
    this.light.shadow.camera.right = this.shadowCameraSize;
    this.light.shadow.camera.top = this.shadowCameraSize;
    this.light.shadow.camera.bottom = -this.shadowCameraSize;
    this.light.shadow.camera.near = config.sunLight.shadow.near;
    this.light.shadow.camera.far = config.sunLight.shadow.far;
    this.light.shadow.camera.updateProjectionMatrix();
  }

  /**
   * Update light to follow a target position
   * Call this each frame with the player/camera target position
   */
  updateTarget(targetPosition: THREE.Vector3): void {
    // Move light to follow target, maintaining offset
    this.light.position.copy(targetPosition).add(this.offset);

    // Point light at target
    this.light.target.position.copy(targetPosition);
  }

  private addDebug(debugFolder: DebugFolder | null): void {
    if (!debugFolder) return;

    debugFolder.addBinding(this.light, "intensity", {
      label: "Sun Intensity",
      min: 0,
      max: 10,
      step: 0.1,
    });

    debugFolder.addBinding(this.offset, "x", {
      label: "Sun Offset X",
      min: -50,
      max: 50,
      step: 0.5,
    });

    debugFolder.addBinding(this.offset, "y", {
      label: "Sun Offset Y",
      min: 0,
      max: 100,
      step: 0.5,
    });

    debugFolder.addBinding(this.offset, "z", {
      label: "Sun Offset Z",
      min: -50,
      max: 50,
      step: 0.5,
    });

    // Shadow controls
    debugFolder
      .addBinding(this, "shadowCameraSize", {
        label: "Shadow Size",
        min: 5,
        max: 50,
        step: 1,
      })
      .on("change", () => this.updateShadowCamera());

    debugFolder
      .addBinding(this, "shadowNormalBias", {
        label: "Shadow Bias",
        min: 0,
        max: 0.1,
        step: 0.001,
      })
      .on("change", () => {
        this.light.shadow.normalBias = this.shadowNormalBias;
      });
  }

  dispose(): void {
    this.light.dispose();
    this.scene.remove(this.light);
    this.scene.remove(this.light.target);
  }
}
