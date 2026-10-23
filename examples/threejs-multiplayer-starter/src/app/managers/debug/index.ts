import type { DebugBinding, DebugUpdateEvent } from "~/shared/types";
import StatsManager from "./stats-manager";
import TweakpaneManager, {
  type MainThreadActions,
  type PhysicsDebugCallbacks,
} from "./tweakpane-manager";

export type { MainThreadActions, PhysicsDebugCallbacks };

/**
 * DebugManager - Facade for debug UI (Tweakpane + Stats.js)
 */
export default class DebugManager {
  private stats: StatsManager | null = null;
  private tweakpane: TweakpaneManager | null = null;
  readonly active: boolean;

  constructor() {
    this.active = window.location.hash === "#debug";

    if (this.active) {
      this.stats = new StatsManager();
      this.tweakpane = new TweakpaneManager();
    }
  }

  setMainThreadActions(actions: MainThreadActions): void {
    this.tweakpane?.setMainThreadActions(actions);
  }

  setPhysicsCallbacks(callbacks: PhysicsDebugCallbacks): void {
    this.tweakpane?.setPhysicsCallbacks(callbacks);
  }

  setUpdateCallback(callback: (event: DebugUpdateEvent) => void): void {
    this.tweakpane?.setUpdateCallback(callback);
  }

  setActionCallback(callback: (id: string) => void): void {
    this.tweakpane?.setActionCallback(callback);
  }

  registerBindings(bindings: DebugBinding[]): void {
    this.tweakpane?.registerBindings(bindings);
  }

  updateBinding(id: string, value: unknown): void {
    this.tweakpane?.updateBinding(id, value);
  }

  beginFrame(): void {
    this.stats?.beginFrame();
  }

  updateFrameTiming(_deltaMs: number): void {
    this.stats?.endFrame();
  }

  dispose(): void {
    this.tweakpane?.dispose();
    this.stats?.dispose();
    this.tweakpane = null;
    this.stats = null;
  }
}
