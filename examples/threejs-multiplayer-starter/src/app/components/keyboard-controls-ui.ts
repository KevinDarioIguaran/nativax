/**
 * KeyboardControlsUI - Web Component showing WASD, Shift, Space keys
 *
 * Displays keyboard controls with real-time press highlighting.
 * Fixed position at bottom-right of screen.
 * Uses Shadow DOM for style isolation. Inherits design tokens from :root.
 */

export class KeyboardControlsUI extends HTMLElement {
  private shadow: ShadowRoot;
  private keyElements: Map<string, HTMLElement> = new Map();
  private boundKeyDown: (e: KeyboardEvent) => void;
  private boundKeyUp: (e: KeyboardEvent) => void;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    this.boundKeyDown = this.handleKeyDown.bind(this);
    this.boundKeyUp = this.handleKeyUp.bind(this);
    this.render();
    this.cacheKeyElements();
    this.addEventListeners();
  }

  private render(): void {
    this.shadow.innerHTML = `
      <style>
        :host {
          position: fixed;
          bottom: var(--space-5, 20px);
          right: var(--space-5, 20px);
          z-index: 1000;
          font-family: var(--font-family, system-ui, sans-serif);
          user-select: none;
        }

        .container {
          background: var(--color-surface-overlay, rgba(0, 0, 0, 0.75));
          backdrop-filter: blur(8px);
          border-radius: var(--radius-lg, 12px);
          padding: var(--space-3, 12px);
          display: flex;
          align-items: flex-end;
          gap: var(--space-2, 8px);
        }

        .wasd-group {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: var(--space-1, 4px);
        }

        .wasd-row {
          display: flex;
          gap: var(--space-1, 4px);
        }

        .key {
          width: 36px;
          height: 36px;
          border: 2px solid var(--color-border, #444);
          border-radius: var(--radius-md, 8px);
          background: transparent;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: var(--font-size-xs, 11px);
          font-weight: 600;
          color: var(--color-text-muted, #666);
          text-transform: uppercase;
          transition: all var(--transition-fast, 0.1s ease);
        }

        .key.space {
          width: 80px;
        }

        .key.active {
          border-color: var(--btn-border-active, #4a9eff);
          background: var(--btn-bg-active, rgba(74, 158, 255, 0.15));
          color: var(--color-text-primary, #fff);
        }
      </style>

      <div class="container">
        <div class="wasd-group">
          <div class="wasd-row">
            <div class="key" data-key="w">W</div>
          </div>
          <div class="wasd-row">
            <div class="key" data-key="shift">⇧</div>
            <div class="key" data-key="a">A</div>
            <div class="key" data-key="d">D</div>
          </div>
        </div>
        <div class="key space" data-key="space">SPACE</div>
      </div>
    `;
  }

  private cacheKeyElements(): void {
    const keys = this.shadow.querySelectorAll<HTMLElement>(".key[data-key]");
    keys.forEach((el) => {
      const key = el.dataset.key;
      if (key) this.keyElements.set(key, el);
    });
  }

  private normalizeKey(e: KeyboardEvent): string | null {
    if (e.code === "Space") return "space";
    if (e.key === "Shift") return "shift";
    const k = e.key.toLowerCase();
    if (["w", "a", "d"].includes(k)) return k;
    return null;
  }

  private handleKeyDown(e: KeyboardEvent): void {
    const key = this.normalizeKey(e);
    if (key) this.keyElements.get(key)?.classList.add("active");
  }

  private handleKeyUp(e: KeyboardEvent): void {
    const key = this.normalizeKey(e);
    if (key) this.keyElements.get(key)?.classList.remove("active");
  }

  private addEventListeners(): void {
    window.addEventListener("keydown", this.boundKeyDown);
    window.addEventListener("keyup", this.boundKeyUp);
  }

  disconnectedCallback(): void {
    window.removeEventListener("keydown", this.boundKeyDown);
    window.removeEventListener("keyup", this.boundKeyUp);
  }
}

customElements.define("keyboard-controls-ui", KeyboardControlsUI);
