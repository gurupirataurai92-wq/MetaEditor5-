/**
 * Scene data model — the engine-agnostic contract between the "planning" side
 * of the pipeline (LLM + TTS + stock APIs) and the "rendering" side
 * (FFmpeg / Remotion). Everything else is a transform to or from a Reel.
 */

export type Aspect = "9:16" | "1:1" | "16:9";

export interface WordTiming {
  word: string;
  startSec: number;
  endSec: number;
}

export interface VisualSpec {
  /** Where the pixels come from for a scene. */
  type: "stock" | "ai-image" | "color" | "upload";
  /** Search query (stock/ai) or hex color (color). */
  query: string;
  /** Resolved media URL once sourced; undefined until then. */
  assetUrl?: string;
  /** Optional Ken Burns / motion hint for the renderer. */
  motion?: "none" | "zoom-in" | "zoom-out" | "pan";
}

export interface Scene {
  id: string;
  /** Narration text for this scene (also the caption source). */
  text: string;
  startSec: number;
  endSec: number;
  visual: VisualSpec;
  captionStyle: string;
  transitionOut?: "none" | "fade" | "whip-pan" | "slide";
}

export interface MusicSpec {
  trackId: string;
  gainDb: number;
}

export interface Voiceover {
  voiceId: string;
  /** Resolved narration audio once synthesized. */
  audioUrl?: string;
  words: WordTiming[];
}

export interface Reel {
  aspect: Aspect;
  fps: number;
  durationSec: number;
  music?: MusicSpec;
  scenes: Scene[];
  voiceover?: Voiceover;
}

/** What a user submits to kick off generation. */
export interface ReelRequest {
  topic: string;
  /** Optional pre-written script; if absent we generate one from `topic`. */
  script?: string;
  voiceId?: string;
  captionStyle?: string;
  musicTrackId?: string;
  targetDurationSec?: number;
  aspect?: Aspect;
}

export type JobStatus =
  | "queued"
  | "scripting"
  | "voicing"
  | "sourcing-visuals"
  | "captioning"
  | "assembling"
  | "done"
  | "failed";

export interface Job {
  id: string;
  request: ReelRequest;
  status: JobStatus;
  /** 0..1 coarse progress for the UI. */
  progress: number;
  reel?: Reel;
  /** URL of the finished MP4 once assembled. */
  outputUrl?: string;
  error?: string;
  createdAt: number;
  updatedAt: number;
}
