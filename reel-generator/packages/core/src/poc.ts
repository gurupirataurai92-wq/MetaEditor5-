/**
 * Offline proof-of-concept: runs the full pipeline with mock providers and
 * prints the resulting plan + job status. No API keys, no ffmpeg required.
 *
 *   pnpm --filter @reel/core poc
 */
import { InMemoryJobStore, processJob } from "./queue.js";
import type { ReelRequest } from "./types.js";

const request: ReelRequest = {
  topic: process.argv[2] ?? "octopuses",
  captionStyle: "karaoke-bold-yellow",
  voiceId: "narrator-warm",
};

const store = new InMemoryJobStore();
const job = store.create(request);

console.log(`> queued ${job.id} for topic "${request.topic}"\n`);

await processJob(store, job.id);

const done = store.get(job.id)!;
console.log(`status:   ${done.status}`);
console.log(`progress: ${Math.round(done.progress * 100)}%`);
console.log(`output:   ${done.outputUrl ?? "(none)"}`);
if (done.error) console.log(`error:    ${done.error}`);

if (done.reel) {
  console.log(`\nreel: ${done.reel.durationSec}s, ${done.reel.scenes.length} scenes\n`);
  for (const s of done.reel.scenes) {
    console.log(
      `  [${s.startSec.toFixed(1)}-${s.endSec.toFixed(1)}s] ${s.id}  ` +
        `visual=${s.visual.query}\n    "${s.text}"`,
    );
  }
}
