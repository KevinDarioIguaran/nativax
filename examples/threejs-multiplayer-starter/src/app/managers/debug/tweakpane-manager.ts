import { Pane, type FolderApi } from "tweakpane";
import type { DebugBinding, DebugUpdateEvent } from "~/shared/types";
import {
  debugPhysicsConfig,
  debugPlayerConfig,
  debugSpawnerConfig,
} from "~/shared/debug-config";

export interface DebugUpdateCallback {
  (event: DebugUpdateEvent): void;
}

export interface DebugActionCallback {
  (id: string): void;
}

export interface MainThreadActions {
  spawnCubes?: (count: number) => void;
  spawnSpheres?: (count: number) => void;
  clearCubes?: () => void;
  getCubeCount?: () => number;
  getBoxCount?: () => number;
  getSphereCount?: () => number;
}

export interface PhysicsDebugCallbacks {
  onDensityChange?: (density: number) => void;
  onGravityChange?: (gravity: number) => void;
  onPlayerConfigChange?: (config: Partial<typeof debugPlayerConfig>) => void;
}

/**
 * TweakpaneManager - Manages Tweakpane debug UI
 */
export default class TweakpaneManager {
  private pane: Pane;
  private folders: Map<string, FolderApi> = new Map();
  private bindings: Map<string, DebugBinding> = new Map();
  private values: Map<string, unknown> = new Map();
  private onUpdate: DebugUpdateCallback | null = null;
  private onAction: DebugActionCallback | null = null;
  private mainThreadActions: MainThreadActions | null = null;
  private physicsCallbacks: PhysicsDebugCallbacks | null = null;

  constructor() {
    this.pane = new Pane({ title: "Debug", expanded: true });
  }

  setMainThreadActions(actions: MainThreadActions): void {
    this.mainThreadActions = actions;
    this.createCubeStormControls();
  }

  setPhysicsCallbacks(callbacks: PhysicsDebugCallbacks): void {
    this.physicsCallbacks = callbacks;
    this.createPhysicsControls();
    this.createPlayerControls();
    this.createSpawnerControls();
  }

  private createCubeStormControls(): void {
    if (!this.mainThreadActions) return;

    const folder = this.getOrCreateFolder("Cube Storm");
    folder.expanded = true;

    const cubeState = { count: 0 };
    const countBinding = folder.addBinding(cubeState, "count", {
      label: "Cubes",
      readonly: true,
    });

    const updateCount = (): void => {
      if (this.mainThreadActions?.getCubeCount) {
        cubeState.count = this.mainThreadActions.getCubeCount();
        countBinding.refresh();
      }
    };

    folder.addButton({ title: "Drop 100 Cubes" }).on("click", () => {
      this.mainThreadActions?.spawnCubes?.(100);
      setTimeout(updateCount, 100);
    });

    folder.addButton({ title: "Drop 500 Cubes" }).on("click", () => {
      this.mainThreadActions?.spawnCubes?.(500);
      setTimeout(updateCount, 100);
    });

    folder.addButton({ title: "Clear All Cubes" }).on("click", () => {
      this.mainThreadActions?.clearCubes?.();
      setTimeout(updateCount, 100);
    });

    updateCount();
  }

  private createPhysicsControls(): void {
    const folder = this.getOrCreateFolder("Physics");
    folder.expanded = false;

    folder
      .addBinding(debugPhysicsConfig, "density", {
        label: "Density",
        min: 0.1,
        max: 10,
        step: 0.1,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onDensityChange?.(ev.value);
      });

    folder
      .addBinding(debugPhysicsConfig, "gravity", {
        label: "Gravity",
        min: -50,
        max: 0,
        step: 1,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onGravityChange?.(ev.value);
      });
  }

