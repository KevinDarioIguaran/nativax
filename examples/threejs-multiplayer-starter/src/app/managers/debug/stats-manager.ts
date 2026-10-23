import Stats from "stats.js";

/**
 * StatsManager - Wraps Stats.js for FPS/MS/MB monitoring
 */
export default class StatsManager {
  private stats: Stats | null = null;

  constructor() {
    this.stats = new Stats();
    this.stats.showPanel(0);
    document.body.appendChild(this.stats.dom);
  }

  beginFrame(): void {
    this.stats?.begin();
  }

  endFrame(): void {
    this.stats?.end();
  }

  dispose(): void {
    if (this.stats) {
      document.body.removeChild(this.stats.dom);
      this.stats = null;
    }
  }
}
