import type { Scene } from "../types.js";

/**
 * Resolves each scene's VisualSpec into a concrete asset URL.
 * Real impl: Pexels/Pixabay stock search (free, rate-limited — cache the
 * results) or an AI image model (SDXL/Flux) for "ai-image" scenes.
 */
export interface VisualProvider {
  source(scenes: Scene[]): Promise<Scene[]>;
}

/**
 * Offline mock: deterministically maps each query to a placeholder asset URL.
 * Keyed by query so repeated queries "cache" to the same asset.
 */
export class MockVisualProvider implements VisualProvider {
  async source(scenes: Scene[]): Promise<Scene[]> {
    return scenes.map((scene) => ({
      ...scene,
      visual: {
        ...scene.visual,
        assetUrl:
          scene.visual.assetUrl ??
          `mock://stock/${encodeURIComponent(scene.visual.query)}.mp4`,
      },
    }));
  }
}
