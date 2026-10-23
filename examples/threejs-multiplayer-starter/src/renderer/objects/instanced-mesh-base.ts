import * as THREE from "three";
import type { EntityId } from "~/shared/types";

/**
 * Abstract base for GPU-instanced meshes.
 *
 * Features:
 * - Single draw call for hundreds of instances
 * - O(1) swap-with-last removal
 * - Per-instance scale tracking
 */
export default abstract class InstancedMeshBase {
  // Pre-allocated matrix for hiding instances (avoids allocation in hot paths)
  private static readonly zeroMatrix = new THREE.Matrix4().makeScale(0, 0, 0);

  protected scene: THREE.Scene;
  protected mesh: THREE.InstancedMesh | null = null;
  protected dummy = new THREE.Object3D();

  // Pre-allocated matrix for swap operations in remove()
  private tempMatrix = new THREE.Matrix4();

  protected entityIds: EntityId[] = [];
  protected entityIndexMap: Map<EntityId, number> = new Map();
  protected entityScales: Map<EntityId, THREE.Vector3> = new Map();

  protected activeCount = 0;
  protected readonly maxCount: number;
  protected readonly name: string;

  constructor(scene: THREE.Scene, maxCount: number, name: string) {
    this.scene = scene;
    this.maxCount = maxCount;
    this.name = name;
    this.createMesh();
  }

  protected abstract createGeometry(): THREE.BufferGeometry;
  protected abstract createMaterial(): THREE.Material;

  private createMesh(): void {
    const geometry = this.createGeometry();
    const material = this.createMaterial();

    this.mesh = new THREE.InstancedMesh(geometry, material, this.maxCount);

    // Initialize all instances invisible
    for (let i = 0; i < this.maxCount; i++) {
      this.mesh.setMatrixAt(i, InstancedMeshBase.zeroMatrix);
    }
    this.mesh.instanceMatrix.needsUpdate = true;

    this.mesh.castShadow = true;
    this.mesh.receiveShadow = true;
    this.mesh.frustumCulled = false;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);

    this.scene.add(this.mesh);
  }

  add(entityId: EntityId, scale: THREE.Vector3): boolean {
    if (!this.mesh) return false;

    if (this.activeCount >= this.maxCount) {
      console.warn(`[${this.name}] At max capacity of ${this.maxCount}`);
      return false;
    }

    const index = this.activeCount;
    this.entityIds[index] = entityId;
    this.entityIndexMap.set(entityId, index);
    this.entityScales.set(entityId, scale.clone());
    this.activeCount++;

    return true;
  }

  addBatch(entityIds: EntityId[], scales: THREE.Vector3[]): number {
    if (!this.mesh) return 0;

    const count = entityIds.length;
    const available = this.maxCount - this.activeCount;

    if (count > available) {
      console.warn(`[${this.name}] Can only add ${available} - would exceed max ${this.maxCount}`);
      return 0;
    }

    const startIndex = this.activeCount;
    for (let i = 0; i < count; i++) {
      const id = entityIds[i];
      const index = startIndex + i;
      this.entityIds[index] = id;
      this.entityIndexMap.set(id, index);
      this.entityScales.set(id, scales[i].clone());
    }

    this.activeCount += count;
    return count;
  }

  remove(entityId: EntityId): boolean {
    if (!this.mesh) return false;

    const index = this.entityIndexMap.get(entityId);
    if (index === undefined) return false;

    const lastIndex = this.activeCount - 1;

    if (index !== lastIndex) {
      const lastEntityId = this.entityIds[lastIndex];

      // Swap matrix using pre-allocated tempMatrix
      this.mesh.getMatrixAt(lastIndex, this.tempMatrix);
      this.mesh.setMatrixAt(index, this.tempMatrix);

      // Update tracking
      this.entityIds[index] = lastEntityId;
      this.entityIndexMap.set(lastEntityId, index);
    }

    // Hide last slot using static zeroMatrix
    this.mesh.setMatrixAt(lastIndex, InstancedMeshBase.zeroMatrix);

    this.entityIndexMap.delete(entityId);
    this.entityScales.delete(entityId);
    this.activeCount--;

    this.mesh.instanceMatrix.needsUpdate = true;
    return true;
  }

  removeBatch(entityIds: EntityId[]): number {
    let removed = 0;
    for (const id of entityIds) {
      if (this.remove(id)) removed++;
    }
    return removed;
  }

  updateInstance(entityId: EntityId, position: THREE.Vector3, quaternion: THREE.Quaternion): void {
    if (!this.mesh) return;

    const index = this.entityIndexMap.get(entityId);
    if (index === undefined) return;

    const scale = this.entityScales.get(entityId) ?? new THREE.Vector3(1, 1, 1);

    this.dummy.position.copy(position);
    this.dummy.quaternion.copy(quaternion);
    this.dummy.scale.copy(scale);
    this.dummy.updateMatrix();
    this.mesh.setMatrixAt(index, this.dummy.matrix);
  }

  commitUpdates(): void {
    if (!this.mesh) return;
    this.mesh.instanceMatrix.needsUpdate = true;
  }

  hasEntity(entityId: EntityId): boolean {
    return this.entityIndexMap.has(entityId);
  }

  getEntityId(index: number): EntityId | undefined {
    return this.entityIds[index];
  }

  getInstanceIndex(entityId: EntityId): number | undefined {
    return this.entityIndexMap.get(entityId);
  }

  /**
   * @deprecated Use forEachEntity() to avoid array allocation
   */
  getEntityIds(): EntityId[] {
    return this.entityIds.slice(0, this.activeCount);
  }

  /**
   * Iterate over active entities without allocating a new array.
   * Use this in hot paths instead of getEntityIds().
   */
  forEachEntity(callback: (entityId: EntityId, index: number) => void): void {
    for (let i = 0; i < this.activeCount; i++) {
      callback(this.entityIds[i], i);
    }
  }

  getCount(): number {
    return this.activeCount;
  }

  clear(): void {
    if (!this.mesh) return;

    for (let i = 0; i < this.activeCount; i++) {
      this.mesh.setMatrixAt(i, InstancedMeshBase.zeroMatrix);
    }
    this.mesh.instanceMatrix.needsUpdate = true;

    this.entityIds = [];
    this.entityIndexMap.clear();
    this.entityScales.clear();
    this.activeCount = 0;
  }

  dispose(): void {
    if (!this.mesh) return;

    this.mesh.geometry.dispose();
    (this.mesh.material as THREE.Material).dispose();
    this.scene.remove(this.mesh);
    this.mesh = null;

    this.entityIds = [];
    this.entityIndexMap.clear();
    this.entityScales.clear();
    this.activeCount = 0;
  }
}
