/**
 * Validation utilities for strict type safety across workers
 *
 * Provides branded types, assertion functions, and debug-only checks
 * to ensure data integrity at worker boundaries.
 */

import type { EntityId } from "./types/entity";

// ============================================
// Branded Types
// ============================================

/**
 * BufferIndex - branded type for validated buffer indices
 * Ensures index has been validated before use in buffer operations
 */
export type BufferIndex = number & { readonly __brand: "BufferIndex" };

/**
 * Create a validated buffer index
 * @throws Error if index is out of bounds
 */
export function createBufferIndex(
  index: number,
  maxEntities: number,
  context: string,
): BufferIndex {
  assertBufferIndexInBounds(index, maxEntities, context);
  return index as BufferIndex;
}

// ============================================
// Assertion Functions
// ============================================

/**
 * Assert that an entity is registered in the entity map
 * @throws Error if entity is not registered
 */
export function assertEntityRegistered(
  entityId: EntityId,
  entityMap: Map<EntityId, number>,
  context: string,
): void {
  if (!entityMap.has(entityId)) {
    throw new Error(
      `[${context}] Entity ${entityId} not registered. ` +
        `Call registerEntity() before accessing this entity.`,
    );
  }
}

/**
 * Assert that a buffer index is within valid bounds
 * @throws Error if index is out of bounds
 */
export function assertBufferIndexInBounds(
  index: number,
  maxEntities: number,
  context: string,
): asserts index is BufferIndex {
  if (typeof index !== "number" || !Number.isInteger(index)) {
    throw new Error(
      `[${context}] Buffer index must be an integer, got: ${typeof index} (${index})`,
    );
  }
  if (index < 0 || index >= maxEntities) {
    throw new Error(
      `[${context}] Buffer index ${index} out of bounds. ` +
        `Valid range: 0-${maxEntities - 1}`,
    );
  }
}

/**
 * Assert that a value is initialized (not null or undefined)
 * @throws Error if value is null or undefined
 */
export function assertInitialized<T>(
  value: T | null | undefined,
  name: string,
  context: string,
): asserts value is T {
  if (value === null || value === undefined) {
    throw new Error(`[${context}] ${name} not initialized. Call init() first.`);
  }
}

/**
 * Assert that an EntityId is valid
 * @throws Error if EntityId is not a positive integer
 */
export function assertValidEntityId(
  id: unknown,
  context: string,
): asserts id is EntityId {
  if (typeof id !== "number" || !Number.isInteger(id) || id <= 0) {
    throw new Error(
      `[${context}] Invalid EntityId: ${id}. Must be a positive integer.`,
    );
  }
}

/**
 * Assert that a string is non-empty
 * @throws Error if string is empty or not a string
 */
export function assertNonEmptyString(
  value: unknown,
  name: string,
  context: string,
): asserts value is string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(
      `[${context}] ${name} must be a non-empty string, got: ${typeof value} ("${value}")`,
    );
  }
}

// ============================================
// Debug Assertions
// ============================================

/**
 * Debug-only assertion that is stripped in production builds
 * Use for performance-sensitive code paths where you want validation
 * during development but not in production
 *
 * @param condition - Condition that should be true
 * @param message - Error message if condition is false
 */
export function debugAssert(
  condition: boolean,
  message: string,
): asserts condition {
  if (import.meta.env.DEV && !condition) {
    throw new Error(`[Debug Assertion Failed] ${message}`);
  }
}

/**
 * Debug-only warning (logged but doesn't throw)
 * Use for non-critical issues that should be addressed but don't break functionality
 */
export function debugWarn(condition: boolean, message: string): void {
  if (import.meta.env.DEV && !condition) {
    console.warn(`[Debug Warning] ${message}`);
  }
}

// ============================================
// Validation Result Type
// ============================================

/**
 * Result type for validations that shouldn't throw
 * Useful for validation that needs to be handled gracefully
 */
export type ValidationResult<T> =
  | { success: true; value: T }
  | { success: false; error: string };

/**
 * Validate a buffer index without throwing
 * Returns a ValidationResult that can be checked
 */
export function validateBufferIndex(
  index: number,
  maxEntities: number,
): ValidationResult<BufferIndex> {
  if (typeof index !== "number" || !Number.isInteger(index)) {
    return {
      success: false,
      error: `Buffer index must be an integer, got: ${typeof index}`,
    };
  }
  if (index < 0 || index >= maxEntities) {
    return {
      success: false,
      error: `Buffer index ${index} out of bounds (max: ${maxEntities - 1})`,
    };
  }
  return { success: true, value: index as BufferIndex };
}

/**
 * Validate an entity is registered without throwing
 */
export function validateEntityRegistered(
  entityId: EntityId,
  entityMap: Map<EntityId, number>,
): ValidationResult<number> {
  const index = entityMap.get(entityId);
  if (index === undefined) {
    return {
      success: false,
      error: `Entity ${entityId} not registered`,
    };
  }
  return { success: true, value: index };
}
