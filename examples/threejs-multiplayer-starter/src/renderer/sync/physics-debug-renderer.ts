import * as THREE from "three";
import type {
  EntityId,
  DebugCollider,
  DebugColliderShape,
} from "~/shared/types";
import type { RenderComponent } from "../entities";
import type Debug from "../systems/debug";
import type { DebugFolder } from "../systems/debug";
import { config } from "~/shared/config";

/**
 * PhysicsDebugRenderer - Visualizes physics colliders as wireframes
 *
 * Creates and manages debug wireframe meshes that follow entity transforms.
 * Only active when debug mode is enabled.
 */
class PhysicsDebugRenderer {
  private scene: THREE.Scene;
  private debugMeshes: Map<EntityId, THREE.Group> = new Map();
  private visible = false;
  private debugFolder: DebugFolder | null = null;

  // Debug state for UI binding
  private debugState = {
    color: `#${config.debug.colliderColor.toString(16).padStart(6, "0")}`,
    opacity: config.debug.colliderOpacity,
    wireframe: true,
  };

  // Shared materials for all debug meshes
  private readonly debugMaterial = new THREE.MeshBasicMaterial({
    color: config.debug.colliderColor,
    wireframe: true,
    transparent: true,
    opacity: config.debug.colliderOpacity,
  });

  constructor(scene: THREE.Scene, debug?: Debug) {
    this.scene = scene;

    if (debug) {
      this.addDebug(debug);
    }
  }

  private addDebug(debug: Debug): void {
    if (!debug.active || !debug.ui) return;

    this.debugFolder = debug.ui.addFolder({ title: "Physics" });

    this.debugFolder
      .addBinding(this, "visible", { label: "Show Colliders" })
      .on("change", () => {
        for (const mesh of this.debugMeshes.values()) {
          mesh.visible = this.visible;
        }
      });

    this.debugFolder
      .addBinding(this.debugState, "color", { label: "Collider Color" })
      .on("change", () => {
        this.debugMaterial.color.set(this.debugState.color);
      });

    this.debugFolder
      .addBinding(this.debugState, "opacity", {
        label: "Collider Opacity",
        min: 0,
        max: 1,
        step: 0.05,
      })
      .on("change", () => {
        this.debugMaterial.opacity = this.debugState.opacity;
      });

    this.debugFolder
      .addBinding(this.debugState, "wireframe", { label: "Wireframe" })
      .on("change", () => {
        this.debugMaterial.wireframe = this.debugState.wireframe;
      });
  }

  /**
   * Set visibility of all debug meshes
   */
  setVisible(visible: boolean): void {
    this.visible = visible;
    for (const mesh of this.debugMeshes.values()) {
      mesh.visible = visible;
    }
  }

  /**
   * Get current visibility state
   */
  isVisible(): boolean {
    return this.visible;
  }

  /**
   * Toggle visibility
   */
  toggle(): void {
    this.setVisible(!this.visible);
  }

  /**
   * Add a debug mesh for an entity
   */
  addEntity(id: EntityId, collider: DebugCollider): void {
    // Remove existing mesh if any
    this.removeEntity(id);

    // Create a group to hold the mesh (allows for offset)
    const group = new THREE.Group();
    const mesh = this.createDebugMesh(collider.shape);

    // Apply offset if specified (e.g., collider offset from body position)
    if (collider.offset) {
      mesh.position.set(
        collider.offset.x,
        collider.offset.y,
        collider.offset.z,
      );
    }

    group.add(mesh);
    group.visible = this.visible;
    this.debugMeshes.set(id, group);
    this.scene.add(group);
  }

  /**
   * Remove debug mesh for an entity
   */
  removeEntity(id: EntityId): void {
    const group = this.debugMeshes.get(id);
    if (group) {
      this.scene.remove(group);
      // Dispose all meshes in the group
      group.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          child.geometry.dispose();
        }
      });
      this.debugMeshes.delete(id);
    }
  }

  /**
   * Update debug mesh positions to match entity transforms
   */
  update(entities: Map<EntityId, RenderComponent>): void {
    if (!this.visible) return;

    for (const [id, group] of this.debugMeshes) {
      const entity = entities.get(id);
      if (entity) {
        group.position.copy(entity.object.position);
        group.quaternion.copy(entity.object.quaternion);
      }
    }
  }

  /**
   * Create a debug mesh for a collider shape
   */
  private createDebugMesh(shape: DebugColliderShape): THREE.Mesh {
    let geometry: THREE.BufferGeometry;

    switch (shape.type) {
      case "cuboid":
        geometry = new THREE.BoxGeometry(
          shape.halfExtents.x * 2,
          shape.halfExtents.y * 2,
          shape.halfExtents.z * 2,
        );
        break;

      case "capsule":
        geometry = new THREE.CapsuleGeometry(
          shape.radius,
          shape.halfHeight * 2,
          8,
          16,
        );
        break;

      case "ball":
        geometry = new THREE.SphereGeometry(shape.radius, 16, 16);
        break;

      default:
        // Fallback to a small sphere for unknown shapes
        geometry = new THREE.SphereGeometry(0.1, 8, 8);
    }

    return new THREE.Mesh(geometry, this.debugMaterial);
  }

  /**
   * Dispose of all debug meshes and materials
   */
  dispose(): void {
    this.debugFolder?.dispose();
    for (const group of this.debugMeshes.values()) {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          child.geometry.dispose();
        }
      });
    }
    this.debugMeshes.clear();
    this.debugMaterial.dispose();
  }
}

export default PhysicsDebugRenderer;
