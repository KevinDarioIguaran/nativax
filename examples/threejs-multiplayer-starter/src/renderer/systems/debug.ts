import type { DebugBinding, DebugUpdateEvent } from "~/shared/types";

type DebugActionHandler = () => void;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type DebugTarget = Record<string, any>;

/**
 * DebugFolder interface - compatible subset of Tweakpane FolderApi
 */
export interface DebugFolder {
  addBinding(
    target: DebugTarget,
    property: string,
    options?: {
      label?: string;
      min?: number;
      max?: number;
      step?: number;
    },
  ): { on(event: string, callback: () => void): unknown };

  addButton(options: { title: string }): {
    on(event: string, callback: () => void): unknown;
  };

  dispose(): void;
}

/**
 * Debug - Debug state management for worker contexts
 *
 * Collects debug bindings from scene objects and forwards them to main thread.
 * Receives updates from main thread and applies them to registered targets.
 */
export default class Debug {
  active: boolean;

  private bindings: Map<string, DebugBinding> = new Map();
  private targets: Map<string, { obj: DebugTarget; prop: string }> = new Map();
  private actions: Map<string, DebugActionHandler> = new Map();
  private changeCallbacks: Map<string, DebugActionHandler> = new Map();

  // Stub UI for compatibility with existing World code
  ui: DebugUI | null;

  constructor(active: boolean = false) {
    this.active = active;
    this.ui = active ? new DebugUI(this) : null;
  }

  /**
   * Register a binding target so updates from main thread can be applied
   */
  registerTarget(id: string, obj: DebugTarget, prop: string): void {
    this.targets.set(id, { obj, prop });
  }

  /**
   * Register a binding to be sent to main thread
   */
  registerBinding(binding: DebugBinding): void {
    this.bindings.set(binding.id, binding);
  }

  /**
   * Register an action handler
   */
  registerAction(id: string, handler: DebugActionHandler): void {
    this.actions.set(id, handler);
  }

  /**
   * Register a change callback for a binding
   */
  registerChangeCallback(id: string, handler: DebugActionHandler): void {
    this.changeCallbacks.set(id, handler);
  }

  /**
   * Get all bindings for main thread
   */
  getBindings(): DebugBinding[] {
    return Array.from(this.bindings.values());
  }

  /**
   * Apply update from main thread
   */
  applyUpdate(event: DebugUpdateEvent): void {
    const target = this.targets.get(event.id);
    if (target) {
      target.obj[target.prop] = event.value;
    }

    // Update stored binding value
    const binding = this.bindings.get(event.id);
    if (binding) {
      binding.value = event.value;
    }

    // Call registered change callback
    const callback = this.changeCallbacks.get(event.id);
    if (callback) {
      callback();
    }
  }

  /**
   * Trigger an action from main thread
   */
  triggerAction(id: string): void {
    const handler = this.actions.get(id);
    handler?.();
  }

  // Stats stubs - timing is handled via callbacks to main thread
  begin(): void {}
  end(): void {}

  dispose(): void {
    this.bindings.clear();
    this.targets.clear();
    this.actions.clear();
  }
}

/**
 * DebugUI - Mimics Tweakpane API for worker context
 *
 * Creates bindings that will be synced to main thread Tweakpane.
 */
class DebugUI {
  private debug: Debug;

  constructor(debug: Debug) {
    this.debug = debug;
  }

  addFolder(options: { title: string }): DebugFolder {
    return new DebugFolderImpl(this.debug, options.title);
  }
}

class DebugFolderImpl implements DebugFolder {
  private debug: Debug;
  private folder: string;

  constructor(debug: Debug, folder: string) {
    this.debug = debug;
    this.folder = folder;
  }

  addBinding(
    target: DebugTarget,
    property: string,
    options?: {
      label?: string;
      min?: number;
      max?: number;
      step?: number;
    },
  ): DebugBindingHandle {
    const label = options?.label ?? property;
    const id = `${this.folder}:${label}`;
    const value = target[property];

    // Detect type from value
    let type: "number" | "boolean" | "color" | "button";
    if (typeof value === "boolean") {
      type = "boolean";
    } else if (typeof value === "string" && value.startsWith("#")) {
      type = "color";
    } else if (
      typeof value === "object" &&
      value !== null &&
      "r" in value &&
      "g" in value &&
      "b" in value
    ) {
      type = "color";
    } else {
      type = "number";
    }

    const binding: DebugBinding = {
      id,
      folder: this.folder,
      label,
      value,
      type,
      options: {
        min: options?.min,
        max: options?.max,
        step: options?.step,
      },
    };

    this.debug.registerBinding(binding);
    this.debug.registerTarget(id, target, property);

    return new DebugBindingHandle(this.debug, id);
  }

  addButton(options: { title: string }): DebugButtonHandle {
    const id = `${this.folder}:${options.title}`;

    const binding: DebugBinding = {
      id,
      folder: this.folder,
      label: options.title,
      value: null,
      type: "button",
    };

    this.debug.registerBinding(binding);

    return new DebugButtonHandle(this.debug, id);
  }

  dispose(): void {}
}

class DebugBindingHandle {
  private debug: Debug;
  private id: string;

  constructor(debug: Debug, id: string) {
    this.debug = debug;
    this.id = id;
  }

  on(event: string, callback: () => void): this {
    if (event === "change") {
      this.debug.registerChangeCallback(this.id, callback);
    }
    return this;
  }
}

class DebugButtonHandle {
  private debug: Debug;
  private id: string;

  constructor(debug: Debug, id: string) {
    this.debug = debug;
    this.id = id;
  }

  on(event: string, callback: () => void): this {
    if (event === "click") {
      this.debug.registerAction(this.id, callback);
    }
    return this;
  }
}
