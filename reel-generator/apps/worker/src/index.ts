/**
 * Render worker (deployment-shape demo).
 *
 * In production this is a separate process that pulls jobs off Redis/BullMQ
 * and runs the render pipeline with REAL providers, writing output to object
 * storage and progress back to Postgres. The web tier only enqueues.
 *
 * This skeleton version has no shared broker, so it demonstrates the loop by
 * generating a batch of demo jobs against its own in-memory store. Point
 * `mockProviders()` at real providers and `InMemoryJobStore` at a Redis/PG
 * adapter to make it real.
 */
import {
  InMemoryJobStore,
  processJob,
  mockProviders,
  type ReelRequest,
} from "@reel/core";

const CONCURRENCY = Number(process.env.WORKER_CONCURRENCY ?? 2);

const demoRequests: ReelRequest[] = [
  { topic: "why the sky is blue" },
  { topic: "the history of coffee" },
  { topic: "how bees make honey" },
];

async function main() {
  const store = new InMemoryJobStore();
  const providers = mockProviders();

  const ids = demoRequests.map((r) => store.create(r).id);
  console.log(`worker: ${ids.length} jobs queued, concurrency=${CONCURRENCY}`);

  // Simple bounded-concurrency drain of the queue.
  let cursor = 0;
  async function drain() {
    while (cursor < ids.length) {
      const id = ids[cursor++];
      await processJob(store, id, providers);
      const job = store.get(id)!;
      console.log(`  ✓ ${id} → ${job.status} (${job.outputUrl ?? job.error})`);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, drain));
  console.log("worker: batch complete");
}

main().catch((err) => {
  console.error("worker crashed:", err);
  process.exit(1);
});
