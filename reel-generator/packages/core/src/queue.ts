import type { Job, ReelRequest } from "./types.js";
import { generateReel } from "./pipeline.js";
import { mockProviders, type Providers } from "./providers/index.js";

/**
 * Job store + queue abstraction. This in-memory implementation lets the
 * skeleton run in a single process. In production, back the store with
 * Postgres and the queue with Redis/BullMQ so the web tier and render
 * workers are separate, horizontally scalable processes.
 */
export interface JobStore {
  create(request: ReelRequest): Job;
  get(id: string): Job | undefined;
  list(): Job[];
  update(id: string, patch: Partial<Job>): Job | undefined;
}

export class InMemoryJobStore implements JobStore {
  private jobs = new Map<string, Job>();

  create(request: ReelRequest): Job {
    const now = Date.now();
    const job: Job = {
      id: `job_${now.toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
      request,
      status: "queued",
      progress: 0,
      createdAt: now,
      updatedAt: now,
    };
    this.jobs.set(job.id, job);
    return job;
  }

  get(id: string): Job | undefined {
    return this.jobs.get(id);
  }

  list(): Job[] {
    return [...this.jobs.values()].sort((a, b) => b.createdAt - a.createdAt);
  }

  update(id: string, patch: Partial<Job>): Job | undefined {
    const job = this.jobs.get(id);
    if (!job) return undefined;
    const next = { ...job, ...patch, updatedAt: Date.now() };
    this.jobs.set(id, next);
    return next;
  }
}

/**
 * Processes a single job through the pipeline, persisting progress to the
 * store as it goes. A worker loop calls this; the web API just enqueues.
 */
export async function processJob(
  store: JobStore,
  jobId: string,
  providers: Providers = mockProviders(),
): Promise<void> {
  const job = store.get(jobId);
  if (!job) throw new Error(`job not found: ${jobId}`);

  try {
    await generateReel(job.request, providers, jobId, (patch) => {
      store.update(jobId, patch);
    });
  } catch (err) {
    store.update(jobId, {
      status: "failed",
      error: err instanceof Error ? err.message : String(err),
    });
  }
}
