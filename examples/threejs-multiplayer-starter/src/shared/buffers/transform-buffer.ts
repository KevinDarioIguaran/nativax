import type { EntityId } from "../types/entity";
import { config } from "../config";
import {
  assertBufferIndexInBounds,
  debugAssert,
  validateBufferIndex,
} from "../validation";

/**
 * Layout per entity in Float32Array (14 floats total):
 * CURRENT:  [posX, posY, posZ, rotX, rotY, rotZ, rotW] = 7 floats
 * PREVIOUS: [posX, posY, posZ, rotX, rotY, rotZ, rotW] = 7 floats
 *
 * Timing buffer (Float64Array):
 * [currentFrameTime, previousFrameTime, physicsInterval] = 3 float64s
 *
 * Control Int32Array for synchronization:
 * [frameCounter, entityCount, ...entityIds]
 */

const FLOATS_PER_ENTITY = config.buffers.floatsPerEntity;
const CONTROL_HEADER_SIZE = config.buffers.controlHeaderSize;
const MAX_ENTITIES = config.buffers.maxEntities;

// Control buffer layout
const FRAME_COUNTER_INDEX = 0;
const ENTITY_COUNT_INDEX = 1;
const ENTITY_IDS_START = 2;

// Timing buffer layout
const TIMING_CURRENT_TIME_INDEX = 0;
const TIMING_PREVIOUS_TIME_INDEX = 1;
const TIMING_INTERVAL_INDEX = 2;
const TIMING_BUFFER_SIZE = 3;

// Transform data layout per entity (indices within FLOATS_PER_ENTITY block)
// Current transform: indices 0-6
const CURRENT_POS_X = 0;
const CURRENT_POS_Y = 1;
const CURRENT_POS_Z = 2;
const CURRENT_ROT_X = 3;
const CURRENT_ROT_Y = 4;
const CURRENT_ROT_Z = 5;
const CURRENT_ROT_W = 6;
// Previous transform: indices 7-13
const PREVIOUS_POS_X = 7;
const PREVIOUS_POS_Y = 8;
const PREVIOUS_POS_Z = 9;
const PREVIOUS_ROT_X = 10;
const PREVIOUS_ROT_Y = 11;
const PREVIOUS_ROT_Z = 12;
const PREVIOUS_ROT_W = 13;
const FLOATS_PER_TRANSFORM = 7;

/**
 * Transform data for a single frame
 */
export interface TransformData {
  posX: number;
  posY: number;
  posZ: number;
  rotX: number;
  rotY: number;
  rotZ: number;
  rotW: number;
}

/**
 * Frame timing information
 */
export interface FrameTiming {
  currentTime: number;
  previousTime: number;
  interval: number;
}

/**
 * Entity state flags (bitfield)
 * Used for per-entity state like grounded status
 */
export const EntityFlags = {
  GROUNDED: 0b00000001, // bit 0 = isGrounded
} as const;

/**
 * SharedTransformBuffer - Zero-copy transform synchronization between workers
 *
 * Uses SharedArrayBuffer for direct memory sharing between Physics and Render workers.
 * Physics worker writes transforms, Render worker reads them.
 *
 * Structure:
 * - controlBuffer (Int32Array): frame counter + entity IDs for synchronization
 * - transformBuffer (Float32Array): previous + current position/rotation data per entity
 * - timingBuffer (Float64Array): physics frame timestamps for interpolation
 * - flagsBuffer (Uint8Array): per-entity state flags (grounded, etc.)
 *
 * The double-buffered transforms (previous + current) combined with timestamps
 * enable smooth interpolation without discontinuities when new physics frames arrive.
 *
 * @see https://gafferongames.com/post/fix_your_timestep/
 * @see https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer
 */
export class SharedTransformBuffer {
  private controlSAB: SharedArrayBuffer;
  private transformSAB: SharedArrayBuffer;
  private timingSAB: SharedArrayBuffer;
  private flagsSAB: SharedArrayBuffer;

  private controlView: Int32Array;
  private transformView: Float32Array;
  private timingView: Float64Array;
  private flagsView: Uint8Array;

  private entityIndexMap: Map<EntityId, number> = new Map();

