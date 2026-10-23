import type {
  SerializedInputEvent,
  SerializedClickEvent,
} from "~/shared/types";

export type InputHandler = (event: SerializedInputEvent) => void;
export type ClickHandler = (event: SerializedClickEvent) => void;

/**
 * InputManager - Captures DOM input events and serializes them for workers
 *
 * Handles:
 * - Keyboard events for player movement (WASD + Shift + Space)
 * - Click events on canvas for entity spawning
 */
export default class InputManager {
  private handler: InputHandler | null = null;
  private clickHandler: ClickHandler | null = null;
  private canvas: HTMLCanvasElement;
  private abortController: AbortController;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.abortController = new AbortController();
    this.setupEventListeners();
  }

  /**
   * Set the callback for input events (keyboard)
   */
  setEventCallback(handler: InputHandler): void {
    this.handler = handler;
  }

  /**
   * Set the callback for click events (canvas clicks for spawning)
   */
  setClickCallback(handler: ClickHandler): void {
    this.clickHandler = handler;
  }

  private setupEventListeners(): void {
    const options = { signal: this.abortController.signal };

    // Keyboard events (on window to capture regardless of focus)
    window.addEventListener("keydown", this.handleKeyboard, options);
    window.addEventListener("keyup", this.handleKeyboard, options);

    // Click events on canvas (for entity spawning)
    this.canvas.addEventListener("click", this.handleClick, options);
  }

  private handleKeyboard = (event: KeyboardEvent): void => {
    if (!this.handler) return;

    // Only capture movement keys (including spacebar for jump)
    const movementKeys = ["w", "a", "s", "d", "W", "A", "S", "D", "Shift", " "];
    if (!movementKeys.includes(event.key)) return;

    // Prevent default to avoid scrolling etc.
    event.preventDefault();

    const serialized: SerializedInputEvent = {
      type: event.type as "keydown" | "keyup",
      key: event.key,
      code: event.code,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
      metaKey: event.metaKey,
      repeat: event.repeat,
    };

    this.handler(serialized);
  };

  private handleClick = (event: MouseEvent): void => {
    if (!this.clickHandler) return;

    // Calculate normalized coordinates (0-1)
    const rect = this.canvas.getBoundingClientRect();
    const normalizedX = (event.clientX - rect.left) / rect.width;
    const normalizedY = (event.clientY - rect.top) / rect.height;

    const serialized: SerializedClickEvent = {
      type: "click",
      x: normalizedX,
      y: normalizedY,
    };

    this.clickHandler(serialized);
  };

  dispose(): void {
    this.abortController.abort();
  }
}
