import RAPIER from "@dimforge/rapier3d-compat";
import type {
  EntityId,
  Transform,
  PhysicsBodyConfig,
  FloatingCapsuleConfig,
  BatchBodyConfig,
} from "~/shared/types";
import { config } from "~/shared/config";
import { generateTerrainHeights } from "~/shared/utils";
import FloatingCapsuleController from "./floating-capsule-controller";

/**
 * BodyFactory - Creates Rapier physics bodies and colliders
 *
 * Encapsulates body/collider creation logic for different entity types.
 */
export class BodyFactory {
  private density: number = config.physics.density;

  /**
   * Update density for future body creation
   */
  setDensity(density: number): void {
    this.density = density;
  }

  /**
   * Create a single entity body from config
   */
  createEntity(
    world: RAPIER.World,
    _entityId: EntityId,
    transform: Transform,
    bodyConfig: PhysicsBodyConfig,
  ): { body: RAPIER.RigidBody; collider: RAPIER.Collider } {
    // Create rigid body descriptor
    let bodyDesc: RAPIER.RigidBodyDesc;
    switch (bodyConfig.type) {
      case "static":
        bodyDesc = RAPIER.RigidBodyDesc.fixed();
        break;
      case "dynamic":
        bodyDesc = RAPIER.RigidBodyDesc.dynamic();
        break;
      case "kinematic":
        bodyDesc = RAPIER.RigidBodyDesc.kinematicPositionBased();
        break;
    }

    // Set position and rotation
    bodyDesc.setTranslation(
      transform.position.x,
      transform.position.y,
      transform.position.z,
    );
    bodyDesc.setRotation({
      x: transform.rotation.x,
      y: transform.rotation.y,
      z: transform.rotation.z,
      w: transform.rotation.w,
    });

    const body = world.createRigidBody(bodyDesc);

    // Create collider
    const colliderDesc = this.createColliderDesc(bodyConfig);

    // Set physics properties
    if (bodyConfig.friction !== undefined) {
      colliderDesc.setFriction(bodyConfig.friction);
    }
    if (bodyConfig.restitution !== undefined) {
      colliderDesc.setRestitution(bodyConfig.restitution);
    }

    const collider = world.createCollider(colliderDesc, body);

    // Enable collision events for dynamic bodies
    if (bodyConfig.type === "dynamic") {
      collider.setActiveEvents(RAPIER.ActiveEvents.COLLISION_EVENTS);
    }

    return { body, collider };
  }

  /**
   * Create a floating capsule controller (player)
   */
  createFloatingPlayer(
    world: RAPIER.World,
    id: EntityId,
    transform: Transform,
    controllerConfig: FloatingCapsuleConfig,
  ): FloatingCapsuleController {
    return new FloatingCapsuleController(
      world,
      id,
      transform,
      controllerConfig,
    );
  }

  /**
   * Create batch of dynamic bodies (boxes or spheres)
   */
  createBatch(
    world: RAPIER.World,
    entityIds: EntityId[],
    positions: Float32Array,
    bodyConfig: BatchBodyConfig,
    sizes: Float32Array,
    velocities?: Float32Array,
  ): Array<{
    id: EntityId;
    body: RAPIER.RigidBody;
    collider: RAPIER.Collider;
  }> {
    const results: Array<{
      id: EntityId;
      body: RAPIER.RigidBody;
      collider: RAPIER.Collider;
    }> = [];

    const count = entityIds.length;

    for (let i = 0; i < count; i++) {
      const id = entityIds[i];
      const x = positions[i * 3];
      const y = positions[i * 3 + 1];
      const z = positions[i * 3 + 2];

      const hasVelocity = velocities !== undefined;

      // Create dynamic rigid body
      const bodyDesc = RAPIER.RigidBodyDesc.dynamic()
        .setTranslation(x, y, z)
        .setLinearDamping(0.1)
        .setAngularDamping(0.1)
        .setCcdEnabled(hasVelocity);

      const body = world.createRigidBody(bodyDesc);

      // Apply initial velocity if provided
      if (velocities) {
        body.setLinvel(
          {
            x: velocities[i * 3],
            y: velocities[i * 3 + 1],
            z: velocities[i * 3 + 2],
          },
          true,
        );
      }

      // Create collider based on type
      const colliderDesc = this.createBatchColliderDesc(bodyConfig, sizes, i);
      const collider = world.createCollider(colliderDesc, body);

      // Enable collision events
      collider.setActiveEvents(RAPIER.ActiveEvents.COLLISION_EVENTS);

      results.push({ id, body, collider });
    }

    return results;
  }

  /**
   * Create collider descriptor from body config
   */
  private createColliderDesc(
    bodyConfig: PhysicsBodyConfig,
  ): RAPIER.ColliderDesc {
    switch (bodyConfig.colliderType) {
      case "cuboid":
        return RAPIER.ColliderDesc.cuboid(
          bodyConfig.dimensions.x / 2,
          bodyConfig.dimensions.y / 2,
          bodyConfig.dimensions.z / 2,
        );

      case "ball":
        return RAPIER.ColliderDesc.ball(bodyConfig.radius ?? 0.5);

      case "capsule":
        return RAPIER.ColliderDesc.capsule(
          (bodyConfig.height ?? 1) / 2,
          bodyConfig.radius ?? 0.5,
        );

      case "heightfield": {
        const terrainConfig = config.terrain;
        const heights = generateTerrainHeights(terrainConfig);
        const nrows = terrainConfig.segments;
        const ncols = terrainConfig.segments;
        const scale = new RAPIER.Vector3(
          terrainConfig.size,
          1,
          terrainConfig.size,
        );
        return RAPIER.ColliderDesc.heightfield(nrows, ncols, heights, scale);
      }

      default:
        return RAPIER.ColliderDesc.cuboid(
          bodyConfig.dimensions.x / 2,
          bodyConfig.dimensions.y / 2,
          bodyConfig.dimensions.z / 2,
        );
    }
  }

  /**
   * Create batch collider descriptor with per-entity sizes
   */
  private createBatchColliderDesc(
    bodyConfig: BatchBodyConfig,
    sizes: Float32Array,
    index: number,
  ): RAPIER.ColliderDesc {
    if (bodyConfig.type === "sphere") {
      const radius = sizes[index];
      return RAPIER.ColliderDesc.ball(radius)
        .setDensity(this.density)
        .setFriction(0.3)
        .setRestitution(0.6);
    }

    // Box: 3 floats per entity
    const hx = sizes[index * 3] / 2;
    const hy = sizes[index * 3 + 1] / 2;
    const hz = sizes[index * 3 + 2] / 2;
    return RAPIER.ColliderDesc.cuboid(hx, hy, hz)
      .setDensity(this.density)
      .setFriction(0.5)
      .setRestitution(0.3);
  }
}
