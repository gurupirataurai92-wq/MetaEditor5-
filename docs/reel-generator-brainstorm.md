# Reel Generator Platform — Brainstorm

> Status: ideation / pre-build. This doc captures the vision, options, and a
> phased plan for an automated short-form video ("reel") generator.

## 1. What we're building

A platform that turns an **idea, script, or URL** into a finished **vertical
short-form video** (9:16) ready for Instagram Reels, TikTok, and YouTube
Shorts — with as little manual editing as possible.

The core loop:

```
Topic / script / link
        │
        ▼
1. Script writing (LLM)        ─► hook + body + CTA, sized to ~30–60s
        │
        ▼
2. Voiceover (TTS)             ─► narration audio + word timestamps
        │
        ▼
3. Visuals                     ─► stock clips / AI images / b-roll per scene
        │
        ▼
4. Captions                    ─► word-synced animated subtitles
        │
        ▼
5. Assembly (render)           ─► music, transitions, mux to MP4 9:16
        │
        ▼
6. Preview + export / schedule ─► download or auto-post
```

## 2. Product variants (pick a lane)

| Variant | What the user brings | What we generate | Best for |
|---|---|---|---|
| **A. Faceless AI reels** | A topic or script | Everything (VO, visuals, captions, music) | Content-at-scale, "story/fact" pages |
| **B. Clip repurposer** | A long video (podcast/YouTube) | Auto-detect highlights → cut into shorts + captions | Creators repurposing long-form |
| **C. Template editor** | Their own footage/photos | Template-driven assembly + captions | Hands-on creators, brands |

Recommendation: **start with Variant A (faceless AI reels)** — it's the highest
"wow per line of code," needs no user-uploaded media, and the pipeline pieces
(B and C) are subsets of it.

## 3. Architecture (Variant A)

```
┌────────────┐    ┌──────────────┐    ┌─────────────────────┐
│  Web app   │───▶│   API server │───▶│  Job queue (async)  │
│ (Next.js)  │    │  (REST/RPC)  │    │  render workers     │
└────────────┘    └──────┬───────┘    └──────────┬──────────┘
                         │                        │
                  ┌──────▼───────┐        ┌───────▼────────┐
                  │  Postgres    │        │  Object store  │
                  │ users/jobs   │        │  (S3/R2) media │
                  └──────────────┘        └────────────────┘
```

**Why a job queue:** rendering is slow (seconds–minutes) and CPU/GPU heavy.
The API enqueues a job and returns immediately; a worker runs the pipeline and
streams status back (polling or websockets). This keeps the web tier responsive
and lets us scale render workers independently.

## 4. The render pipeline (the hard part)

| Stage | Job | Candidate tools |
|---|---|---|
| Script | topic → structured script (scenes) | LLM (Claude) |
| Voiceover | script → audio + word timings | ElevenLabs / OpenAI TTS / Coqui (OSS) |
| Visual sourcing | per-scene query → clip/image | Pexels/Pixabay API (free), or AI image (SDXL/Flux) |
| Captions | word timings → styled ASS/SRT | whisper for timing if TTS lacks it |
| Assembly | layer video+audio+captions+music | **FFmpeg** (core), or Remotion (React-based) |
| Thumbnail | grab/compose cover frame | FFmpeg |

**Two assembly engines to weigh:**
- **FFmpeg + filtergraph** — battle-tested, fast, headless, cheap. Harder to
  express fancy motion/animation.
- **Remotion** (render React components to video) — gorgeous animated captions
  and transitions, but heavier (spins Chromium per render).

Recommendation: **FFmpeg for v1** (predictable, cheap, scriptable), keep the
scene model engine-agnostic so we can swap in Remotion for premium templates.

## 5. Scene data model (engine-agnostic)

```jsonc
{
  "reel": {
    "aspect": "9:16", "fps": 30, "durationSec": 42,
    "music": { "trackId": "lofi-01", "gainDb": -18 },
    "scenes": [
      {
        "id": "s1",
        "text": "Did you know octopuses have three hearts?",
        "startSec": 0, "endSec": 4.2,
        "visual": { "type": "stock", "query": "octopus underwater", "assetUrl": "..." },
        "captionStyle": "karaoke-bold-yellow",
        "transitionOut": "whip-pan"
      }
    ],
    "voiceover": { "voiceId": "narrator-warm", "audioUrl": "...", "words": [ /* timings */ ] }
  }
}
```

This JSON is the contract between "planning" (LLM + APIs) and "rendering"
(FFmpeg/Remotion). Everything else is a transform to/from it.

## 6. Tech stack proposal

- **Frontend:** Next.js (App Router) + Tailwind — SPA feel, easy deploy.
- **Backend:** Node/TypeScript API (shared types with frontend) **or** Python
  (richer media/ML ecosystem). *Leaning TS for one language end-to-end.*
- **Worker:** separate container running FFmpeg; pulls jobs from Redis/BullMQ.
- **DB:** Postgres (users, projects, jobs, assets).
- **Storage:** S3-compatible (AWS S3 / Cloudflare R2) for rendered MP4s + assets.
- **Auth:** Clerk/Auth.js. **Billing:** Stripe (credits per render).

## 7. Cost & rate-limit realities (design around these)

- TTS and AI-image APIs cost per call — **cache aggressively**, dedupe scenes,
  and meter usage with a **credit system**.
- Stock-footage APIs (Pexels/Pixabay) are free but rate-limited — cache asset
  URLs and downloaded files.
- Rendering is the CPU cost — a **queue + concurrency cap** prevents a stampede
  from melting workers.

## 8. Phased roadmap

**Phase 0 — Proof of concept (CLI, no UI)**
Topic → script (LLM) → TTS → 3 stock clips → burned-in captions → MP4.
One command, one hardcoded style. Proves the pipeline end to end.

**Phase 1 — Minimum web product**
Wrap PoC in an API + queue; simple web form (topic in, video out); job status;
download button. One caption style, one music track.

**Phase 2 — Creator controls**
Voice picker, caption styles, music library, per-scene visual swap, editable
script, live preview of the scene timeline.

**Phase 3 — Scale & growth**
Accounts, credits/billing, templates, brand kits, auto-post/schedule to
socials, Variant B (long-video repurposing).

## 9. Open questions (need product direction)

1. **Variant** — faceless AI reels (A), long-video repurposing (B), or template
   editor (C)?
2. **Language** — TypeScript end-to-end, or Python backend for ML flexibility?
3. **First deliverable** — a runnable CLI proof-of-concept, or scaffold the full
   web app skeleton first?
4. **Assembly engine** — FFmpeg (cheap/fast) vs Remotion (prettier motion)?
5. **Hosting/network** — does this environment allow the outbound API calls
   (LLM/TTS/stock) the pipeline needs, or do we stub them for now?

## 10. Immediate next step (proposed)

Build **Phase 0** as a self-contained CLI in `reel-generator/`: a scripted
pipeline with pluggable providers (LLM/TTS/stock all behind interfaces, with
mock implementations so it runs offline). That gives us a real artifact to
iterate on without committing to paid APIs yet.
