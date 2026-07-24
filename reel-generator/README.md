# Reel Generator

A **faceless AI reel generator** — turn a topic (or script) into a finished
9:16 short-form video: LLM writes the script, TTS narrates it, stock/AI
footage fills each scene, captions are word-synced, and FFmpeg assembles the
MP4.

> **Status: skeleton.** The full pipeline runs end to end today using **mock
> providers** (no API keys, no ffmpeg). Real providers slot in behind the same
> interfaces — see [Swapping in real providers](#swapping-in-real-providers).
> See [`docs/reel-generator-brainstorm.md`](../docs/reel-generator-brainstorm.md)
> for the product thinking behind it.

## Monorepo layout

```
reel-generator/
├─ packages/
│  └─ core/            @reel/core — types, pipeline, providers, queue
│     └─ src/
│        ├─ types.ts           Scene / Reel / Job data model (the contract)
│        ├─ pipeline.ts        plan → voice → visuals → captions → assemble
│        ├─ queue.ts           JobStore + processJob (in-memory for now)
│        ├─ poc.ts             offline end-to-end demo (no deps)
│        └─ providers/         ScriptProvider, VoiceProvider, VisualProvider,
│                              AssemblyProvider — interfaces + mocks
└─ apps/
   ├─ web/             @reel/web — Next.js UI + REST API (/api/reels)
   └─ worker/          @reel/worker — render worker (deployment-shape demo)
```

The **scene JSON** (`Reel`) is the engine-agnostic contract between the
planning side (LLM/TTS/stock) and the rendering side (FFmpeg/Remotion).

## Quick start

```bash
pnpm install

# 1. Prove the pipeline offline (no keys, no ffmpeg):
pnpm poc                     # or: pnpm --filter @reel/core poc "your topic"

# 2. Run the web app (form + live job status):
pnpm dev:web                 # http://localhost:3000

# 3. See the worker deployment shape:
pnpm dev:worker
```

## How it flows

```
POST /api/reels {topic}
     │  store.create(job)  → status: queued
     ▼
processJob → generateReel():
   scripting        ScriptProvider.plan()      topic → timed scenes
   voicing          VoiceProvider.synthesize() → audio + word timings
   sourcing-visuals VisualProvider.source()    → asset per scene
   captioning       (derived from word timings)
   assembling       AssemblyProvider.render()  → MP4
     ▼
GET /api/reels/:id  ← UI polls until done/failed
```

## Swapping in real providers

Every capability is behind an interface in `packages/core/src/providers`.
Replace the mock with a real implementation and compose it in
`mockProviders()` (or inject per-environment):

| Interface | Mock | Real (suggested) |
|---|---|---|
| `ScriptProvider` | canned template | Claude / an LLM returning scene JSON |
| `VoiceProvider` | derived timings | ElevenLabs / OpenAI TTS (+ whisper for timings) |
| `VisualProvider` | placeholder URLs | Pexels/Pixabay stock, or SDXL/Flux images |
| `AssemblyProvider` | validate + fake URL | `FFmpegAssemblyProvider` (filtergraph) |

For production, also swap `InMemoryJobStore` for Postgres + Redis/BullMQ and
run `apps/worker` as separate processes so the web tier only enqueues.

## Roadmap

- **Phase 0 (done):** offline pipeline end to end (`pnpm poc`).
- **Phase 1 (this skeleton):** web form → API → job status → output URL.
- **Phase 2:** real providers, FFmpeg assembly, voice/style/music pickers,
  editable script + scene timeline preview.
- **Phase 3:** accounts, credits/billing, templates, auto-post/scheduling.
