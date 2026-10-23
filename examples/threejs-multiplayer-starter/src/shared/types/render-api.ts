import type {
  SerializedInputEvent,
  ViewportSize,
  DebugBinding,
  DebugUpdateEvent,
} from "./events";
import type { EntityId } from "./entity";
import type { SharedBuffers, DebugCollider } from "./physics-api";
import type { FootstepCallback, ListenerCallback } from "./audio-events";

// ============================================
// Raycasting Types
// ============================================

/**
 * Result from a raycast operation
 */
export interface RaycastResult {
  /** Hit point on the target (ground plane) */
  point: { x: number; y: number; z: number };
  /** Camera position (ray origin) */
  origin: { x: number; y: number; z: number };
  /** Ray direction (normalized) */
  direction: { x: number; y: number; z: number };
}

/**
 * Render Worker API - exposed via Comlink
 */
export interface RenderApi {
  /**
   * Initialize the renderer with an OffscreenCanvas
   * Note: Callbacks must be passed as separate arguments (not in object)
   * because Comlink.proxy functions cannot be nested in objects.
   */
  init(
    canvas: OffscreenCanvas,
    viewport: ViewportSize,
    debug: boolean,
    sharedBuffers: SharedBuffers,
    onProgress?: (progress: number) => void,
    onReady?: () => void,
    onFrameTiming?: (deltaMs: number) => void,
  ): Promise<void>;

  /**
   * Handle viewport resize
   */
  resize(viewport: ViewportSize): void;

  /**
   * Handle input events from main thread
   */
  handleInput(event: SerializedInputEvent): void;

  /**
   * Get all debug bindings from the scene
   */
  getDebugBindings(): Promise<DebugBinding[]>;

  /**
   * Update a debug value
   */
  updateDebug(event: DebugUpdateEvent): void;

  /**
   * Trigger a debug button action
   */
  triggerDebugAction(id: string): void;

  // ============================================
  // Entity Management (for unique entities like player, ground)
  // ============================================

  /**
   * Spawn a render entity (mesh) for a physics entity
   * Used for unique entities that don't use instancing (player, ground)
   * @param debugCollider - Optional collider info for debug visualization
   */
  spawnEntity(
    id: EntityId,
    type: string,
    data?: Record<string, unknown>,
    debugCollider?: DebugCollider,
  ): Promise<void>;

  /**
   * Remove a render entity
   */
  removeEntity(id: EntityId): void;

  /**
   * Get the player entity ID (for camera following)
   */
  getPlayerEntityId(): Promise<EntityId | null>;

  // ============================================
  // Instanced Boxes (single draw call for all boxes)
  // ============================================

  /**
   * Add a single box to the instanced mesh
   */
  addBox(entityId: EntityId, scale?: { x: number; y: number; z: number }): void;

  /**
   * Add multiple boxes to the instanced mesh
   */
  addBoxes(
    entityIds: EntityId[],
    scales?: Array<{ x: number; y: number; z: number }>,
  ): void;

  /**
   * Remove boxes from the instanced mesh
   */
  removeBoxes(entityIds: EntityId[]): void;

  /**
   * Clear all instanced boxes
   */
  clearBoxes(): void;

  /**
   * Get current box count
   */
  getBoxCount(): number;

  // ============================================
  // Instanced Spheres (single draw call for all spheres)
  // ============================================

  /**
   * Add a single sphere to the instanced mesh
   */
  addSphere(entityId: EntityId, radius?: number): void;

  /**
   * Add multiple spheres to the instanced mesh
   */
  addSpheres(entityIds: EntityId[], radii?: number[]): void;

  /**
   * Remove spheres from the instanced mesh
   */
  removeSpheres(entityIds: EntityId[]): void;

  /**
   * Clear all instanced spheres
   */
  clearSpheres(): void;

  /**
   * Get current sphere count
   */
  getSphereCount(): number;

  // ============================================
  // Combined Instance Operations
  // ============================================

  /**
   * Remove instances by entity IDs (auto-detects box vs sphere)
   */
  removeInstances(entityIds: EntityId[]): void;

  /**
   * Clear all instanced meshes (boxes and spheres)
   */
  clearAllInstances(): void;

  // ============================================
  // Lifecycle
  // ============================================

  /**
   * Clean up and dispose resources
   */
  dispose(): void;

  // ============================================
  // Audio Event Callbacks
  // ============================================

  /**
   * Set callback for footstep events (for audio)
   * Called based on player movement and animation state
   */
  setFootstepCallback(callback: FootstepCallback): void;

  /**
   * Set callback for listener position updates (for spatial audio)
   * Called each frame with camera position/orientation
   */
  setListenerCallback(callback: ListenerCallback): void;

  // ============================================
  // Raycasting
  // ============================================

  /**
   * Raycast from screen coordinates to invisible ground plane at Y=0
   * Used for click-to-spawn mechanics
   * @param x Normalized screen X (0-1, left to right)
   * @param y Normalized screen Y (0-1, top to bottom)
   * @returns Hit info including point, camera origin, and ray direction, or null if no hit
   */
  raycastGround(x: number, y: number): RaycastResult | null;
}
