import type { Reel } from "../types.js";

export interface AssemblyResult {
  outputUrl: string;
  durationSec: number;
}

/**
 * Renders a fully-planned Reel (visuals sourced, voiceover synthesized,
 * captions timed) into a single MP4.
 * Real impl: build an FFmpeg filtergraph that stacks each scene's clip,
 * burns in ASS/karaoke captions from the word timings, overlays music
 * ducked under the voiceover, and muxes to 9:16 H.264.
 */
export interface AssemblyProvider {
  render(reel: Reel, jobId: string): Promise<AssemblyResult>;
}

/**
 * Offline mock: does no encoding. Validates the reel is renderable
 * (every scene has an asset, voiceover exists) and returns a fake output URL.
 * Swap for `FFmpegAssemblyProvider` when ffmpeg is available.
 */
export class MockAssemblyProvider implements AssemblyProvider {
  async render(reel: Reel, jobId: string): Promise<AssemblyResult> {
    const missing = reel.scenes.filter((s) => !s.visual.assetUrl);
    if (missing.length > 0) {
      throw new Error(
        `cannot assemble: ${missing.length} scene(s) missing visual assets`,
      );
    }
    if (!reel.voiceover) {
      throw new Error("cannot assemble: no voiceover");
    }
    return {
      outputUrl: `mock://output/${jobId}.mp4`,
      durationSec: reel.durationSec,
    };
  }
}

/**
 * Sketch of the real engine. Left unimplemented so the skeleton stays
 * offline-runnable; fill in with an ffmpeg child-process invocation.
 */
export class FFmpegAssemblyProvider implements AssemblyProvider {
  constructor(private readonly ffmpegPath = "ffmpeg") {}

  async render(_reel: Reel, _jobId: string): Promise<AssemblyResult> {
    throw new Error(
      "FFmpegAssemblyProvider not implemented yet — build the filtergraph here",
    );
  }
}
