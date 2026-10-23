/**
 * SpawnHandler - Handles click-to-spawn events
 *
 * Responsibilities:
 * - Receives canvas click events
 * - Raycasts to find spawn direction
 * - Calculates spawn position and velocity
 * - Spawns entities via EntityCoordinator
 */

import type { Remote } from "comlink";
import type { RenderApi, SerializedClickEvent } from "~/shared/types";
import { config } from "~/shared/config";
import type { SpawnConfig } from "../components/spawner-ui";
import type EntityCoordinator from "../coordinators/entity-coordinator";

/**
 * Interface for UI components that provide spawn configuration
 */
interface SpawnConfigProvider {
  getSpawnConfig(): SpawnConfig;
}

export default class SpawnHandler {
  private ui: SpawnConfigProvider;
  private entities: EntityCoordinator;
  private renderApi: Remote<RenderApi>;

  constructor(
    ui: SpawnConfigProvider,
    entities: EntityCoordinator,
    renderApi: Remote<RenderApi>,
  ) {
    this.ui = ui;
    this.entities = entities;
    this.renderApi = renderApi;
  }

  /**
   * Handle a canvas click event
   * Performs raycast and spawns entity shooting from camera
   */
  async handleClick(event: SerializedClickEvent): Promise<void> {
    // 1. Get spawn config from UI
    const uiConfig = this.ui.getSpawnConfig();

    // 2. Raycast to get spawn position and direction
    const raycast = await this.renderApi.raycastGround(event.x, event.y);
    if (!raycast) {
      // No hit on ground plane (e.g., pointing at sky)
      return;
    }

    // 3. Clamp size to prevent physics tunneling
    const size = Math.max(
      config.spawner.minSize,
      Math.min(config.spawner.maxSize, uiConfig.size),
    );

    // 4. Calculate spawn position (near camera) and velocity (toward hit point)
    const spawnOffset = config.spawner.spawnOffset;
    const spawnPos = {
      x: raycast.origin.x + raycast.direction.x * spawnOffset,
      y: raycast.origin.y + raycast.direction.y * spawnOffset,
      z: raycast.origin.z + raycast.direction.z * spawnOffset,
    };

    const speed = config.spawner.projectileSpeed;
    const velocity = {
      x: raycast.direction.x * speed,
      y: raycast.direction.y * speed,
      z: raycast.direction.z * speed,
    };

    // 5. Spawn entity with velocity
    if (uiConfig.shape === "box") {
      await this.entities.spawnBox({
        position: spawnPos,
        size: { x: size, y: size, z: size },
        velocity,
      });
    } else {
      await this.entities.spawnSphere({
        position: spawnPos,
        radius: size / 2, // Diameter matches box size
        velocity,
      });
    }
  }

  /**
   * Dispose of resources
   */
  dispose(): void {
    // Nothing to dispose currently
  }
}
