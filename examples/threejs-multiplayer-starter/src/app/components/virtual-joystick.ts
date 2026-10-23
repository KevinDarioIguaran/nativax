/**
 * VirtualJoystick - Web Component for mobile movement control
 *
 * Circular joystick with draggable knob for touch-based movement.
 * Emits joystick-move events with angle, distance, and active state.
 * Distance > 0.7 maps to sprint for faster movement.
 * Inherits design tokens from :root.
 */

export interface JoystickState {
  angle: number; // Radians: 0 = up, PI/2 = right, PI = down, -PI/2 = left
  distance: number; // 0-1 normalized distance from center
  active: boolean; // Whether joystick is being touched
}

export class VirtualJoystick extends HTMLElement {
  private shadow: ShadowRoot;
  private base: HTMLElement | null = null;
  private knob: HTMLElement | null = null;
  private activeTouchId: number | null = null;
  private baseRadius = 60; // Half of 120px base
  private knobRadius = 25; // Half of 50px knob
  private maxDistance: number;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
    this.maxDistance = this.baseRadius - this.knobRadius;
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
          right: var(--space-5, 20px);
          z-index: 1000;
          touch-action: none;
          user-select: none;
          -webkit-user-select: none;
        }

        .base {
          width: 120px;
          height: 120px;
          border-radius: var(--radius-full, 9999px);
          background: var(--control-bg, rgba(0, 0, 0, 0.5));
          border: 2px solid var(--control-border, rgba(255, 255, 255, 0.3));
          position: relative;
          backdrop-filter: blur(4px);
        }

        .knob {
          width: 50px;
          height: 50px;
          border-radius: var(--radius-full, 9999px);
          background: rgba(74, 158, 255, 0.8);
          position: absolute;
          top: 50%;
          left: 50%;
          transform: translate(-50%, -50%);
          transition: background var(--transition-fast, 0.1s ease);
          pointer-events: none;
        }

        .knob.active {
          background: var(--color-accent, #4a9eff);
        }

        .knob.sprint {
          background: var(--color-sprint, #ff9e4a);
        }
      </style>

      <div class="base">
        <div class="knob"></div>
      </div>
    `;
  }

  private cacheElements(): void {
    this.base = this.shadow.querySelector(".base");
    this.knob = this.shadow.querySelector(".knob");
  }

  private addEventListeners(): void {
    this.base?.addEventListener("touchstart", this.handleTouchStart.bind(this));
    window.addEventListener("touchmove", this.handleTouchMove.bind(this));
    window.addEventListener("touchend", this.handleTouchEnd.bind(this));
    window.addEventListener("touchcancel", this.handleTouchEnd.bind(this));
  }

  private handleTouchStart(e: TouchEvent): void {
    e.preventDefault();
    if (this.activeTouchId !== null) return; // Already tracking a touch

    const touch = e.changedTouches[0];
    this.activeTouchId = touch.identifier;
    this.knob?.classList.add("active");
    this.updateKnobPosition(touch);
  }

  private handleTouchMove(e: TouchEvent): void {
    if (this.activeTouchId === null) return;

    // Find our tracked touch
    for (let i = 0; i < e.changedTouches.length; i++) {
      const touch = e.changedTouches[i];
      if (touch.identifier === this.activeTouchId) {
        e.preventDefault();
        this.updateKnobPosition(touch);
        break;
      }
    }
  }

  private handleTouchEnd(e: TouchEvent): void {
    if (this.activeTouchId === null) return;

    // Check if our tracked touch ended
    for (let i = 0; i < e.changedTouches.length; i++) {
      const touch = e.changedTouches[i];
      if (touch.identifier === this.activeTouchId) {
        this.activeTouchId = null;
        this.resetKnob();
        this.emitState(0, 0, false);
        break;
      }
    }
  }

  private updateKnobPosition(touch: Touch): void {
    if (!this.base || !this.knob) return;

    const rect = this.base.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;

    // Calculate offset from center
    let deltaX = touch.clientX - centerX;
    let deltaY = touch.clientY - centerY;

    // Calculate distance and angle
    // atan2(x, -y) gives: 0 = up, PI/2 = right, PI = down, -PI/2 = left
    const rawDistance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    const angle = Math.atan2(deltaX, -deltaY);

    // Clamp distance to max
    const clampedDistance = Math.min(rawDistance, this.maxDistance);
    const normalizedDistance = clampedDistance / this.maxDistance;

    // Calculate clamped position
    if (rawDistance > 0) {
      deltaX = (deltaX / rawDistance) * clampedDistance;
      deltaY = (deltaY / rawDistance) * clampedDistance;
    }

    // Update knob position
    this.knob.style.transform = `translate(calc(-50% + ${deltaX}px), calc(-50% + ${deltaY}px))`;

    // Update sprint visual
    if (normalizedDistance > 0.7) {
      this.knob.classList.add("sprint");
    } else {
      this.knob.classList.remove("sprint");
    }

    // Emit state
    this.emitState(angle, normalizedDistance, true);
  }

  private resetKnob(): void {
    if (!this.knob) return;
    this.knob.style.transform = "translate(-50%, -50%)";
    this.knob.classList.remove("active", "sprint");
  }

  private emitState(angle: number, distance: number, active: boolean): void {
    const state: JoystickState = { angle, distance, active };
    this.dispatchEvent(
      new CustomEvent("joystick-move", {
        detail: state,
        bubbles: true,
        composed: true,
      }),
    );
  }

  disconnectedCallback(): void {
    window.removeEventListener("touchmove", this.handleTouchMove.bind(this));
    window.removeEventListener("touchend", this.handleTouchEnd.bind(this));
    window.removeEventListener("touchcancel", this.handleTouchEnd.bind(this));
  }
}

customElements.define("virtual-joystick", VirtualJoystick);
