import * as THREE from "three";
import type { EntityId } from "~/shared/types";
import type { RenderComponent, EntityContext } from "../types";

/**
 * GroundEntity - Invisible physics proxy for ground plane
 *
 * The visual floor is created separately in Renderer.
 * This entity just tracks the physics body's position.
 */
export class GroundEntity implements RenderComponent {
  readonly id: EntityId;
  readonly type = "ground";
  readonly object: THREE.Object3D;

  constructor(id: EntityId, context: EntityContext) {
    this.id = id;
    this.object = new THREE.Object3D();
    this.object.visible = false;
    context.scene.add(this.object);
  }

  dispose(): void {
    this.object.parent?.remove(this.object);
  }
}

/**
 * Factory function for creating GroundEntity
 */
export function createGroundEntity(
  id: EntityId,
  context: EntityContext,
): RenderComponent {
  return new GroundEntity(id, context);
}
