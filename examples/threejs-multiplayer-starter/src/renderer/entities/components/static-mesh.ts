import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import type { RenderComponent, EntityContext } from "../types";

/**
 * Static mesh configuration
 */
export interface StaticMeshData {
  geometry?: "box" | "sphere" | "cylinder";
  size?: { x: number; y: number; z: number };
  color?: number;
}

/**
 * StaticMeshEntity - Generic static mesh (default/fallback entity type)
 *
 * Creates a simple colored mesh for entities without a specific component.
 * Useful for debugging or placeholder objects.
 */
export class StaticMeshEntity implements RenderComponent {
  readonly id: EntityId;
  readonly type = "static-mesh";
  readonly object: THREE.Mesh;

  private geometry: THREE.BufferGeometry;
  private material: THREE.Material;

  constructor(id: EntityId, context: EntityContext, data: StaticMeshData = {}) {
    this.id = id;

    const size = data.size ?? { x: 1, y: 1, z: 1 };
    const color = data.color ?? 0x888888;

    switch (data.geometry) {
      case "sphere":
        this.geometry = new THREE.SphereGeometry(size.x / 2, 32, 32);
        break;
      case "cylinder":
        this.geometry = new THREE.CylinderGeometry(
          size.x / 2,
          size.x / 2,
          size.y,
          32,
        );
        break;
      default:
        this.geometry = new THREE.BoxGeometry(size.x, size.y, size.z);
    }

    this.material = new THREE.MeshStandardMaterial({ color });
    this.object = new THREE.Mesh(this.geometry, this.material);
    this.object.castShadow = true;
    this.object.receiveShadow = true;

    context.scene.add(this.object);
  }

  dispose(): void {
    this.geometry.dispose();
    this.material.dispose();
    this.object.parent?.remove(this.object);
  }
}

/**
 * Factory function for creating StaticMeshEntity
 */
export function createStaticMeshEntity(
  id: EntityId,
  context: EntityContext,
  data?: Record<string, unknown>,
): RenderComponent {
  return new StaticMeshEntity(id, context, data as StaticMeshData);
}
