// ============================================
// Input Events (Main Thread → Workers)
// ============================================

export type InputEventType = "keydown" | "keyup";

export interface SerializedKeyboardEvent {
  type: "keydown" | "keyup";
  key: string;
  code: string;
  ctrlKey: boolean;
  shiftKey: boolean;
  metaKey: boolean;
  repeat: boolean;
}

export interface SerializedClickEvent {
  type: "click";
  /** Normalized screen X (0-1, left to right) */
  x: number;
  /** Normalized screen Y (0-1, top to bottom) */
  y: number;
}

export type SerializedInputEvent =
  | SerializedKeyboardEvent
  | SerializedClickEvent;

// ============================================
// Viewport / Sizing
// ============================================

export interface ViewportSize {
  width: number;
  height: number;
  pixelRatio: number;
}

export interface ElementBounds {
  left: number;
  top: number;
  width: number;
  height: number;
}

// ============================================
// Debug Events (Bidirectional)
// ============================================

export interface DebugBinding {
  id: string;
  folder: string;
  label: string;
  value: unknown;
  type: "number" | "boolean" | "color" | "select" | "button";
  options?: {
    min?: number;
    max?: number;
    step?: number;
    choices?: Record<string, unknown>;
  };
}

export interface DebugUpdateEvent {
  id: string;
  value: unknown;
}

export interface DebugButtonEvent {
  id: string;
}