  private createPlayerControls(): void {
    const folder = this.getOrCreateFolder("Player Physics");
    folder.expanded = false;

    folder
      .addBinding(debugPlayerConfig, "springStrength", {
        label: "Spring Strength",
        min: 0.1,
        max: 5,
        step: 0.1,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({
          springStrength: ev.value,
        });
      });

    folder
      .addBinding(debugPlayerConfig, "springDamping", {
        label: "Spring Damping",
        min: 0.01,
        max: 0.5,
        step: 0.01,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({
          springDamping: ev.value,
        });
      });

    folder
      .addBinding(debugPlayerConfig, "moveForce", {
        label: "Move Force",
        min: 5,
        max: 100,
        step: 1,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({ moveForce: ev.value });
      });

    folder
      .addBinding(debugPlayerConfig, "jumpForce", {
        label: "Jump Force",
        min: 1,
        max: 20,
        step: 0.5,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({ jumpForce: ev.value });
      });

    folder
      .addBinding(debugPlayerConfig, "floatingDistance", {
        label: "Float Distance",
        min: 0.1,
        max: 1,
        step: 0.05,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({
          floatingDistance: ev.value,
        });
      });

    folder
      .addBinding(debugPlayerConfig, "maxVelocity", {
        label: "Max Velocity",
        min: 1,
        max: 20,
        step: 0.5,
      })
      .on("change", (ev) => {
        this.physicsCallbacks?.onPlayerConfigChange?.({
          maxVelocity: ev.value,
        });
      });
  }

  private createSpawnerControls(): void {
    const folder = this.getOrCreateFolder("Spawner");
    folder.expanded = false;

    folder.addBinding(debugSpawnerConfig, "size", {
      label: "Spawn Size",
      min: 0.3,
      max: 3.0,
      step: 0.1,
    });

    folder.addBinding(debugSpawnerConfig, "projectileSpeed", {
      label: "Projectile Speed",
      min: 5,
      max: 50,
      step: 1,
    });
  }

  setUpdateCallback(callback: DebugUpdateCallback): void {
    this.onUpdate = callback;
  }

  setActionCallback(callback: DebugActionCallback): void {
    this.onAction = callback;
  }

  registerBindings(bindings: DebugBinding[]): void {
    for (const binding of bindings) {
      this.bindings.set(binding.id, binding);
      this.values.set(binding.id, binding.value);
      this.createControl(binding);
    }
  }

  private getOrCreateFolder(name: string): FolderApi {
    let folder = this.folders.get(name);
    if (!folder) {
      folder = this.pane.addFolder({ title: name, expanded: false });
      this.folders.set(name, folder);
    }
    return folder;
  }

  private createControl(binding: DebugBinding): void {
    const folder = this.getOrCreateFolder(binding.folder);
    const obj = { [binding.label]: binding.value };

    switch (binding.type) {
      case "number":
        folder
          .addBinding(obj, binding.label, {
            min: binding.options?.min,
            max: binding.options?.max,
            step: binding.options?.step,
          })
          .on("change", (ev) => this.handleChange(binding.id, ev.value));
        break;

      case "boolean":
        folder
          .addBinding(obj, binding.label)
          .on("change", (ev) => this.handleChange(binding.id, ev.value));
        break;

      case "color":
        folder
          .addBinding(obj, binding.label, { color: { type: "float" } })
          .on("change", (ev) => this.handleChange(binding.id, ev.value));
        break;

      case "select":
        folder
          .addBinding(obj, binding.label, { options: binding.options?.choices })
          .on("change", (ev) => this.handleChange(binding.id, ev.value));
        break;

      case "button":
        folder.addButton({ title: binding.label }).on("click", () => {
          this.onAction?.(binding.id);
        });
        break;
    }
  }

  private handleChange(id: string, value: unknown): void {
    this.values.set(id, value);
    this.onUpdate?.({ id, value });
  }

  updateBinding(id: string, value: unknown): void {
    this.values.set(id, value);
  }

  dispose(): void {
    this.pane.dispose();
    this.folders.clear();
    this.bindings.clear();
    this.values.clear();
    this.onUpdate = null;
    this.onAction = null;
  }
}
