import type { Job, Reel, ReelRequest } from "./types.js";
import type { Providers } from "./providers/index.js";

export interface ProgressReporter {
  (patch: Partial<Pick<Job, "status" | "progress" | "reel" | "outputUrl">>): void;
}

/**
 * Runs the full plan → render pipeline for one request, reporting progress at
 * each stage. Pure orchestration: every capability comes from an injected
 * provider, so the same function drives mock and real runs alike.
 */
export async function generateReel(
  req: ReelRequest,
  providers: Providers,
  jobId: string,
  report: ProgressReporter = () => {},
): Promise<Reel> {
  const aspect = req.aspect ?? "9:16";

  // 1. Script → timed scenes
  report({ status: "scripting", progress: 0.1 });
  const scenes = await providers.script.plan(req);

  // 2. Voiceover + word timings
  report({ status: "voicing", progress: 0.35 });
  const voiceover = await providers.voice.synthesize(
    scenes,
    req.voiceId ?? "narrator-warm",
  );

  // 3. Source visuals per scene
  report({ status: "sourcing-visuals", progress: 0.6 });
  const sourced = await providers.visuals.source(scenes);

  // 4. Captions are derived from voiceover word timings at render time;
  //    nothing to fetch, but we mark the stage for the UI.
  report({ status: "captioning", progress: 0.75 });

  const durationSec = sourced.length
    ? sourced[sourced.length - 1].endSec
    : (req.targetDurationSec ?? 0);

  const reel: Reel = {
    aspect,
    fps: 30,
    durationSec,
    music: req.musicTrackId
      ? { trackId: req.musicTrackId, gainDb: -18 }
      : { trackId: "lofi-01", gainDb: -18 },
    scenes: sourced,
    voiceover,
  };

  // 5. Assemble to MP4
  report({ status: "assembling", progress: 0.9, reel });
  const result = await providers.assembly.render(reel, jobId);

  report({ status: "done", progress: 1, outputUrl: result.outputUrl });
  return reel;
}
