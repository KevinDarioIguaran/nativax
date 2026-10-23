/**
 * LoadProgressTracker - Combines progress from multiple loading sources
 *
 * Tracks weighted progress from different loaders (audio, render assets, etc.)
 * and provides a combined progress value.
 */
export default class LoadProgressTracker {
  private sources: Map<string, { weight: number; progress: number }> =
    new Map();
  private onProgress: (progress: number) => void;

  constructor(onProgress: (progress: number) => void) {
    this.onProgress = onProgress;
  }

  /**
   * Register a loading source with its weight
   * @param name - Unique identifier for the source
   * @param weight - Relative weight (weights are normalized automatically)
   */
  addSource(name: string, weight: number): void {
    this.sources.set(name, { weight, progress: 0 });
  }

  /**
   * Create a progress callback for a specific source
   * @param name - The source name to update
   * @returns A callback function that updates this source's progress
   */
  createCallback(name: string): (progress: number) => void {
    return (progress: number) => {
      this.updateSource(name, progress);
    };
  }

  /**
   * Update progress for a specific source
   * @param name - The source name
   * @param progress - Progress value (0-1)
   */
  updateSource(name: string, progress: number): void {
    const source = this.sources.get(name);
    if (source) {
      source.progress = Math.min(1, Math.max(0, progress));
      this.emitCombinedProgress();
    }
  }

  /**
   * Get the current combined progress
   */
  getCombinedProgress(): number {
    if (this.sources.size === 0) return 0;

    // Calculate total weight for normalization
    let totalWeight = 0;
    for (const source of this.sources.values()) {
      totalWeight += source.weight;
    }

    if (totalWeight === 0) return 0;

    // Calculate weighted progress
    let combined = 0;
    for (const source of this.sources.values()) {
      combined += (source.weight / totalWeight) * source.progress;
    }

    return combined;
  }

  private emitCombinedProgress(): void {
    this.onProgress(this.getCombinedProgress());
  }

  /**
   * Reset all progress to zero
   */
  reset(): void {
    for (const source of this.sources.values()) {
      source.progress = 0;
    }
  }
}
