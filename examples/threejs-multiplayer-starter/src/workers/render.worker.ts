/**
 * Render Worker Entry Point
 *
 * Implements the RenderApi interface by delegating to the Experience class.
 * This separation keeps the API factory at the worker boundary while
 * the domain logic lives in the renderer module.
 */
import * as Comlink from "comlink";
import { SharedTransformBuffer } from "~/shared/buffers";
import type {
  RenderApi,
  RaycastResult,
  ViewportSize,
  SerializedInputEvent,
  DebugBinding,
  DebugUpdateEvent,
  EntityId,
  SharedBuffers,
  DebugCollider,
  FootstepCallback,
  ListenerCallback,
} from "~/shared/types";
import {
  assertInitialized,
  assertValidEntityId,
  assertNonEmptyString,
} from "~/shared/validation";
import Experience from "../renderer";

/**
 * Creates the RenderApi implementation
 *
 * The API wraps the Experience class and handles:
 * - Lazy initialization (experience created on init())
 * - SharedArrayBuffer wrapping
 * - Method delegation to experience instance
 * - Input validation at worker boundary
 */
function createRenderApi(): RenderApi {
  let experience: Experience | null = null;
  /**
   * Assert that Experience is initialized
   * @throws Error if experience is null
   */
  const assertExperienceInitialized = (): Experience => {
    assertInitialized(experience, "Experience", "RenderApi");
    return experience;
  };

  return {
    async init(
      canvas: OffscreenCanvas,
      viewport: ViewportSize,
      debug: boolean,
      sharedBuffers: SharedBuffers,
      onProgress?: (progress: number) => void,
      onReady?: () => void,
      onFrameTiming?: (deltaMs: number) => void,
    ): Promise<void> {
      // Warn if already initialized
      if (experience) {
        console.warn(
          "[RenderApi.init] Already initialized. Disposing and reinitializing.",
        );
        experience.dispose();
      }

      const sharedBuffer = new SharedTransformBuffer(
        sharedBuffers.control,
        sharedBuffers.transform,
        sharedBuffers.timing,
        sharedBuffers.flags,
      );

      experience = new Experience(
        canvas,
        viewport,
        debug,
        sharedBuffer,
        onProgress,
        onReady,
        onFrameTiming,
      );
    },

    resize(viewport: ViewportSize): void {
      assertExperienceInitialized().resize(viewport);
    },

    handleInput(event: SerializedInputEvent): void {
      assertExperienceInitialized().handleInput(event);
    },

    async getDebugBindings(): Promise<DebugBinding[]> {
      return assertExperienceInitialized().getDebugBindings();
    },

    updateDebug(event: DebugUpdateEvent): void {
      assertExperienceInitialized().updateDebug(event);
    },

    triggerDebugAction(id: string): void {
      assertNonEmptyString(id, "action id", "RenderApi.triggerDebugAction");
      assertExperienceInitialized().triggerDebugAction(id);
    },

    // ============================================
    // Entity Management (unique entities)
    // ============================================

    async spawnEntity(
      id: EntityId,
      type: string,
      data?: Record<string, unknown>,
      debugCollider?: DebugCollider,
    ): Promise<void> {
      assertValidEntityId(id, "RenderApi.spawnEntity");
      assertNonEmptyString(type, "entity type", "RenderApi.spawnEntity");

      await assertExperienceInitialized().spawnEntity(
        id,
        type,
        data,
        debugCollider,
      );
    },

    removeEntity(id: EntityId): void {
      assertValidEntityId(id, "RenderApi.removeEntity");
      assertExperienceInitialized().removeEntity(id);
    },

    async getPlayerEntityId(): Promise<EntityId | null> {
      return assertExperienceInitialized().getPlayerEntityId();
    },

    // ============================================
    // Instanced Boxes
    // ============================================

    addBox(
      entityId: EntityId,
      scale?: { x: number; y: number; z: number },
    ): void {
      assertValidEntityId(entityId, "RenderApi.addBox");
      assertExperienceInitialized().addBox(entityId, scale);
    },

    addBoxes(
      entityIds: EntityId[],
      scales?: Array<{ x: number; y: number; z: number }>,
    ): void {
      for (const id of entityIds) {
        assertValidEntityId(id, "RenderApi.addBoxes");
      }
      assertExperienceInitialized().addBoxes(entityIds, scales);
    },

    removeBoxes(entityIds: EntityId[]): void {
      for (const id of entityIds) {
        assertValidEntityId(id, "RenderApi.removeBoxes");
      }
      assertExperienceInitialized().removeBoxes(entityIds);
    },

    clearBoxes(): void {
      assertExperienceInitialized().clearBoxes();
    },

    getBoxCount(): number {
      return assertExperienceInitialized().getBoxCount();
    },

    // ============================================
    // Instanced Spheres
    // ============================================

    addSphere(entityId: EntityId, radius?: number): void {
      assertValidEntityId(entityId, "RenderApi.addSphere");
      assertExperienceInitialized().addSphere(entityId, radius);
    },

    addSpheres(entityIds: EntityId[], radii?: number[]): void {
      for (const id of entityIds) {
        assertValidEntityId(id, "RenderApi.addSpheres");
      }
      assertExperienceInitialized().addSpheres(entityIds, radii);
    },

    removeSpheres(entityIds: EntityId[]): void {
      for (const id of entityIds) {
        assertValidEntityId(id, "RenderApi.removeSpheres");
      }
      assertExperienceInitialized().removeSpheres(entityIds);
    },

    clearSpheres(): void {
      assertExperienceInitialized().clearSpheres();
    },

    getSphereCount(): number {
      return assertExperienceInitialized().getSphereCount();
    },

    // ============================================
    // Combined Instance Operations
    // ============================================

    removeInstances(entityIds: EntityId[]): void {
      for (const id of entityIds) {
        assertValidEntityId(id, "RenderApi.removeInstances");
      }
      assertExperienceInitialized().removeInstances(entityIds);
    },

    clearAllInstances(): void {
      assertExperienceInitialized().clearAllInstances();
    },

    // ============================================
    // Raycasting
    // ============================================

    raycastGround(x: number, y: number): RaycastResult | null {
      return assertExperienceInitialized().raycastGround(x, y);
    },

    // ============================================
    // Lifecycle
    // ============================================

    dispose(): void {
      experience?.dispose();
      experience = null;
    },

    // ============================================
    // Audio Callbacks
    // ============================================

    setFootstepCallback(callback: FootstepCallback): void {
      assertExperienceInitialized().setFootstepCallback(callback);
    },

    setListenerCallback(callback: ListenerCallback): void {
      assertExperienceInitialized().setListenerCallback(callback);
    },
  };
}

const api = createRenderApi();
Comlink.expose(api);

// Listen for direct cleanup messages (bypasses Comlink for synchronous cleanup)
// This is critical for beforeunload where async Comlink calls won't complete
self.addEventListener("message", (event) => {
  if (event.data?.type === "cleanup") {
    api.dispose();
  }
});
