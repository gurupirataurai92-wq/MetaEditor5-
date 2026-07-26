# Reel Generator — PHP + MySQL (XAMPP)

A **script-to-video generator** you can run locally on **XAMPP** (Apache +
MySQL + PHP). Enter a topic or full script, choose **realistic** or **cartoon**
and **short** or **long**, and the pipeline writes/segments the script, times a
voiceover, and produces a video. You can also **upload your own videos** and
play them back. Everything is stored in a MySQL database.

## How the video actually gets made (important)

Photorealistic video of humans is produced by a **third-party AI video API**
(text-to-video or a licensed synthetic-presenter service). This app is the
**integration + workflow layer**, not the model:

- **With a provider connected** (endpoint + API key in `config/config.php`),
  the script + options are sent to it and the returned MP4 is stored and played.
- **With no provider** (default), the app runs in **preview mode**: it renders
  the reel as an in-browser 9:16 animation from the database (scenes + word
  timings) so everything works out of the box — no keys, no ffmpeg.

> **Policy:** the provider integration is for text-to-video and *licensed /
> consented* synthetic-presenter services. It must not be used to fabricate
> videos impersonating real, identifiable individuals without their consent.

## Requirements

- **XAMPP** (or any Apache + PHP 8.1+ + MySQL/MariaDB stack)
- PHP extension **pdo_mysql** (bundled with XAMPP by default)

## Install & launch (XAMPP)

1. **Copy the folder** into XAMPP's web root:
   - Windows: `C:\xampp\htdocs\reel-generator-php`
   - macOS: `/Applications/XAMPP/htdocs/reel-generator-php`
   - Linux: `/opt/lampp/htdocs/reel-generator-php`
2. Open the **XAMPP Control Panel** and **Start** both **Apache** and **MySQL**.
3. Visit **<http://localhost/reel-generator-php/>**.

That's it. On first load the app **auto-creates** the `reel_generator` database
and its tables, then you can generate a reel immediately.

### Prefer to set up the database by hand?

Set `auto_install => false` in `config/config.php`, then either:

- **phpMyAdmin** (<http://localhost/phpmyadmin>) → *Import* → choose
  `sql/schema.sql`, **or**
- **CLI**: `mysql -u root < sql/schema.sql`

### Different MySQL credentials?

Edit `config/config.php`. Defaults match a stock XAMPP install
(`127.0.0.1:3306`, user `root`, empty password).

## How it works

```
index.php   ─ create form + list of recent reels
   │ POST
create.php  ─ create_reel() → process_reel() → redirect to the player
   │
reel.php    ─ scene breakdown + 9:16 in-browser player
api.php     ─ JSON: { reel, scenes, words }  (player + status polling)
```

Pipeline stages (in `includes/pipeline.php`), each persisted to MySQL:

| Stage | What it does | Table written |
|---|---|---|
| Script | topic → timed scenes | `scenes` |
| Voiceover | scenes → per-word timings | `caption_words` |
| Visuals | per-scene placeholder asset | `scenes.visual_asset_url` |
| Captions | derived from word timings at play time | — |
| Assemble | finalize duration + playable output | `reels` |

## Database

Three tables (see `sql/schema.sql`):

- **`reels`** — one row per generation job (topic, status, progress, duration…)
- **`scenes`** — timed scenes for a reel (text, timing, visual query, motion)
- **`caption_words`** — per-word timings that drive the karaoke captions

All foreign keys cascade on delete, so removing a reel cleans up its scenes and
words.

## File layout

```
reel-generator-php/
├─ index.php            home: create form (look/length options) + uploads + reels
├─ create.php           POST handler → runs the pipeline
├─ upload.php           POST handler → validates & stores an uploaded video
├─ reel.php             single reel: rendered <video> or in-browser preview
├─ api.php              JSON endpoint (reel + scenes + words)
├─ config/config.php    DB credentials, video-provider key, upload limits
├─ sql/schema.sql       database + tables (auto-installed/upgraded or import by hand)
├─ includes/
│  ├─ db.php            PDO connection + self-install + schema upgrades
│  ├─ pipeline.php      generation pipeline, uploads, data access
│  ├─ video.php         video-provider layer (REST adapter + preview fallback)
│  ├─ helpers.php       escaping, URLs, JSON, redirects
│  └─ layout.php        shared page chrome
├─ uploads/             stored uploads (script execution disabled via .htaccess)
└─ assets/
   ├─ style.css         UI styling
   └─ player.js         the 9:16 preview player
```

## Connecting a real video provider

Set two environment variables (or edit `config/config.php`), then restart
Apache:

```
REELGEN_VIDEO_ENDPOINT = https://your-video-api.example/v1/generate
REELGEN_VIDEO_API_KEY  = sk-...
```

`includes/video.php` POSTs `{ script, style, length, aspect, fps }` and expects
JSON back with either a ready `video_url` or an async `job_id`. Adapt the
payload/response mapping to your chosen service (e.g. a text-to-video or
licensed-avatar API). Rendered files are stored on the reel and played inline.

## Making it real (next steps)

- **Script** → call an LLM to return scene JSON from the topic.
- **Voiceover** → ElevenLabs / OpenAI TTS; store the audio, use returned
  (or whisper-derived) word timings — the schema already holds them.
- **Visuals** → Pexels/Pixabay search or an AI image model; save real URLs into
  `scenes.visual_asset_url`.
- **Export** → an ffmpeg step (`shell_exec`) that burns captions over the clips
  and writes an MP4 to `output/`.
