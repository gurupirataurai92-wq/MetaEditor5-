"use client";

import { useCallback, useRef, useState } from "react";
import type { Job } from "@reel/core";

const TERMINAL = new Set(["done", "failed"]);

export default function Home() {
  const [topic, setTopic] = useState("");
  const [script, setScript] = useState("");
  const [captionStyle, setCaptionStyle] = useState("karaoke-bold-yellow");
  const [job, setJob] = useState<Job | null>(null);
  const [busy, setBusy] = useState(false);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const poll = useCallback((id: string) => {
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      const res = await fetch(`/api/reels/${id}`);
      if (!res.ok) return;
      const { job } = (await res.json()) as { job: Job };
      setJob(job);
      if (TERMINAL.has(job.status)) {
        if (pollRef.current) clearInterval(pollRef.current);
        setBusy(false);
      }
    }, 400);
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!topic.trim()) return;
    setBusy(true);
    setJob(null);
    const res = await fetch("/api/reels", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        topic,
        script: script.trim() || undefined,
        captionStyle,
      }),
    });
    const { job } = (await res.json()) as { job: Job };
    setJob(job);
    poll(job.id);
  }

  return (
    <main className="wrap">
      <h1>🎬 Reel Generator</h1>
      <p className="sub">
        Faceless AI reels — topic in, vertical video out.{" "}
        <em>(skeleton: mock providers, no real render yet)</em>
      </p>

      <form className="panel" onSubmit={submit}>
        <label htmlFor="topic">Topic</label>
        <input
          id="topic"
          placeholder="e.g. why octopuses have three hearts"
          value={topic}
          onChange={(e) => setTopic(e.target.value)}
        />

        <label htmlFor="script">Script (optional — leave blank to auto-write)</label>
        <textarea
          id="script"
          placeholder="Paste your own narration, or let the generator write it."
          value={script}
          onChange={(e) => setScript(e.target.value)}
        />

        <label htmlFor="style">Caption style</label>
        <select
          id="style"
          value={captionStyle}
          onChange={(e) => setCaptionStyle(e.target.value)}
        >
          <option value="karaoke-bold-yellow">Karaoke · bold yellow</option>
          <option value="minimal-white">Minimal · white</option>
          <option value="gradient-pop">Gradient pop</option>
        </select>

        <button type="submit" disabled={busy}>
          {busy ? "Generating…" : "Generate reel"}
        </button>
      </form>

      {job && <JobView job={job} />}
    </main>
  );
}

function JobView({ job }: { job: Job }) {
  return (
    <section className="job panel">
      <div className="status">
        <span>{prettyStatus(job.status)}</span>
        <span>{Math.round(job.progress * 100)}%</span>
      </div>
      <div className="bar">
        <i style={{ width: `${Math.round(job.progress * 100)}%` }} />
      </div>

      {job.reel?.scenes.map((s) => (
        <div className="scene" key={s.id}>
          <div className="t">
            {s.startSec.toFixed(1)}–{s.endSec.toFixed(1)}s · visual:{" "}
            <code>{s.visual.query}</code>
          </div>
          <div>{s.text}</div>
        </div>
      ))}

      {job.status === "done" && (
        <div className="out">
          output: <code>{job.outputUrl}</code>
        </div>
      )}
      {job.error && <div className="err">✗ {job.error}</div>}
    </section>
  );
}

function prettyStatus(s: Job["status"]): string {
  return (
    {
      queued: "Queued",
      scripting: "Writing script…",
      voicing: "Synthesizing voiceover…",
      "sourcing-visuals": "Sourcing visuals…",
      captioning: "Timing captions…",
      assembling: "Assembling video…",
      done: "Done ✓",
      failed: "Failed",
    } as Record<Job["status"], string>
  )[s];
}
