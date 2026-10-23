import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import InstancedMeshBase from "./instanced-mesh-base";

/**
 * GPU-instanced box rendering.
 * Extends InstancedMeshBase with box geometry and per-instance Vector3 scale.
 */
export default class InstancedBoxes extends InstancedMeshBase {
  constructor(scene: THREE.Scene, maxCount: number = 1000) {
    super(scene, maxCount, "InstancedBoxes");
  }

  protected createGeometry(): THREE.BufferGeometry {
    return new THREE.BoxGeometry(1, 1, 1);
  }

  protected createMaterial(): THREE.Material {
    return new THREE.MeshStandardMaterial({
      color: 0x8b4513,
      roughness: 0.7,
      metalness: 0.1,
    });
  }

  addBox(
    entityId: EntityId,
    scale: { x: number; y: number; z: number } = { x: 1, y: 1, z: 1 },
  ): boolean {
    return this.add(entityId, new THREE.Vector3(scale.x, scale.y, scale.z));
  }

  addBoxes(
    entityIds: EntityId[],
    scales?: Array<{ x: number; y: number; z: number }>,
  ): number {
    const vec3Scales = entityIds.map((_, i) => {
      const s = scales?.[i] ?? { x: 1, y: 1, z: 1 };
      return new THREE.Vector3(s.x, s.y, s.z);
    });
    return this.addBatch(entityIds, vec3Scales);
  }

  removeBox(entityId: EntityId): boolean {
    return this.remove(entityId);
  }

  removeBoxes(entityIds: EntityId[]): number {
    return this.removeBatch(entityIds);
  }
}
