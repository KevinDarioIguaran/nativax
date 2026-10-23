import type { EntityId } from "~/shared/types";
import type {
  RenderComponent,
  RenderComponentFactory,
  EntityContext,
} from "./types";

// Import component factories
import { createPlayerEntity } from "./components/player";
import { createGroundEntity } from "./components/ground";
import { createStaticMeshEntity } from "./components/static-mesh";

/**
 * EntityRegistry - Manages component factory registration
 *
 * Allows adding new entity types without modifying Renderer.
 * New types are registered with their factory function.
 *
 * Note: Dynamic boxes and spheres now use instancing (InstancedBoxes/InstancedSpheres)
 * and are NOT registered here. Only unique entity types need registration.
 */
class EntityRegistry {
  private factories = new Map<string, RenderComponentFactory>();

  /**
   * Register a factory for an entity type
   */
  register(type: string, factory: RenderComponentFactory): void {
    if (this.factories.has(type)) {
      console.warn(`[EntityRegistry] Overwriting factory for type: ${type}`);
    }
    this.factories.set(type, factory);
  }

  /**
   * Get factory for an entity type
   */
  get(type: string): RenderComponentFactory | undefined {
    return this.factories.get(type);
  }

  /**
   * Check if a factory exists for an entity type
   */
  has(type: string): boolean {
    return this.factories.has(type);
  }

  /**
   * Get all registered type names
   */
  getTypes(): string[] {
    return Array.from(this.factories.keys());
  }
}

/** Global entity registry instance */
export const entityRegistry = new EntityRegistry();

// Register built-in entity types
// Note: Boxes and spheres use instancing, not individual entities
entityRegistry.register("player", createPlayerEntity);
entityRegistry.register("ground", createGroundEntity);
entityRegistry.register("static-mesh", createStaticMeshEntity);

/**
 * EntityFactory - Creates render components from type strings
 *
 * Uses the registry to look up factory functions.
 * Falls back to static-mesh for unknown types.
 */
export class EntityFactory {
  private context: EntityContext;

  constructor(context: EntityContext) {
    this.context = context;
  }

  /**
   * Create a render component for an entity
   *
   * @param id - Unique entity identifier
   * @param type - Entity type string (must be registered in registry)
   * @param data - Optional data passed to factory
   * @returns Created render component
   */
  async create(
    id: EntityId,
    type: string,
    data?: Record<string, unknown>,
  ): Promise<RenderComponent> {
    const factory = entityRegistry.get(type);

    if (!factory) {
      console.warn(
        `[EntityFactory] Unknown entity type: "${type}", using fallback`,
      );
      return createStaticMeshEntity(id, this.context, {
        ...data,
        color: 0xff0000, // Red cube for unknown types
      });
    }

    return factory(id, this.context, data);
  }
}

// Re-export types
export * from "./types";
