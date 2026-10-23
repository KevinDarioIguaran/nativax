import * as THREE from "three";
import type Resources from "../systems/resources";
import type Debug from "../systems/debug";
import type { DebugFolder } from "../systems/debug";
import { generateTerrainHeights } from "~/shared/utils";
import { config } from "~/shared/config";

export default class Floor {
  private scene: THREE.Scene;
  private debugFolder: DebugFolder | null = null;
  private colorTexture!: THREE.Texture;
  private normalTexture!: THREE.Texture;

  mesh: THREE.Mesh;
  repeatRate: number = 100; // Scaled for larger terrain (10x)

  constructor(scene: THREE.Scene, resources: Resources, debug?: Debug) {
    this.scene = scene;

    const { size, segments } = config.terrain;

    // Create geometry with segments for vertex displacement
    const geometry = new THREE.PlaneGeometry(size, size, segments, segments);

    // Generate heights using same config as physics (deterministic)
    const heights = generateTerrainHeights(config.terrain);

    // Displace vertices to match physics heightfield
    this.displaceVertices(geometry, heights, segments);

    // Recompute normals for correct lighting on slopes
    geometry.computeVertexNormals();

    const material = this.createMaterial(resources);

    this.mesh = new THREE.Mesh(geometry, material);
    this.mesh.rotation.x = -Math.PI * 0.5;
    this.mesh.receiveShadow = true;

    this.scene.add(this.mesh);

    // Setup debug controls
    if (debug) {
      this.addDebug(debug);
    }
  }

  private addDebug(debug: Debug): void {
    if (!debug.active || !debug.ui) return;

    this.debugFolder = debug.ui.addFolder({ title: "Floor" });

    this.debugFolder
      .addBinding(this, "repeatRate", {
        label: "Texture Repeat",
        min: 1,
        max: 50,
        step: 1,
      })
      .on("change", () => this.updateTextureRepeat());
  }

  private updateTextureRepeat(): void {
    this.colorTexture.repeat.set(this.repeatRate, this.repeatRate);
    this.normalTexture.repeat.set(this.repeatRate, this.repeatRate);
  }

  /**
   * Displace geometry vertices based on height data
   *
   * Critical: Three.js PlaneGeometry uses row-major order (X varies fastest),
   * while Rapier heightfield uses column-major order (Z varies fastest).
   * This method handles the index conversion.
   */
  private displaceVertices(
    geometry: THREE.PlaneGeometry,
    heights: Float32Array,
    segments: number,
  ): void {
    const positions = geometry.attributes.position;
    const rows = segments + 1;
    const cols = segments + 1;

    // PlaneGeometry vertices are in row-major order
    for (let i = 0; i < positions.count; i++) {
      // Convert PlaneGeometry index to grid coords
      const gridX = i % cols;
      const gridZ = Math.floor(i / cols);

      // Convert to column-major index for heights array (matches Rapier)
      const heightIndex = gridX * rows + gridZ;
      const height = heights[heightIndex];

      // Z is the "up" direction in PlaneGeometry before rotation
      positions.setZ(i, height);
    }

    positions.needsUpdate = true;
  }

  createMaterial(resources: Resources) {
    this.colorTexture = resources.items.grassColorTexture as THREE.Texture;
    this.colorTexture.colorSpace = THREE.SRGBColorSpace;
    this.colorTexture.repeat.set(this.repeatRate, this.repeatRate);
    this.colorTexture.wrapS = THREE.RepeatWrapping;
    this.colorTexture.wrapT = THREE.RepeatWrapping;

    this.normalTexture = resources.items.grassNormalTexture as THREE.Texture;
    this.normalTexture.repeat.set(this.repeatRate, this.repeatRate);
    this.normalTexture.wrapS = THREE.RepeatWrapping;
    this.normalTexture.wrapT = THREE.RepeatWrapping;

    return new THREE.MeshStandardMaterial({
      map: this.colorTexture,
      normalMap: this.normalTexture,
    });
  }

  dispose(): void {
    this.debugFolder?.dispose();
    this.mesh.geometry.dispose();
    (this.mesh.material as THREE.Material).dispose();
    this.scene.remove(this.mesh);
  }
}
