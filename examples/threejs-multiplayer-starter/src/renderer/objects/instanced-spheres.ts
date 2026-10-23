import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import InstancedMeshBase from "./instanced-mesh-base";

/**
 * GPU-instanced sphere rendering.
 * Extends InstancedMeshBase with sphere geometry and uniform radius scale.
 */
export default class InstancedSpheres extends InstancedMeshBase {
  constructor(scene: THREE.Scene, maxCount: number = 1000) {
    super(scene, maxCount, "InstancedSpheres");
  }

  protected createGeometry(): THREE.BufferGeometry {
    // Reduced from (16,12) to (12,8) for performance
    // 96 verts vs 192 - imperceptible at distance
    return new THREE.SphereGeometry(0.5, 12, 8);
  }

  protected createMaterial(): THREE.Material {
    return new THREE.MeshStandardMaterial({
      color: 0x4169e1,
      roughness: 0.6,
      metalness: 0.2,
    });
  }

  addSphere(entityId: EntityId, radius: number = 0.5): boolean {
    // Geometry has radius 0.5, so scale = radius * 2
    const scale = radius * 2;
    return this.add(entityId, new THREE.Vector3(scale, scale, scale));
  }

  addSpheres(entityIds: EntityId[], radii?: number[]): number {
    const vec3Scales = entityIds.map((_, i) => {
      const scale = (radii?.[i] ?? 0.5) * 2;
      return new THREE.Vector3(scale, scale, scale);
    });
    return this.addBatch(entityIds, vec3Scales);
  }

  removeSphere(entityId: EntityId): boolean {
    return this.remove(entityId);
  }

  removeSpheres(entityIds: EntityId[]): number {
    return this.removeBatch(entityIds);
  }
}