  constructor(
    existingControl?: SharedArrayBuffer,
    existingTransform?: SharedArrayBuffer,
    existingTiming?: SharedArrayBuffer,
    existingFlags?: SharedArrayBuffer,
  ) {
    if (existingControl && existingTransform && existingTiming) {
      // Use existing buffers (when receiving in worker)
      this.controlSAB = existingControl;
      this.transformSAB = existingTransform;
      this.timingSAB = existingTiming;
      this.flagsSAB =
        existingFlags ??
        new SharedArrayBuffer(MAX_ENTITIES * Uint8Array.BYTES_PER_ELEMENT);
    } else {
      // Create new buffers (in main thread)
      const controlSize =
        (CONTROL_HEADER_SIZE + MAX_ENTITIES) * Int32Array.BYTES_PER_ELEMENT;
      const transformSize =
        MAX_ENTITIES * FLOATS_PER_ENTITY * Float32Array.BYTES_PER_ELEMENT;
      const timingSize = TIMING_BUFFER_SIZE * Float64Array.BYTES_PER_ELEMENT;
      const flagsSize = MAX_ENTITIES * Uint8Array.BYTES_PER_ELEMENT;

      this.controlSAB = new SharedArrayBuffer(controlSize);
      this.transformSAB = new SharedArrayBuffer(transformSize);
      this.timingSAB = new SharedArrayBuffer(timingSize);
      this.flagsSAB = new SharedArrayBuffer(flagsSize);
    }

    this.controlView = new Int32Array(this.controlSAB);
    this.transformView = new Float32Array(this.transformSAB);
    this.timingView = new Float64Array(this.timingSAB);
    this.flagsView = new Uint8Array(this.flagsSAB);
  }

  /**
   * Get the underlying SharedArrayBuffers for transfer to workers
   */
  getBuffers(): {
    control: SharedArrayBuffer;
    transform: SharedArrayBuffer;
    timing: SharedArrayBuffer;
    flags: SharedArrayBuffer;
  } {
    return {
      control: this.controlSAB,
      transform: this.transformSAB,
      timing: this.timingSAB,
      flags: this.flagsSAB,
    };
  }

  /**
   * Register an entity and get its slot index
   * Called when spawning entities
   *
   * @param id - The entity ID to register
   * @returns The buffer index for this entity, or throws if max entities exceeded
   * @throws Error if maximum entity count is reached
   */
  registerEntity(id: EntityId): number {
    const currentCount = Atomics.load(this.controlView, ENTITY_COUNT_INDEX);

    if (currentCount >= MAX_ENTITIES) {
      throw new Error(
        `Maximum entity count (${MAX_ENTITIES}) exceeded. Cannot register entity ${id}.`,
      );
    }

    const index = currentCount;
    this.entityIndexMap.set(id, index);

    // Store entity ID in control buffer
    Atomics.store(this.controlView, ENTITY_IDS_START + index, id as number);

    // Increment entity count
    Atomics.store(this.controlView, ENTITY_COUNT_INDEX, currentCount + 1);

    return index;
  }

  /**
   * Unregister an entity
   * Note: This doesn't compact the buffer, just marks the slot as unused
   */
  unregisterEntity(id: EntityId): void {
    this.entityIndexMap.delete(id);
  }

  /**
   * Get entity index from ID
   */
  getEntityIndex(id: EntityId): number {
    return this.entityIndexMap.get(id) ?? -1;
  }

  /**
   * Rebuild entity index map from control buffer
   * Called in workers after receiving buffers
   */
  rebuildEntityMap(): void {
    const count = Atomics.load(this.controlView, ENTITY_COUNT_INDEX);

    for (let i = 0; i < count; i++) {
      const entityId = Atomics.load(
        this.controlView,
        ENTITY_IDS_START + i,
      ) as EntityId;
      this.entityIndexMap.set(entityId, i);
    }
  }

  // ============================================
  // Physics Worker: Write transforms and timing
  // ============================================

  /**
   * Write transform data for an entity
   * Called by Physics Worker each physics step
   *
   * This shifts the current transform to previous, then writes the new current.
   * This enables smooth interpolation between physics frames.
   *
   * @throws Error if entityIndex is out of bounds
   */
  writeTransform(
    entityIndex: number,
    posX: number,
    posY: number,
    posZ: number,
    rotX: number,
    rotY: number,
    rotZ: number,
    rotW: number,
  ): void {
    // Validate buffer index bounds
    assertBufferIndexInBounds(
      entityIndex,
      MAX_ENTITIES,
      "SharedTransformBuffer.writeTransform",
    );

    // Debug-only check that the index corresponds to a registered entity
    debugAssert(
      this.isEntityIndexValid(entityIndex),
      `Entity index ${entityIndex} has no registered entity`,
    );

    const offset = entityIndex * FLOATS_PER_ENTITY;

    // Shift current → previous using native copyWithin (faster than loop)
    this.transformView.copyWithin(
      offset + FLOATS_PER_TRANSFORM, // target: previous section
      offset, // start: current section
      offset + FLOATS_PER_TRANSFORM, // end: end of current section
    );

    // Write new current
    this.transformView[offset + CURRENT_POS_X] = posX;
    this.transformView[offset + CURRENT_POS_Y] = posY;
    this.transformView[offset + CURRENT_POS_Z] = posZ;
    this.transformView[offset + CURRENT_ROT_X] = rotX;
    this.transformView[offset + CURRENT_ROT_Y] = rotY;
    this.transformView[offset + CURRENT_ROT_Z] = rotZ;
    this.transformView[offset + CURRENT_ROT_W] = rotW;
  }

