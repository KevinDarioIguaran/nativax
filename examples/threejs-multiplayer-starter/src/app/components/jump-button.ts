/**
 * JumpButton - Web Component for mobile jump control
 *
 * Simple circular button that emits jump-start/jump-end events.
 * Visual feedback on press with scale and color change.
 * Inherits design tokens from :root.
 */

export class JumpButton extends HTMLElement {
  private shadow: ShadowRoot;
  private button: HTMLElement | null = null;
  private activeTouchId: number | null = null;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    this.render();
    this.cacheElements();
    this.addEventListeners();
  }

  private render(): void {
    this.shadow.innerHTML = `
      <style>
        :host {
          position: fixed;
          bottom: var(--space-5, 20px);
          left: var(--space-5, 20px);
          z-index: 1000;
          touch-action: none;
          user-select: none;
          -webkit-user-select: none;
        }

        .button {
          width: 70px;
          height: 70px;
          border-radius: var(--radius-full, 9999px);
          background: var(--control-bg, rgba(0, 0, 0, 0.5));
          border: 2px solid var(--control-border, rgba(255, 255, 255, 0.3));
          display: flex;
          align-items: center;
          justify-content: center;
          color: rgba(255, 255, 255, 0.7);
          font-family: var(--font-family, system-ui, sans-serif);
          font-size: var(--font-size-xs, 11px);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          transition: all var(--transition-fast, 0.1s ease);
          backdrop-filter: blur(4px);
        }

        .button.pressed {
          background: rgba(74, 158, 255, 0.6);
          border-color: var(--color-accent, #4a9eff);
          transform: scale(0.95);
          color: var(--color-text-primary, #fff);
        }
      </style>

      <div class="button">Jump</div>
    `;
  }

  private cacheElements(): void {
    this.button = this.shadow.querySelector(".button");
  }

  private addEventListeners(): void {
    this.button?.addEventListener(
      "touchstart",
      this.handleTouchStart.bind(this),
    );
    window.addEventListener("touchend", this.handleTouchEnd.bind(this));
    window.addEventListener("touchcancel", this.handleTouchEnd.bind(this));
  }

  private handleTouchStart(e: TouchEvent): void {
    e.preventDefault();
    if (this.activeTouchId !== null) return;

    const touch = e.changedTouches[0];
    this.activeTouchId = touch.identifier;
    this.button?.classList.add("pressed");
    this.emitJump(true);
  }

  private handleTouchEnd(e: TouchEvent): void {
    if (this.activeTouchId === null) return;

    for (let i = 0; i < e.changedTouches.length; i++) {
      const touch = e.changedTouches[i];
      if (touch.identifier === this.activeTouchId) {
        this.activeTouchId = null;
        this.button?.classList.remove("pressed");
        this.emitJump(false);
        break;
      }
    }
  }

  private emitJump(pressed: boolean): void {
    const eventName = pressed ? "jump-start" : "jump-end";
    this.dispatchEvent(
      new CustomEvent(eventName, {
        bubbles: true,
        composed: true,
      }),
    );
  }

  disconnectedCallback(): void {
    window.removeEventListener("touchend", this.handleTouchEnd.bind(this));
    window.removeEventListener("touchcancel", this.handleTouchEnd.bind(this));
  }
}

customElements.define("jump-button", JumpButton);
