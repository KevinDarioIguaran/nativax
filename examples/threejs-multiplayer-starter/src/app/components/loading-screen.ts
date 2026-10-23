/**
 * LoadingScreen - Web Component for displaying loading progress and start button
 *
 * Shows experiment description, device-specific instructions, loading progress,
 * then displays a "Click to Start" button to unlock audio (browser autoplay policy).
 * Uses Shadow DOM for style isolation. Inherits design tokens from :root.
 */
import { isMobile } from "../utils/device-detector";

export class LoadingScreen extends HTMLElement {
  private shadow: ShadowRoot;
  private onStartCallback: (() => void) | null = null;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    this.render();
  }

  private render(): void {
    const mobile = isMobile();

    this.shadow.innerHTML = `
      <style>
        :host {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background: var(--color-surface, #1a1a1a);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9999;
          font-family: var(--font-family, system-ui, sans-serif);
          transition: opacity var(--transition-slow, 0.3s ease);
          overflow-y: auto;
        }

        :host([hidden]) {
          opacity: 0;
          pointer-events: none;
        }

        .content {
          text-align: center;
          max-width: 420px;
          padding: var(--space-5, 20px);
        }

        .title {
          color: var(--color-text-primary, #fff);
          font-size: var(--font-size-xl, 20px);
          font-weight: 600;
          margin: 0 0 var(--space-2, 8px);
          letter-spacing: 0.02em;
        }

        .subtitle {
          font-family: var(--font-mono, monospace);
          color: var(--color-text-secondary, #a3a3a3);
          font-size: var(--font-size-xs, 11px);
          margin: 0 0 var(--space-4, 16px);
          line-height: 1.5;
        }

        .instructions {
          background: var(--color-surface-elevated, rgba(30, 30, 30, 0.95));
          border: 1px solid var(--color-border-subtle, rgba(255, 255, 255, 0.15));
          border-radius: var(--radius-lg, 12px);
          padding: var(--space-4, 16px);
          margin-bottom: var(--space-5, 20px);
          text-align: left;
        }

        .instructions-title {
          font-size: var(--font-size-xs, 11px);
          font-weight: 600;
          color: var(--color-text-secondary, #a3a3a3);
          text-transform: uppercase;
          letter-spacing: 0.08em;
          margin: 0 0 var(--space-3, 12px);
        }

        .instruction-row {
          display: flex;
          align-items: center;
          gap: var(--space-3, 12px);
          margin-bottom: var(--space-2, 8px);
          font-size: var(--font-size-sm, 13px);
          color: var(--color-text-primary, #fff);
        }

        .instruction-row:last-child {
          margin-bottom: 0;
        }

        .keys {
          display: flex;
          gap: var(--space-1, 4px);
          min-width: 80px;
          justify-content: flex-end;
        }

        .key {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 24px;
          height: 24px;
          padding: 0 var(--space-2, 8px);
          background: var(--btn-bg-active, rgba(74, 158, 255, 0.15));
          border: 1px solid var(--btn-border-active, #4a9eff);
          border-radius: var(--radius-sm, 4px);
          font-family: var(--font-mono, monospace);
          font-size: var(--font-size-xs, 11px);
          font-weight: 500;
          color: var(--color-accent, #4a9eff);
        }

        .action {
          color: var(--color-text-secondary, #a3a3a3);
        }

        .hint {
          font-size: var(--font-size-xs, 11px);
          color: var(--color-text-muted, #666);
          margin-top: var(--space-3, 12px);
          padding-top: var(--space-3, 12px);
          border-top: 1px solid var(--color-border-subtle, rgba(255, 255, 255, 0.15));
        }

        .progress-container {
          width: 100%;
          height: 4px;
          background: var(--color-gray-800, #333);
          border-radius: 2px;
          overflow: hidden;
          margin-bottom: var(--space-2, 8px);
        }

        .progress-bar {
          height: 100%;
          background: var(--color-accent-gradient, linear-gradient(90deg, #4a9eff, #00d4ff));
          width: 0%;
          transition: width var(--transition-slow, 0.3s ease);
          border-radius: 2px;
        }

        .progress-text {
          color: var(--color-text-secondary, #888);
          font-size: var(--font-size-sm, 13px);
          margin: 0;
          min-height: 1.25rem;
        }

        .start-button {
          display: none;
          background: var(--color-accent, #4a9eff);
          color: var(--color-text-primary, #fff);
          border: 2px solid var(--color-accent, #4a9eff);
          padding: var(--space-3, 12px) var(--space-6, 24px);
          font-size: var(--font-size-base, 14px);
          font-weight: 500;
          letter-spacing: 0.08em;
          border-radius: var(--radius-md, 8px);
          cursor: pointer;
          transition: all var(--transition-normal, 0.15s ease);
          margin-top: var(--space-4, 16px);
          text-transform: uppercase;
          font-family: inherit;
        }

        .start-button:hover {
          background: var(--color-accent-hover, #3a8eef);
          border-color: var(--color-accent-hover, #3a8eef);
        }

        .start-button:focus {
          outline: 2px solid var(--color-accent, #4a9eff);
          outline-offset: 4px;
        }

        .start-button:active {
          transform: scale(0.98);
        }

        .start-button.visible {
          display: inline-block;
          animation: fadeIn 0.5s ease-out;
        }

        .loading-indicator {
          display: flex;
          justify-content: center;
          gap: var(--space-2, 8px);
          margin-top: var(--space-4, 16px);
        }

        .loading-indicator.hidden {
          display: none;
        }

        .loading-dot {
          width: 8px;
          height: 8px;
          background: var(--color-accent, #4a9eff);
          border-radius: var(--radius-full, 9999px);
          animation: pulse 1.4s ease-in-out infinite;
        }

        .loading-dot:nth-child(2) {
          animation-delay: 0.2s;
        }

        .loading-dot:nth-child(3) {
          animation-delay: 0.4s;
        }

        @keyframes pulse {
          0%, 80%, 100% {
            opacity: 0.3;
            transform: scale(0.8);
          }
          40% {
            opacity: 1;
            transform: scale(1);
          }
        }

        @keyframes fadeIn {
          from {
            opacity: 0;
            transform: translateY(10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }

        @media (max-width: 480px) {
          .content {
            padding: var(--space-4, 16px);
          }

          .title {
            font-size: var(--font-size-lg, 16px);
          }

          .keys {
            min-width: 70px;
          }
        }
      </style>

      <div class="content">
        <h1 class="title">OffscreenCanvas Experiment</h1>
        <p class="subtitle">
          Three.js + Web Workers + Comlink<br>
          Physics and rendering in separate threads
        </p>

        <div class="instructions">
          <h2 class="instructions-title">Controls</h2>
          ${mobile ? this.getMobileInstructions() : this.getDesktopInstructions()}
          <p class="hint">Tap the preview in the top-right to change shape and size</p>
        </div>

        <div class="progress-container">
          <div class="progress-bar"></div>
        </div>
        <p class="progress-text">Initializing...</p>
        <div class="loading-indicator">
          <div class="loading-dot"></div>
          <div class="loading-dot"></div>
          <div class="loading-dot"></div>
        </div>
        <button class="start-button">${mobile ? "Tap to Start" : "Click to Start"}</button>
      </div>
    `;

    // Add start button handler
    const startBtn = this.shadow.querySelector(".start-button");
    startBtn?.addEventListener("click", () => {
      if (this.onStartCallback) {
        this.onStartCallback();
      }
      this.hide();
    });
  }

  private getDesktopInstructions(): string {
    return `
      <div class="instruction-row">
        <span class="keys"><span class="key">W</span><span class="key">A</span><span class="key">D</span></span>
        <span class="action">Move forward / turn</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Space</span></span>
        <span class="action">Jump</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Shift</span></span>
        <span class="action">Sprint (hold)</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Click</span></span>
        <span class="action">Spawn object</span>
      </div>
    `;
  }

  private getMobileInstructions(): string {
    return `
      <div class="instruction-row">
        <span class="keys"><span class="key">Joystick</span></span>
        <span class="action">Move and turn</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Edge</span></span>
        <span class="action">Sprint (push to edge)</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Button</span></span>
        <span class="action">Jump</span>
      </div>
      <div class="instruction-row">
        <span class="keys"><span class="key">Tap</span></span>
        <span class="action">Spawn object</span>
      </div>
    `;
  }

  /**
   * Update loading progress
   * @param progress - Progress value from 0 to 1
   * @param message - Optional status message
   */
  setProgress(progress: number, message?: string): void {
    const progressBar = this.shadow.querySelector<HTMLElement>(".progress-bar");
    const progressText = this.shadow.querySelector(".progress-text");

    if (progressBar) {
      progressBar.style.width = `${Math.min(100, Math.max(0, progress * 100))}%`;
    }

    if (progressText && message) {
      progressText.textContent = message;
    }
  }

  /**
   * Show the start button (called when loading is complete)
   */
  showStartButton(): void {
    const startBtn = this.shadow.querySelector(".start-button");
    const loadingIndicator = this.shadow.querySelector(".loading-indicator");
    const progressText = this.shadow.querySelector(".progress-text");

    startBtn?.classList.add("visible");
    loadingIndicator?.classList.add("hidden");

    if (progressText) {
      progressText.textContent = "Ready!";
    }
  }

  /**
   * Set callback for when start button is clicked
   */
  setOnStart(callback: () => void): void {
    this.onStartCallback = callback;
  }

  /**
   * Hide the loading screen with fade animation
   */
  hide(): void {
    this.setAttribute("hidden", "");
    // Remove from DOM after animation
    setTimeout(() => {
      this.remove();
    }, 300);
  }
}

// Register the custom element
customElements.define("loading-screen", LoadingScreen);
