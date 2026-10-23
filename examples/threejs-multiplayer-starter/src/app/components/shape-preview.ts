import * as THREE from "three";

/**
 * ShapePreview - Three.js preview renderer for entity spawner
 *
 * Renders a small spinning preview of the selected shape.
 * Runs on main thread (overhead exceeds cost of worker transfer).
 */
export class ShapePreview {
  private static readonly ROTATION_SPEED = 0.5; // rad/s
  private static readonly CAMERA_DISTANCE = 2.5;

  private renderer: THREE.WebGLRenderer;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private mesh: THREE.Mesh | null = null;
  private animationId = 0;
  private lastTime = 0;

  private currentShape: "box" | "sphere" = "box";
  private currentSize = 1;

  // Reusable geometries/materials
  private boxGeometry: THREE.BoxGeometry;
  private sphereGeometry: THREE.SphereGeometry;
  private boxMaterial: THREE.MeshStandardMaterial;
  private sphereMaterial: THREE.MeshStandardMaterial;

  constructor(canvas: HTMLCanvasElement) {
    // Get actual canvas size from CSS
    const rect = canvas.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height) || 80;

    // Renderer - small, no antialiasing needed at this size
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: false,
    });
    this.renderer.setSize(size, size);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    // Scene
    this.scene = new THREE.Scene();

    // Camera - isometric-ish angle
    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, 10);
    const d = ShapePreview.CAMERA_DISTANCE;
    this.camera.position.set(d * 0.7, d * 0.5, d * 0.7);
    this.camera.lookAt(0, 0, 0);

    // Lighting
    const ambient = new THREE.AmbientLight(0xffffff, 0.6);
    const directional = new THREE.DirectionalLight(0xffffff, 0.8);
    directional.position.set(5, 5, 5);
    this.scene.add(ambient, directional);

    // Geometries (reuse on shape switch)
    this.boxGeometry = new THREE.BoxGeometry(1, 1, 1);
    this.sphereGeometry = new THREE.SphereGeometry(0.5, 16, 12);

    // Materials matching instanced meshes exactly
    this.boxMaterial = new THREE.MeshStandardMaterial({
      color: 0x8b4513,
      roughness: 0.7,
      metalness: 0.1,
    });
    this.sphereMaterial = new THREE.MeshStandardMaterial({
      color: 0x4169e1,
      roughness: 0.6,
      metalness: 0.2,
    });

    this.createMesh();
    this.animate();
  }

  private createMesh(): void {
    if (this.mesh) {
      this.scene.remove(this.mesh);
    }

    const geometry =
      this.currentShape === "box" ? this.boxGeometry : this.sphereGeometry;
    const material =
      this.currentShape === "box" ? this.boxMaterial : this.sphereMaterial;

    this.mesh = new THREE.Mesh(geometry, material);
    this.applySize();
    this.scene.add(this.mesh);
  }

  private applySize(): void {
    if (!this.mesh) return;
    this.mesh.scale.setScalar(this.currentSize);
  }

  setShape(shape: "box" | "sphere"): void {
    if (this.currentShape === shape) return;
    this.currentShape = shape;
    this.createMesh();
  }

  setSize(size: number): void {
    this.currentSize = size;
    this.applySize();
  }

  private animate = (): void => {
    this.animationId = requestAnimationFrame(this.animate);

    const now = performance.now();
    const delta = (now - this.lastTime) / 1000;
    this.lastTime = now;

    if (this.mesh) {
      this.mesh.rotation.y += ShapePreview.ROTATION_SPEED * delta;
    }

    this.renderer.render(this.scene, this.camera);
  };

  dispose(): void {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = 0;
    }

    this.boxGeometry.dispose();
    this.sphereGeometry.dispose();
    this.boxMaterial.dispose();
    this.sphereMaterial.dispose();
    this.renderer.dispose();

    this.mesh = null;
  }
}
