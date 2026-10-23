/**
 * Seeded 2D Simplex Noise
 *
 * Deterministic noise generation for synchronized terrain across workers.
 * Based on Stefan Gustavson's Simplex noise algorithm.
 */

// Gradient vectors for 2D simplex noise
const GRAD2 = [
  [1, 1],
  [-1, 1],
  [1, -1],
  [-1, -1],
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];

// Skewing factors for 2D
const F2 = 0.5 * (Math.sqrt(3) - 1);
const G2 = (3 - Math.sqrt(3)) / 6;

export class SimplexNoise {
  private perm: Uint8Array;
  private permMod8: Uint8Array;

  constructor(seed: number) {
    this.perm = new Uint8Array(512);
    this.permMod8 = new Uint8Array(512);
    this.buildPermutationTable(seed);
  }

  private buildPermutationTable(seed: number): void {
    // Seeded PRNG (simple LCG - Linear Congruential Generator)
    const random = (): number => {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    };

    // Create initial permutation array
    const p = new Uint8Array(256);
    for (let i = 0; i < 256; i++) {
      p[i] = i;
    }

    // Fisher-Yates shuffle with seeded random
    for (let i = 255; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [p[i], p[j]] = [p[j], p[i]];
    }

    // Double the table to avoid modulo operations
    for (let i = 0; i < 512; i++) {
      this.perm[i] = p[i & 255];
      this.permMod8[i] = this.perm[i] & 7;
    }
  }

  /**
   * 2D Simplex noise
   * @returns Value in range [-1, 1]
   */
  noise2D(x: number, y: number): number {
    // Skew input space to determine which simplex cell we're in
    const s = (x + y) * F2;
    const i = Math.floor(x + s);
    const j = Math.floor(y + s);

    // Unskew back to get the cell origin in (x, y) space
    const t = (i + j) * G2;
    const X0 = i - t;
    const Y0 = j - t;

    // Distances from cell origin
    const x0 = x - X0;
    const y0 = y - Y0;

    // Determine which simplex we're in
    // For 2D, the simplex is an equilateral triangle
    let i1: number, j1: number;
    if (x0 > y0) {
      // Lower triangle, XY order: (0,0)->(1,0)->(1,1)
      i1 = 1;
      j1 = 0;
    } else {
      // Upper triangle, YX order: (0,0)->(0,1)->(1,1)
      i1 = 0;
      j1 = 1;
    }

    // Offsets for middle corner in (x,y) unskewed coords
    const x1 = x0 - i1 + G2;
    const y1 = y0 - j1 + G2;

    // Offsets for last corner in (x,y) unskewed coords
    const x2 = x0 - 1 + 2 * G2;
    const y2 = y0 - 1 + 2 * G2;

    // Wrap indices to [0, 255]
    const ii = i & 255;
    const jj = j & 255;

    // Calculate contribution from each corner
    let n0 = 0,
      n1 = 0,
      n2 = 0;

    // Corner 0
    let t0 = 0.5 - x0 * x0 - y0 * y0;
    if (t0 >= 0) {
      const gi0 = this.permMod8[ii + this.perm[jj]];
      t0 *= t0;
      n0 = t0 * t0 * this.dot2(GRAD2[gi0], x0, y0);
    }

    // Corner 1
    let t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 >= 0) {
      const gi1 = this.permMod8[ii + i1 + this.perm[jj + j1]];
      t1 *= t1;
      n1 = t1 * t1 * this.dot2(GRAD2[gi1], x1, y1);
    }

    // Corner 2
    let t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 >= 0) {
      const gi2 = this.permMod8[ii + 1 + this.perm[jj + 1]];
      t2 *= t2;
      n2 = t2 * t2 * this.dot2(GRAD2[gi2], x2, y2);
    }

    // Scale to [-1, 1]
    return 70 * (n0 + n1 + n2);
  }

  private dot2(g: number[], x: number, y: number): number {
    return g[0] * x + g[1] * y;
  }

  /**
   * Fractal Brownian Motion - layered noise for natural terrain
   * @param x - X coordinate
   * @param y - Y coordinate
   * @param octaves - Number of noise layers (more = more detail)
   * @param persistence - Amplitude reduction per octave (0-1)
   * @returns Value in range [-1, 1]
   */
  fbm(x: number, y: number, octaves: number, persistence: number): number {
    let total = 0;
    let amplitude = 1;
    let frequency = 1;
    let maxValue = 0;

    for (let i = 0; i < octaves; i++) {
      total += this.noise2D(x * frequency, y * frequency) * amplitude;
      maxValue += amplitude;
      amplitude *= persistence;
      frequency *= 2;
    }

    // Normalize to [-1, 1]
    return total / maxValue;
  }
}
