/**
 * ErrorOverlay - Web Component for displaying application errors
 *
 * A reusable error overlay component that provides consistent error
 * presentation across the application. Uses Shadow DOM for style isolation.
 * Inherits design tokens from :root.
 *
 * @example
 * ```typescript
 * import { ErrorOverlay } from "./components/error-overlay";
 *
 * const overlay = new ErrorOverlay();
 * overlay.show(ErrorOverlay.MESSAGES.OFFSCREEN_CANVAS_UNSUPPORTED);
 * document.body.appendChild(overlay);
 * ```
 */
export class ErrorOverlay extends HTMLElement {
  private shadow: ShadowRoot;

  /**
   * Predefined error messages for common application errors
   * Use these for consistent messaging across the application
   */
  static readonly MESSAGES = {
    OFFSCREEN_CANVAS_UNSUPPORTED:
      "Your browser doesn't support OffscreenCanvas. Please use a modern browser like Chrome, Firefox, or Edge.",
    SHARED_ARRAY_BUFFER_UNSUPPORTED:
      "SharedArrayBuffer is not available. This may be due to missing cross-origin isolation headers (COOP/COEP). Please check your server configuration.",
    CANVAS_NOT_FOUND:
      "Canvas element #webgl not found in the document. Please ensure the HTML template is correct.",
    INIT_FAILED:
      "Failed to initialize application. Please refresh the page and try again.",
    WORKER_INIT_FAILED:
      "Failed to initialize web workers. Please ensure your browser supports Web Workers.",
    RESOURCE_LOAD_FAILED: (name: string) =>
      `Failed to load resource: ${name}. Some features may not work correctly.`,
    PHYSICS_INIT_FAILED:
      "Failed to initialize physics engine. Physics simulation will not be available.",
    WEBGL_NOT_SUPPORTED:
      "WebGL is not supported in your browser. Please use a browser with WebGL support.",
    GPU_CONTEXT_EXHAUSTED:
      "GPU resources exhausted. This can happen after rapid page refreshes. Please wait a moment and try again, or restart your browser.",
  } as const;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    this.render();
  }

  private render(): void {
    this.shadow.innerHTML = `
      <style>
        :host {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background: var(--color-surface-modal, rgba(0, 0, 0, 0.9));
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 10000;
          font-family: var(--font-family, system-ui, sans-serif);
        }

        :host([hidden]) {
          display: none;
        }

        .error-content {
          background: var(--color-surface, #1a1a1a);
          padding: 2rem 3rem;
          border-radius: var(--radius-md, 8px);
          border: 1px solid var(--color-border, #333);
          text-align: center;
          max-width: 500px;
          box-shadow: var(--shadow-lg, 0 4px 24px rgba(0, 0, 0, 0.5));
        }

        .error-title {
          color: var(--color-error, #ff4444);
          margin: 0 0 1rem;
          font-size: 1.5rem;
          font-weight: 600;
        }

        .error-message {
          color: var(--color-text-secondary, #ccc);
          margin: 0;
          line-height: 1.6;
          font-size: 1rem;
        }

        .error-details {
          margin-top: 1rem;
          padding-top: 1rem;
          border-top: 1px solid var(--color-border, #333);
          color: var(--color-text-muted, #888);
          font-size: var(--font-size-base, 14px);
          font-family: var(--font-mono, "SF Mono", Monaco, Consolas, monospace);
          text-align: left;
          white-space: pre-wrap;
          word-break: break-word;
        }

        .error-actions {
          margin-top: 1.5rem;
          display: flex;
          justify-content: center;
          gap: 1rem;
        }

        .error-button {
          background: var(--color-gray-800, #333);
          color: var(--color-text-primary, #fff);
          border: 1px solid var(--color-gray-600, #555);
          padding: 0.5rem 1.5rem;
          border-radius: var(--radius-sm, 4px);
          font-size: var(--font-size-base, 14px);
          font-family: inherit;
          cursor: pointer;
          transition: all var(--transition-normal, 0.15s ease);
        }

        .error-button:hover {
          background: var(--color-border, #444);
          border-color: var(--color-text-muted, #666);
        }

        .error-button:focus {
          outline: 2px solid var(--color-error, #ff4444);
          outline-offset: 2px;
        }
      </style>

      <div class="error-content">
        <h1 class="error-title">Error</h1>
        <p class="error-message"></p>
        <div class="error-details" hidden></div>
        <div class="error-actions">
          <button class="error-button" id="refresh-btn">Refresh Page</button>
        </div>
      </div>
    `;

    // Add refresh button handler
    const refreshBtn = this.shadow.getElementById("refresh-btn");
    refreshBtn?.addEventListener("click", () => {
      window.location.reload();
    });
  }

  /**
   * Show the error overlay with a message
   * @param message - The main error message to display
   * @param details - Optional technical details (shown in monospace font)
   */
  show(message: string, details?: string): void {
    const messageEl = this.shadow.querySelector(".error-message");
    const detailsEl = this.shadow.querySelector(".error-details");

    if (messageEl) {
      messageEl.textContent = message;
    }

    if (detailsEl) {
      if (details) {
        detailsEl.textContent = details;
        detailsEl.removeAttribute("hidden");
      } else {
        detailsEl.setAttribute("hidden", "");
      }
    }

    this.removeAttribute("hidden");
  }

  /**
   * Hide the error overlay
   */
  hide(): void {
    this.setAttribute("hidden", "");
  }

  /**
   * Set the title of the error overlay
   * @param title - The title to display (default: "Error")
   */
  setTitle(title: string): void {
    const titleEl = this.shadow.querySelector(".error-title");
    if (titleEl) {
      titleEl.textContent = title;
    }
  }
}

// Register the custom element
customElements.define("error-overlay", ErrorOverlay);
