import * as THREE from "three";
import type { GLTF } from "three/examples/jsm/loaders/GLTFLoader.js";
import type Resources from "../systems/resources";
import type Debug from "../systems/debug";
import type { DebugFolder } from "../systems/debug";
import { config } from "~/shared/config";

/**
 * Animation name mappings for the fox model
 * Maps our semantic names to the actual clip names in the GLTF
 */
const ANIMATION_NAMES = {
  idle: "Survey", // Fox model uses "Survey" for idle animation
  walking: "Walk",
  running: "Run",
} as const;

/**
 * Fox - Animated fox character mesh
 *
 * Handles rendering and animation only.
 * Movement is controlled by the Physics Worker.
 * Animations are triggered by RenderExperience based on player input.
 */
export default class Fox {
  private scene: THREE.Scene;
  private debugFolder: DebugFolder | null = null;

  resource: GLTF;
  model: THREE.Group;

  mixer: THREE.AnimationMixer;
  actions: {
    idle: THREE.AnimationAction;
    walking: THREE.AnimationAction;
    running: THREE.AnimationAction;
    current: THREE.AnimationAction;
  };

  // Debug-tunable parameters
  speed: number = 1;
  crossFadeDuration: number = config.animations.crossFadeDuration;

  // Track current animation by name (not action ref) to distinguish "jumping" from "running"
  currentAnimation: "idle" | "walking" | "running" | "jumping" = "idle";

  constructor(scene: THREE.Scene, resources: Resources, debug?: Debug) {
    this.scene = scene;
    this.resource = resources.items.foxModel as GLTF;

    // Set scale
    this.model = this.resource.scene;
    this.model.scale.set(0.02, 0.02, 0.02);

    // Add to scene
    this.scene.add(this.model);

    // Add shadows
    this.model.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.castShadow = true;
      }
    });

    // Build animation map by name for reliable lookup
    const animationMap = new Map<string, THREE.AnimationClip>();
    for (const clip of this.resource.animations) {
      animationMap.set(clip.name, clip);
    }

    /**
     * Get a clip by name with fallback to first animation
     */
    const getClip = (
      semanticName: keyof typeof ANIMATION_NAMES,
    ): THREE.AnimationClip => {
      const clipName = ANIMATION_NAMES[semanticName];
      const clip = animationMap.get(clipName);

      if (!clip) {
        console.warn(
          `[Fox] Animation "${clipName}" not found. ` +
            `Available animations: ${Array.from(animationMap.keys()).join(", ")}. ` +
            `Falling back to first animation.`,
        );
        return this.resource.animations[0];
      }

      return clip;
    };

    // Create animation actions by name
    this.mixer = new THREE.AnimationMixer(this.model);
    this.actions = {
      idle: this.mixer.clipAction(getClip("idle")),
      walking: this.mixer.clipAction(getClip("walking")),
      running: this.mixer.clipAction(getClip("running")),
      current: this.mixer.clipAction(getClip("idle")),
    };

    // Play idle animation
    this.actions.current.play();

    // Setup debug controls
    if (debug) {
      this.addDebug(debug);
    }
  }

  private addDebug(debug: Debug): void {
    if (!debug.active || !debug.ui) return;

    this.debugFolder = debug.ui.addFolder({ title: "Animation" });

    this.debugFolder
      .addBinding(this, "speed", {
        label: "Speed",
        min: 0,
        max: 3,
        step: 0.1,
      })
      .on("change", () => {
        this.mixer.timeScale = this.speed;
      });

    this.debugFolder.addBinding(this, "crossFadeDuration", {
      label: "Cross Fade",
      min: 0,
      max: 2,
      step: 0.05,
    });

    this.debugFolder.addButton({ title: "Play Idle" }).on("click", () => {
      this.play("idle");
    });

    this.debugFolder.addButton({ title: "Play Walk" }).on("click", () => {
      this.play("walking");
    });

    this.debugFolder.addButton({ title: "Play Run" }).on("click", () => {
      this.play("running");
    });
  }

  play(name: "idle" | "walking" | "running" | "jumping") {
    // Early exit if already playing this animation
    if (name === this.currentAnimation) return;

    // For jumping, use the running action but with jumping speed
    const actionName = name === "jumping" ? "running" : name;
    const newAction = this.actions[actionName];
    const oldAction = this.actions.current;

    // Apply animation-specific playback speed
    this.mixer.timeScale = config.animations.speeds[name];

    newAction.reset();
    newAction.play();
    newAction.crossFadeFrom(oldAction, this.crossFadeDuration, false);

    this.actions.current = newAction;
    this.currentAnimation = name;
  }

  dispose(): void {
    this.debugFolder?.dispose();
    this.mixer.stopAllAction();
    this.scene.remove(this.model);
  }
}
