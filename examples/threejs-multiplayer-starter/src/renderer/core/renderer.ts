import * as THREE from "three";
import type { ViewportSize } from "~/shared/types";
import { config } from "~/shared/config";
import type Debug from "../systems/debug";
import type { DebugFolder } from "../systems/debug";

/**
 * Renderer - WebGLRenderer wrapper
 *
 * Responsible for:
 * - Creating and configuring THREE.WebGLRenderer
 * - Handling viewport resizing
 * - Rendering scene/camera pairs
 *
 * This is a thin wrapper that exposes the WebGLRenderer as `instance`
 * for cases where direct access is needed.
 *
 * Note: Three.js WebGLRenderer accepts OffscreenCanvas natively since r128+.
 * The type assertion is needed due to @types/three not including OffscreenCanvas
 * in the WebGLRendererParameters.canvas type definition.
 */
class Renderer {
  readonly instance: THREE.WebGLRenderer;
  private debugFolder: DebugFolder | null = null;

  // Debug state for color binding (needs to be an object property)
  private debugState = {
    clearColor: config.renderer.clearColor,
  };

  constructor(canvas: OffscreenCanvas, viewport: ViewportSize, debug?: Debug) {
    // OffscreenCanvas is natively supported by Three.js WebGLRenderer
    // Type assertion needed due to incomplete @types/three definitions
    this.instance = new THREE.WebGLRenderer({
      canvas: canvas as unknown as HTMLCanvasElement,
      antialias: true,
      powerPreference: "high-performance",
    });

    // Tone mapping for realistic lighting
    this.instance.toneMapping = THREE.CineonToneMapping;
    this.instance.toneMappingExposure = config.renderer.toneMappingExposure;

    // Shadow configuration
    this.instance.shadowMap.enabled = config.sunLight.shadow.enabled;
    this.instance.shadowMap.type = THREE.PCFSoftShadowMap;

    // Background color
    this.instance.setClearColor(config.renderer.clearColor);

    // Viewport setup
    const pixelRatio = Math.min(
      viewport.pixelRatio,
      config.renderer.maxPixelRatio,
    );
    this.instance.setPixelRatio(pixelRatio);
    this.instance.setSize(viewport.width, viewport.height, false);

    // Setup debug controls
    if (debug) {
      this.addDebug(debug);
    }
  }

  private addDebug(debug: Debug): void {
    if (!debug.active || !debug.ui) return;

    this.debugFolder = debug.ui.addFolder({ title: "Renderer" });

    // Tone mapping exposure
    this.debugFolder.addBinding(this.instance, "toneMappingExposure", {
      label: "Exposure",
      min: 0,
      max: 3,
      step: 0.01,
    });

    // Clear color (background)
    this.debugFolder
      .addBinding(this.debugState, "clearColor", {
        label: "Clear Color",
      })
      .on("change", () => {
        this.instance.setClearColor(this.debugState.clearColor);
      });

    // Shadow map toggle
    this.debugFolder.addBinding(this.instance.shadowMap, "enabled", {
      label: "Shadows",
    });
  }

  resize(viewport: ViewportSize): void {
    this.instance.setSize(viewport.width, viewport.height, false);
    const pixelRatio = Math.min(
      viewport.pixelRatio,
      config.renderer.maxPixelRatio,
    );
    this.instance.setPixelRatio(pixelRatio);
  }

  render(scene: THREE.Scene, camera: THREE.Camera): void {
    this.instance.render(scene, camera);
  }

  dispose(): void {
    this.debugFolder?.dispose();

    // Force context loss to release WebGL resources immediately
    // This helps prevent context exhaustion on rapid page refreshes
    const gl = this.instance.getContext();
    const ext = gl.getExtension("WEBGL_lose_context");
    ext?.loseContext();

    this.instance.dispose();
  }
}

export default Renderer;
