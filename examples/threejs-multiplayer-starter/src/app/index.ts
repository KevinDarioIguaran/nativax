import CanvasProvider from "./providers/canvas-provider";
import InputManager from "./managers/input-manager";
import DebugManager from "./managers/debug";
import TouchInputHandler from "./managers/touch-input-handler";
import UIManager, { ErrorOverlay } from "./ui/ui-manager";
import WorkerCoordinator from "./coordinators/worker-coordinator";
import EntityCoordinator from "./coordinators/entity-coordinator";
import InputRouter from "./routing/input-router";
import SpawnHandler from "./handlers/spawn-handler";
import ResizeHandler from "./handlers/resize-handler";

/**
 * App - Main thread orchestrator
 *
 * Wires together managers and coordinators.
 */
export default class App {
  private canvas: CanvasProvider;
  private input: InputManager;
  private debug: DebugManager;
  private ui: UIManager;
  private coordinator: WorkerCoordinator;
  private entities: EntityCoordinator | null = null;
  private inputRouter: InputRouter | null = null;
  private touchHandler: TouchInputHandler | null = null;
  private spawnHandler: SpawnHandler | null = null;
  private resizeHandler: ResizeHandler | null = null;
  private _initialized = false;

  constructor() {
    this.ui = new UIManager();

    if (!CanvasProvider.isSupported()) {
      this.ui.showError(ErrorOverlay.MESSAGES.OFFSCREEN_CANVAS_UNSUPPORTED);
      throw new Error("OffscreenCanvas not supported");
    }

    if (typeof SharedArrayBuffer === "undefined") {
      this.ui.showError(ErrorOverlay.MESSAGES.SHARED_ARRAY_BUFFER_UNSUPPORTED);
      throw new Error("SharedArrayBuffer not supported");
    }

    const canvasElement = document.querySelector<HTMLCanvasElement>("#webgl");
    if (!canvasElement) {
      this.ui.showError(ErrorOverlay.MESSAGES.CANVAS_NOT_FOUND);
      throw new Error("Canvas element #webgl not found");
    }

    this.canvas = new CanvasProvider(canvasElement);
    this.input = new InputManager(canvasElement);
    this.debug = new DebugManager();
    this.coordinator = new WorkerCoordinator();

    this.ui.showLoadingScreen(() => {
      this.coordinator.getAudioBridge().unlockAudio();
    });

    this.init();
  }

  private async init(): Promise<void> {
    try {
      await this.initWorkers();
      this.setupEventListeners();
      this._initialized = true;
    } catch (error) {
      console.error("Failed to initialize app:", error);
      const details = error instanceof Error ? error.message : String(error);
      this.ui.showError(ErrorOverlay.MESSAGES.INIT_FAILED, details);
    }
  }

  private async initWorkers(): Promise<void> {
    const offscreen = this.canvas.transferToOffscreen();
    const viewport = this.canvas.getViewport();

    await this.coordinator.init(offscreen, viewport, this.debug.active, {
      onProgress: (progress) => this.ui.updateLoadProgress(progress),
      onReady: () => this.ui.showStartButton(),
      onFrameTiming: (deltaMs) => this.debug.updateFrameTiming(deltaMs),
    });

    const physicsApi = this.coordinator.getPhysicsApi();
    const renderApi = this.coordinator.getRenderApi();
    const sharedBuffer = this.coordinator.getSharedBuffer();

    this.entities = new EntityCoordinator(physicsApi, renderApi, sharedBuffer);
    this.inputRouter = new InputRouter(physicsApi, renderApi);

    const spawnerUI = this.ui.createSpawnerUI();
    this.ui.createKeyboardControlsUI();
    this.spawnHandler = new SpawnHandler(spawnerUI, this.entities, renderApi);

    // Setup mobile touch controls if on mobile device
    if (this.ui.isMobileDevice) {
      const { joystick, jumpButton } = this.ui.createMobileControls();
      this.touchHandler = new TouchInputHandler(
        joystick,
        jumpButton,
        this.inputRouter,
      );
    }

    this.coordinator.getAudioBridge().setupCallbacks(physicsApi, renderApi);
    await this.entities.initWorld();
    this.coordinator.startPhysics();

    if (this.debug.active) {
      this.setupDebug(renderApi);
    }
  }

  private async setupDebug(
    renderApi: Awaited<ReturnType<WorkerCoordinator["getRenderApi"]>>,
  ): Promise<void> {
    const physicsApi = this.coordinator.getPhysicsApi();

    this.debug.setUpdateCallback((event) => renderApi.updateDebug(event));
    this.debug.setActionCallback((id) => renderApi.triggerDebugAction(id));

    this.debug.setMainThreadActions({
      spawnCubes: (count) =>
        this.entities?.spawnTestObjects(count, 0).catch(console.error),
      spawnSpheres: (count) =>
        this.entities?.spawnTestObjects(0, count).catch(console.error),
      clearCubes: () => this.entities?.clearAll().catch(console.error),
      getCubeCount: () => this.entities?.getTotalCount() ?? 0,
      getBoxCount: () => this.entities?.getBoxCount() ?? 0,
      getSphereCount: () => this.entities?.getSphereCount() ?? 0,
    });

    this.debug.setPhysicsCallbacks({
      onDensityChange: (density) => physicsApi.updatePhysicsConfig({ density }),
      onGravityChange: (gravity) => physicsApi.updatePhysicsConfig({ gravity }),
      onPlayerConfigChange: (config) => physicsApi.updatePlayerConfig(config),
    });

    const bindings = await renderApi.getDebugBindings();
    this.debug.registerBindings(bindings);
  }

  private setupEventListeners(): void {
    this.input.setEventCallback((event) =>
      this.inputRouter?.handleInput(event),
    );
    this.input.setClickCallback((event) =>
      this.spawnHandler?.handleClick(event),
    );

    this.resizeHandler = new ResizeHandler(this.canvas.element, (viewport) => {
      this.coordinator.resize(viewport);
    });
    this.resizeHandler.start();

    window.addEventListener("beforeunload", () => this.dispose());

    if (this.debug.active) {
      const loop = (): void => {
        this.debug.beginFrame();
        requestAnimationFrame(loop);
      };
      loop();
    }
  }

  dispose(): void {
    this.ui.dispose();
    this.resizeHandler?.dispose();
    this.input.dispose();
    this.debug.dispose();
    this.spawnHandler?.dispose();
    this.touchHandler?.dispose();
    this.inputRouter?.dispose();
    this.entities?.dispose();
    this.coordinator.dispose();

    this.resizeHandler = null;
    this.spawnHandler = null;
    this.touchHandler = null;
    this.inputRouter = null;
    this.entities = null;
    this._initialized = false;
  }

  get initialized(): boolean {
    return this._initialized;
  }
}