  /**
   * Write frame timing information
   * Called by Physics Worker after writing all transforms, before signalFrameComplete
   *
   * @param currentTime - performance.now() when this physics frame completed
   * @param interval - Expected physics interval in ms (e.g., 1000/60 for 60Hz)
   */
  writeFrameTiming(currentTime: number, interval: number): void {
    // Shift current → previous
    this.timingView[TIMING_PREVIOUS_TIME_INDEX] =
      this.timingView[TIMING_CURRENT_TIME_INDEX];
    // Write new current time
    this.timingView[TIMING_CURRENT_TIME_INDEX] = currentTime;
    // Write interval
    this.timingView[TIMING_INTERVAL_INDEX] = interval;
  }

  /**
   * Increment frame counter after all transforms and timing are written
   * This signals to the Render Worker that new data is available
   */
  signalFrameComplete(): void {
    Atomics.add(this.controlView, FRAME_COUNTER_INDEX, 1);
  }

  /**
   * Get current frame counter
   */
  getFrameCounter(): number {
    return Atomics.load(this.controlView, FRAME_COUNTER_INDEX);
  }

  // ============================================
  // Render Worker: Read transforms and timing
  // ============================================

  /**
   * Read frame timing information
   * Called by Render Worker to calculate interpolation alpha
   */
  readFrameTiming(): FrameTiming {
    return {
      currentTime: this.timingView[TIMING_CURRENT_TIME_INDEX],
      previousTime: this.timingView[TIMING_PREVIOUS_TIME_INDEX],
      interval: this.timingView[TIMING_INTERVAL_INDEX],
    };
  }

  /**
   * Read both current and previous transform data for an entity
   * Called by Render Worker each render frame for interpolation
   *
   * @throws Error if entityIndex is out of bounds
   */
  readTransform(entityIndex: number): {
    current: TransformData;
    previous: TransformData;
  } {
    // Validate buffer index bounds
    assertBufferIndexInBounds(
      entityIndex,
      MAX_ENTITIES,
      "SharedTransformBuffer.readTransform",
    );

    const offset = entityIndex * FLOATS_PER_ENTITY;

    return {
      current: {
        posX: this.transformView[offset + CURRENT_POS_X],
        posY: this.transformView[offset + CURRENT_POS_Y],
        posZ: this.transformView[offset + CURRENT_POS_Z],
        rotX: this.transformView[offset + CURRENT_ROT_X],
        rotY: this.transformView[offset + CURRENT_ROT_Y],
        rotZ: this.transformView[offset + CURRENT_ROT_Z],
        rotW: this.transformView[offset + CURRENT_ROT_W],
      },
      previous: {
        posX: this.transformView[offset + PREVIOUS_POS_X],
        posY: this.transformView[offset + PREVIOUS_POS_Y],
        posZ: this.transformView[offset + PREVIOUS_POS_Z],
        rotX: this.transformView[offset + PREVIOUS_ROT_X],
        rotY: this.transformView[offset + PREVIOUS_ROT_Y],
        rotZ: this.transformView[offset + PREVIOUS_ROT_Z],
        rotW: this.transformView[offset + PREVIOUS_ROT_W],
      },
    };
  }

  // ============================================
  // Entity State Flags
  // ============================================

  /**
   * Write entity state flags
   * Called by Physics Worker to communicate entity state (e.g., grounded)
   */
  writeEntityFlags(entityIndex: number, flags: number): void {
    if (entityIndex >= 0 && entityIndex < MAX_ENTITIES) {
      this.flagsView[entityIndex] = flags;
    }
  }

  /**
   * Read entity state flags
   * Called by Render Worker to read entity state for animation decisions
   */
  readEntityFlags(entityIndex: number): number {
    if (entityIndex >= 0 && entityIndex < MAX_ENTITIES) {
      return this.flagsView[entityIndex];
    }
    return 0;
  }

  /**
   * Check if an entity index corresponds to a registered entity
   * Used for debug assertions
   */
  private isEntityIndexValid(index: number): boolean {
    const count = Atomics.load(this.controlView, ENTITY_COUNT_INDEX);
    return index >= 0 && index < count;
  }

  /**
   * Validate a buffer index without throwing
   * Returns a ValidationResult that can be checked
   */
  validateIndex(index: number): ReturnType<typeof validateBufferIndex> {
    return validateBufferIndex(index, MAX_ENTITIES);
  }

  /**
   * Get entity count
   */
  getEntityCount(): number {
    return Atomics.load(this.controlView, ENTITY_COUNT_INDEX);
  }

  /**
   * Get entity ID at index
   */
  getEntityIdAt(index: number): EntityId {
    return Atomics.load(this.controlView, ENTITY_IDS_START + index) as EntityId;
  }
}

/**
 * Check if SharedArrayBuffer is supported
 */
export function isSharedArrayBufferSupported(): boolean {
  return typeof SharedArrayBuffer !== "undefined" && crossOriginIsolated;
}
