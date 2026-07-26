# Reel Generator — PHP + MySQL (XAMPP)

A **faceless short-form video generator** you can run locally on **XAMPP**
(Apache + MySQL + PHP). Enter a topic; the pipeline writes a script, times a
voiceover, sources per-scene visuals, and syncs karaoke captions — then **plays
the finished 9:16 reel right in your browser**, driven from the database.

No API keys and no ffmpeg required: the provider steps are offline mocks that
produce **real, stored data** (scenes + word timings). Swap any step for a real
service (LLM / TTS / stock / ffmpeg) without changing the rest.

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
├─ index.php            home: create form + recent reels
├─ create.php           POST handler → runs the pipeline
├─ reel.php             single reel + in-browser player
├─ api.php              JSON endpoint (reel + scenes + words)
├─ config/config.php    DB credentials + app settings
├─ sql/schema.sql       database + tables (auto-installed or import by hand)
├─ includes/
│  ├─ db.php            PDO connection + self-install
│  ├─ pipeline.php      generation pipeline + data access
│  ├─ helpers.php       escaping, URLs, JSON, redirects
│  └─ layout.php        shared page chrome
└─ assets/
   ├─ style.css         UI styling
   └─ player.js         the 9:16 reel player
```

## Making it real (next steps)

- **Script** → call an LLM to return scene JSON from the topic.
- **Voiceover** → ElevenLabs / OpenAI TTS; store the audio, use returned
  (or whisper-derived) word timings — the schema already holds them.
- **Visuals** → Pexels/Pixabay search or an AI image model; save real URLs into
  `scenes.visual_asset_url`.
- **Export** → an ffmpeg step (`shell_exec`) that burns captions over the clips
  and writes an MP4 to `output/`.
