import { NextResponse } from "next/server";
import type { ReelRequest } from "@reel/core";
import { store, enqueueAndProcess } from "@/lib/store";

export const dynamic = "force-dynamic";

/** GET /api/reels — list recent jobs. */
export function GET() {
  return NextResponse.json({ jobs: store.list() });
}

/** POST /api/reels — create a job and start generation. */
export async function POST(req: Request) {
  let body: Partial<ReelRequest>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid JSON body" }, { status: 400 });
  }

  const topic = body.topic?.trim();
  if (!topic) {
    return NextResponse.json({ error: "`topic` is required" }, { status: 400 });
  }

  const request: ReelRequest = {
    topic,
    script: body.script,
    voiceId: body.voiceId,
    captionStyle: body.captionStyle,
    musicTrackId: body.musicTrackId,
    targetDurationSec: body.targetDurationSec,
    aspect: body.aspect,
  };

  const job = store.create(request);
  enqueueAndProcess(job.id);

  return NextResponse.json({ job }, { status: 202 });
}
