import { InMemoryJobStore, processJob } from "@reel/core";

/**
 * Process-wide singleton job store. Next.js can re-evaluate modules across
 * hot reloads, so we stash the store on globalThis to keep jobs alive.
 *
 * NOTE: single-process, in-memory — fine for the skeleton/demo. Production
 * replaces this with Postgres (store) + Redis/BullMQ (queue) and a separate
 * worker process (see apps/worker), so the web tier only enqueues.
 */
const globalForStore = globalThis as unknown as {
  __reelStore?: InMemoryJobStore;
};

export const store: InMemoryJobStore =
  globalForStore.__reelStore ?? new InMemoryJobStore();

if (!globalForStore.__reelStore) {
  globalForStore.__reelStore = store;
}

/**
 * Demo-mode enqueue: kick the pipeline in-process (fire-and-forget) with mock
 * providers. Swap for a real queue publish once a worker is wired up.
 */
export function enqueueAndProcess(jobId: string): void {
  void processJob(store, jobId).catch((err) => {
    console.error(`job ${jobId} failed:`, err);
  });
}
