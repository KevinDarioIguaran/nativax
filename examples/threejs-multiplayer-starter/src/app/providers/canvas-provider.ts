import type { ViewportSize } from "~/shared/types";

/**
 * Provides canvas element and OffscreenCanvas transfer.
 */
export default class CanvasProvider {
  private canvas: HTMLCanvasElement;
  private _offscreen: OffscreenCanvas | null = null;
  private _transferred: boolean = false;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
  }

  /**
   * Check if OffscreenCanvas is supported
   */
  static isSupported(): boolean {
    const canvas = document.createElement("canvas");
    return typeof canvas.transferControlToOffscreen === "function";
  }

  /**
   * Get current viewport size
   */
  getViewport(): ViewportSize {
    return {
      width: this.canvas.clientWidth,
      height: this.canvas.clientHeight,
      pixelRatio: Math.min(window.devicePixelRatio, 2),
    };
  }

  /**
   * Transfer canvas control to an OffscreenCanvas.
   * Can only be called once.
   */
  transferToOffscreen(): OffscreenCanvas {
    if (this._transferred) {
      throw new Error("Canvas has already been transferred");
    }

    this._offscreen = this.canvas.transferControlToOffscreen();
    this._transferred = true;

    return this._offscreen;
  }

  /**
   * Check if canvas has been transferred
   */
  get isTransferred(): boolean {
    return this._transferred;
  }

  /**
   * Get the underlying canvas element (for input events)
   */
  get element(): HTMLCanvasElement {
    return this.canvas;
  }
}
