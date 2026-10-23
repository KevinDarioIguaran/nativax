import { SimplexNoise } from "./noise";

/**
 * Terrain configuration for height generation
 */
export interface TerrainConfig {
  size: number;
  segments: number;
  noiseScale: number;
  amplitude: number;
  octaves: number;
  persistence: number;
  seed: number;
}

/**
 * Generate height data for terrain
 *
 * Returns Float32Array in column-major order for Rapier heightfield.
 * The same data can be used for Three.js PlaneGeometry vertex displacement
 * with proper index conversion.
 *
 * @param terrainConfig - Terrain generation parameters
 * @returns Float32Array of height values in column-major order
 */
export function generateTerrainHeights(terrainConfig: TerrainConfig): Float32Array {
  const { size, segments, noiseScale, amplitude, octaves, persistence, seed } =
    terrainConfig;

  const noise = new SimplexNoise(seed);

  // Rapier heightfield needs (segments + 1) x (segments + 1) points
  const rows = segments + 1;
  const cols = segments + 1;
  const heights = new Float32Array(rows * cols);

  const halfSize = size / 2;
  const step = size / segments;

  for (let z = 0; z < rows; z++) {
    for (let x = 0; x < cols; x++) {
      // World coordinates (centered at origin)
      const worldX = -halfSize + x * step;
      const worldZ = -halfSize + z * step;

      // Sample noise with fbm for natural terrain
      const noiseValue = noise.fbm(
        worldX * noiseScale,
        worldZ * noiseScale,
        octaves,
        persistence,
      );

      // Map [-1, 1] to [0, amplitude]
      const height = ((noiseValue + 1) / 2) * amplitude;

      // Column-major order for Rapier: index = x * rows + z
      heights[x * rows + z] = height;
    }
  }

  return heights;
}

/**
 * Get height at a specific world position
 *
 * Useful for spawning entities at the correct terrain height.
 *
 * @param x - World X coordinate
 * @param z - World Z coordinate
 * @param heights - Pre-generated height array
 * @param terrainConfig - Terrain configuration
 * @returns Height at the given position
 */
export function getHeightAt(
  x: number,
  z: number,
  heights: Float32Array,
  terrainConfig: TerrainConfig,
): number {
  const { size, segments } = terrainConfig;
  const rows = segments + 1;
  const halfSize = size / 2;
  const step = size / segments;

  // Convert world coords to grid coords
  const gridX = Math.floor((x + halfSize) / step);
  const gridZ = Math.floor((z + halfSize) / step);

  // Clamp to valid range
  const clampedX = Math.max(0, Math.min(segments, gridX));
  const clampedZ = Math.max(0, Math.min(segments, gridZ));

  // Column-major order
  return heights[clampedX * rows + clampedZ];
}
