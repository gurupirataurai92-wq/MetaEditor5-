import { NextResponse } from "next/server";
import { store } from "@/lib/store";

export const dynamic = "force-dynamic";

/** GET /api/reels/:id — poll one job's status. */
export function GET(
  _req: Request,
  { params }: { params: { id: string } },
) {
  const job = store.get(params.id);
  if (!job) {
    return NextResponse.json({ error: "job not found" }, { status: 404 });
  }
  return NextResponse.json({ job });
}
