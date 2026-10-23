import { EventEmitter } from "~/shared/utils";

type TimeEvents = {
  tick: {
    delta: number;
    elapsed: number;
  };
};

/**
 * Time - Animation loop using requestAnimationFrame
 *
 * Works in both main thread and worker contexts via self.requestAnimationFrame.
 */
export default class Time extends EventEmitter<TimeEvents> {
  start: number;
  current: number;
  elapsed: number;
  delta: number;

  private animationFrameId: number | null = null;

  constructor() {
    super();

    this.start = performance.now();
    this.current = this.start;
    this.elapsed = 0;
    this.delta = 16;

    this.tick();
  }

  private tick = (): void => {
    const currentTime = performance.now();
    this.delta = currentTime - this.current;
    this.current = currentTime;
    this.elapsed = this.current - this.start;

    this.emit("tick", {
      delta: this.delta,
      elapsed: this.elapsed,
    });

    this.animationFrameId = self.requestAnimationFrame(this.tick);
  };

  dispose(): void {
    if (this.animationFrameId !== null) {
      self.cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  }
}
