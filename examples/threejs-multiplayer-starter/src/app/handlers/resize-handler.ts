import type { ViewportSize } from "~/shared/types";

/**
 * ResizeHandler - Handles viewport resize and pixel ratio changes
 *
 * Responsibilities:
 * - Observe canvas element size changes via ResizeObserver
 * - Track devicePixelRatio changes via matchMedia
 * - Emit viewport updates to callback
 */
export default class ResizeHandler {
  private element: HTMLElement;
  private onResize: (viewport: ViewportSize) => void;
  private resizeObserver: ResizeObserver | null = null;
  private pixelRatioMediaQuery: MediaQueryList | null = null;
  private pixelRatioHandler: (() => void) | null = null;

  constructor(
    element: HTMLElement,
    onResize: (viewport: ViewportSize) => void,
  ) {
    this.element = element;
    this.onResize = onResize;
  }

  /**
   * Start observing resize events
   */
  start(): void {
    // Observe element size changes
    this.resizeObserver = new ResizeObserver(() => {
      this.emitResize();
    });
    this.resizeObserver.observe(this.element);

    // Observe pixel ratio changes
    this.setupPixelRatioListener();
  }

  private setupPixelRatioListener(): void {
    this.pixelRatioHandler = (): void => {
      this.emitResize();
      // Re-register for next change with new media query
      this.updatePixelRatioMediaQuery();
    };

    this.updatePixelRatioMediaQuery();
  }

  private updatePixelRatioMediaQuery(): void {
    // Remove previous listener if exists
    if (this.pixelRatioMediaQuery && this.pixelRatioHandler) {
      this.pixelRatioMediaQuery.removeEventListener(
        "change",
        this.pixelRatioHandler,
      );
    }

    // Create new media query for current pixel ratio
    this.pixelRatioMediaQuery = matchMedia(
      `(resolution: ${window.devicePixelRatio}dppx)`,
    );

    if (this.pixelRatioHandler) {
      this.pixelRatioMediaQuery.addEventListener(
        "change",
        this.pixelRatioHandler,
        { once: true },
      );
    }
  }

  private emitResize(): void {
    const viewport: ViewportSize = {
      width: this.element.clientWidth,
      height: this.element.clientHeight,
      pixelRatio: Math.min(window.devicePixelRatio, 2),
    };
    this.onResize(viewport);
  }

  /**
   * Stop observing and clean up
   */
  dispose(): void {
    if (this.pixelRatioMediaQuery && this.pixelRatioHandler) {
      this.pixelRatioMediaQuery.removeEventListener(
        "change",
        this.pixelRatioHandler,
      );
    }
    this.pixelRatioMediaQuery = null;
    this.pixelRatioHandler = null;

    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
  }
}
