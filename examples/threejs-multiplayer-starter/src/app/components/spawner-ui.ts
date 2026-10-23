/**
 * SpawnerUI - Unified spawn configuration component
 *
 * Canvas preview IS the button. Clicking it opens a popover menu
 * with shape toggle and size slider. Works on both desktop and mobile.
 *
 * Uses native Popover API for light-dismiss behavior.
 */

import { config } from "~/shared/config";
import { ShapePreview } from "./shape-preview";

export interface SpawnConfig {
  shape: "box" | "sphere";
  size: number;
}

// SVG icons
const BOX_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"></path>
  <path d="m3.3 7 8.7 5 8.7-5"></path>
  <path d="M12 22V12"></path>
</svg>`;

const SPHERE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="10"></circle>
</svg>`;

export class SpawnerUI extends HTMLElement {
  private shadow: ShadowRoot;
  private selectedShape: "box" | "sphere" = "box";
  private selectedSize: number = config.spawner.defaultSize;
  private shapePreview: ShapePreview | null = null;
  private popoverId: string;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    // Unique ID for popover targeting
    this.popoverId = `spawner-menu-${Math.random().toString(36).slice(2, 8)}`;
    this.render();
    this.setupEventListeners();
  }

  connectedCallback(): void {
    // Init preview after element is in DOM so canvas has correct dimensions
    requestAnimationFrame(() => this.initPreview());
  }

  private render(): void {
    this.shadow.innerHTML = `
      <style>
        :host {
          position: fixed;
          top: var(--space-5, 20px);
          right: var(--space-5, 20px);
          z-index: 1000;
          font-family: var(--font-family, system-ui, sans-serif);
          user-select: none;
          -webkit-user-select: none;
        }

        /* Canvas button */
        .preview-button {
          width: 80px;
          height: 80px;
          padding: 0;
          border: 2px solid var(--control-border, rgba(255, 255, 255, 0.3));
          border-radius: var(--radius-lg, 12px);
          background: var(--control-bg, rgba(0, 0, 0, 0.5));
          backdrop-filter: blur(4px);
          cursor: pointer;
          transition: all var(--transition-normal, 0.15s ease);
          overflow: hidden;
        }

        .preview-button:hover {
          border-color: var(--color-accent, #4a9eff);
        }

        .preview-button:active {
          transform: scale(0.96);
        }

        .preview-canvas {
          width: 100%;
          height: 100%;
          display: block;
        }

        /* Popover menu - reset UA defaults */
        .menu {
          border: none;
          padding: 0;
          background: transparent;
          position: fixed;
          inset: unset;
          top: calc(var(--space-5, 20px) + 90px);
          right: var(--space-5, 20px);
          margin: 0;
        }

        .menu::backdrop {
          background: transparent;
        }

        .menu-content {
          background: var(--color-surface-elevated, rgba(30, 30, 30, 0.95));
          border: 1px solid var(--color-border-subtle, rgba(255, 255, 255, 0.15));
          border-radius: var(--radius-lg, 12px);
          padding: var(--space-4, 16px);
          width: 180px;
          box-shadow: var(--shadow-lg, 0 4px 24px rgba(0, 0, 0, 0.5));
          overflow: hidden;
          box-sizing: border-box;
        }

        /* Shape toggle - segmented control */
        .shape-toggle {
          display: block;
          margin-bottom: var(--space-4, 16px);
          cursor: pointer;
        }

        .toggle-input {
          position: absolute;
          opacity: 0;
          pointer-events: none;
        }

        .toggle-track {
          display: flex;
          position: relative;
          background: var(--slider-track, #333);
          border-radius: var(--radius-md, 8px);
          padding: 4px;
        }

        .toggle-indicator {
          position: absolute;
          top: 4px;
          left: 4px;
          width: calc(50% - 4px);
          height: calc(100% - 8px);
          background: var(--btn-bg-active, rgba(74, 158, 255, 0.15));
          border: 1px solid var(--btn-border-active, #4a9eff);
          border-radius: var(--radius-sm, 6px);
          transition: transform var(--transition-normal, 0.15s ease);
        }

        .toggle-input:checked + .toggle-track .toggle-indicator {
          transform: translateX(100%);
        }

        .toggle-option {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          height: 36px;
          z-index: 1;
          color: var(--color-text-muted, #666);
          transition: color var(--transition-normal, 0.15s ease);
        }

        /* Active states based on checkbox */
        .toggle-input:not(:checked) + .toggle-track .box-option {
          color: var(--color-text-primary, #fff);
        }

        .toggle-input:checked + .toggle-track .sphere-option {
          color: var(--color-text-primary, #fff);
        }

        /* Focus state */
        .toggle-input:focus-visible + .toggle-track {
          outline: 2px solid var(--color-accent, #4a9eff);
          outline-offset: 2px;
        }

        /* Size control */
        .size-control {
          margin-bottom: var(--space-3, 12px);
        }

        .label {
          font-size: var(--font-size-xs, 11px);
          font-weight: 600;
          color: var(--color-text-secondary, #a3a3a3);
          text-transform: uppercase;
          letter-spacing: 0.05em;
          margin-bottom: var(--space-2, 8px);
          display: block;
        }

        .slider {
          width: 100%;
          -webkit-appearance: none;
          appearance: none;
          height: 6px;
          background: var(--slider-track, #333);
          border-radius: 3px;
          cursor: pointer;
        }

        .slider::-webkit-slider-thumb {
          -webkit-appearance: none;
          width: 18px;
          height: 18px;
          background: var(--slider-thumb, #4a9eff);
          border-radius: var(--radius-full, 9999px);
          cursor: pointer;
          transition: transform var(--transition-fast, 0.1s ease);
        }

        .slider::-webkit-slider-thumb:hover {
          transform: scale(1.15);
        }

        .slider::-moz-range-thumb {
          width: 18px;
          height: 18px;
          background: var(--slider-thumb, #4a9eff);
          border: none;
          border-radius: var(--radius-full, 9999px);
          cursor: pointer;
        }

        /* Instructions */
        .instructions {
          font-size: var(--font-size-xs, 11px);
          color: var(--color-text-muted, #666);
          text-align: center;
          padding-top: var(--space-3, 12px);
          border-top: 1px solid var(--color-border, #444);
        }

        /* Mobile responsive */
        @media (max-width: 1024px) {
          .preview-button {
            width: 60px;
            height: 60px;
          }

          .menu {
            top: calc(var(--space-5, 20px) + 70px);
          }
        }
      </style>

      <button class="preview-button" popovertarget="${this.popoverId}">
        <canvas class="preview-canvas"></canvas>
      </button>

      <div id="${this.popoverId}" popover class="menu">
        <div class="menu-content">
          <label class="shape-toggle">
            <input type="checkbox" class="toggle-input" />
            <span class="toggle-track">
              <span class="toggle-indicator"></span>
              <span class="toggle-option box-option">${BOX_SVG}</span>
              <span class="toggle-option sphere-option">${SPHERE_SVG}</span>
            </span>
          </label>

          <div class="size-control">
            <label class="label">Size</label>
            <input
              type="range"
              class="slider"
              min="${config.spawner.minSize}"
              max="${config.spawner.maxSize}"
              step="0.1"
              value="${config.spawner.defaultSize}"
            >
          </div>

          <div class="instructions">Click canvas to spawn</div>
        </div>
      </div>
    `;
  }

  private initPreview(): void {
    const canvas =
      this.shadow.querySelector<HTMLCanvasElement>(".preview-canvas");
    if (canvas) {
      try {
        this.shapePreview = new ShapePreview(canvas);
        this.shapePreview.setShape(this.selectedShape);
        this.shapePreview.setSize(this.selectedSize);
      } catch (e) {
        console.warn("Failed to initialize shape preview:", e);
      }
    }
  }

  private setupEventListeners(): void {
    // Shape toggle (checkbox change)
    const toggleInput =
      this.shadow.querySelector<HTMLInputElement>(".toggle-input");
    toggleInput?.addEventListener("change", (e) => {
      const target = e.target as HTMLInputElement;
      this.selectedShape = target.checked ? "sphere" : "box";
      this.shapePreview?.setShape(this.selectedShape);
    });

    // Size slider
    const slider = this.shadow.querySelector<HTMLInputElement>(".slider");
    slider?.addEventListener("input", (e) => {
      const target = e.target as HTMLInputElement;
      this.setSize(parseFloat(target.value));
    });
  }

  private setSize(size: number): void {
    this.selectedSize = size;
    this.shapePreview?.setSize(size);
  }

  disconnectedCallback(): void {
    this.shapePreview?.dispose();
    this.shapePreview = null;
  }

  /**
   * Get the current spawn configuration
   */
  getSpawnConfig(): SpawnConfig {
    return {
      shape: this.selectedShape,
      size: this.selectedSize,
    };
  }

  /**
   * Programmatically set the shape
   */
  setSelectedShape(shape: "box" | "sphere"): void {
    if (this.selectedShape === shape) return;
    this.selectedShape = shape;

    // Sync checkbox state
    const toggleInput =
      this.shadow.querySelector<HTMLInputElement>(".toggle-input");
    if (toggleInput) {
      toggleInput.checked = shape === "sphere";
    }

    this.shapePreview?.setShape(shape);
  }

  /**
   * Programmatically set the size
   */
  setSelectedSize(size: number): void {
    this.selectedSize = Math.max(
      config.spawner.minSize,
      Math.min(config.spawner.maxSize, size),
    );

    const slider = this.shadow.querySelector<HTMLInputElement>(".slider");
    if (slider) slider.value = this.selectedSize.toString();

    this.shapePreview?.setSize(this.selectedSize);
  }
}

customElements.define("spawner-ui", SpawnerUI);
