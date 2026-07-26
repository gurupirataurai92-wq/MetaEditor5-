<?php
/**
 * The reel generation pipeline (PHP port).
 *
 * plan script → synthesize voice timings → source visuals → time captions →
 * "assemble". Like the TypeScript skeleton, the providers here are offline
 * mocks: they produce real, stored data (scenes + word timings) that the
 * in-browser player turns into a watchable 9:16 reel — no external APIs or
 * ffmpeg required. Swap any step for a real service without touching the rest.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/video.php';

/**
 * Creates a queued reel row from user input and returns its id.
 *
 * @param array<string,mixed> $input
 */
function create_reel(array $input): int
{
    $topic = trim((string) ($input['topic'] ?? ''));
    if ($topic === '') {
        throw new InvalidArgumentException('A topic is required.');
    }

    $script       = trim((string) ($input['script'] ?? ''));
    $captionStyle = trim((string) ($input['caption_style'] ?? 'karaoke-bold-yellow'));
    $voiceId      = trim((string) ($input['voice_id'] ?? 'narrator-warm'));
    $musicTrack   = trim((string) ($input['music_track_id'] ?? 'lofi-01'));

    // Look & length options (validated against the allowed enum values).
    $renderStyle = in_array($input['render_style'] ?? '', ['realistic', 'cartoon'], true)
        ? (string) $input['render_style'] : 'cartoon';
    $lengthMode = in_array($input['length_mode'] ?? '', ['short', 'long'], true)
        ? (string) $input['length_mode'] : 'short';

    $pdo = db();
    $stmt = $pdo->prepare(
        'INSERT INTO reels
            (topic, script, voice_id, caption_style, music_track_id,
             render_style, length_mode, source, status, progress)
         VALUES
            (:topic, :script, :voice_id, :caption_style, :music_track_id,
             :render_style, :length_mode, "generated", :status, 0)'
    );
    $stmt->execute([
        ':topic'          => mb_substr($topic, 0, 255),
        ':script'         => $script !== '' ? $script : null,
        ':voice_id'       => $voiceId !== '' ? $voiceId : 'narrator-warm',
        ':caption_style'  => $captionStyle !== '' ? $captionStyle : 'karaoke-bold-yellow',
        ':music_track_id' => $musicTrack !== '' ? $musicTrack : 'lofi-01',
        ':render_style'   => $renderStyle,
        ':length_mode'    => $lengthMode,
        ':status'         => 'queued',
    ]);

    return (int) $pdo->lastInsertId();
}

/**
 * Runs the full pipeline for a reel, persisting each stage. Fast enough to run
 * synchronously; a production build would hand this to a queue/worker.
 */
function process_reel(int $reelId): void
{
    $pdo  = db();
    $reel = get_reel($reelId);
    if ($reel === null) {
        throw new RuntimeException("Reel #{$reelId} not found.");
    }

    try {
        // 1. Script → timed scenes (length_mode controls how many beats).
        set_status($reelId, 'scripting', 0.10);
        $scenes = plan_scenes(
            $reel['topic'],
            $reel['script'] ?? '',
            $reel['caption_style'],
            $reel['length_mode'] ?? 'short'
        );

        // Clear any prior run, then persist scenes.
        $pdo->prepare('DELETE FROM scenes WHERE reel_id = :id')->execute([':id' => $reelId]);
        $sceneIds = [];
        $insScene = $pdo->prepare(
            'INSERT INTO scenes
               (reel_id, scene_index, text, start_sec, end_sec, visual_type,
                visual_query, motion, caption_style, transition_out)
             VALUES
               (:reel_id, :idx, :text, :start, :end, :vtype,
                :vquery, :motion, :cstyle, :trans)'
        );
        foreach ($scenes as $i => $s) {
            $insScene->execute([
                ':reel_id' => $reelId,
                ':idx'     => $i,
                ':text'    => $s['text'],
                ':start'   => $s['start_sec'],
                ':end'     => $s['end_sec'],
                ':vtype'   => $s['visual_type'],
                ':vquery'  => $s['visual_query'],
                ':motion'  => $s['motion'],
                ':cstyle'  => $s['caption_style'],
                ':trans'   => $s['transition_out'],
            ]);
            $sceneIds[$i] = (int) $pdo->lastInsertId();
        }

        // 2. Voiceover → per-word timings.
        set_status($reelId, 'voicing', 0.40);
        $pdo->prepare('DELETE FROM caption_words WHERE reel_id = :id')->execute([':id' => $reelId]);
        $insWord = $pdo->prepare(
            'INSERT INTO caption_words (reel_id, scene_id, ordinal, word, start_sec, end_sec)
             VALUES (:reel_id, :scene_id, :ordinal, :word, :start, :end)'
        );
        $ordinal = 0;
        foreach ($scenes as $i => $s) {
            foreach (synth_word_timings($s) as $w) {
                $insWord->execute([
                    ':reel_id'  => $reelId,
                    ':scene_id' => $sceneIds[$i],
                    ':ordinal'  => $ordinal++,
                    ':word'     => mb_substr($w['word'], 0, 64),
                    ':start'    => $w['start_sec'],
                    ':end'      => $w['end_sec'],
                ]);
            }
        }

        // 3. Source visuals (placeholder asset per scene, cached by query).
        set_status($reelId, 'sourcing_visuals', 0.65);
        $updAsset = $pdo->prepare(
            'UPDATE scenes SET visual_asset_url = :url WHERE id = :id'
        );
        foreach ($scenes as $i => $s) {
            $updAsset->execute([
                ':url' => 'placeholder://stock/' . rawurlencode($s['visual_query']),
                ':id'  => $sceneIds[$i],
            ]);
        }

        // 4. Captions are derived from word timings at play time — nothing to fetch.
        set_status($reelId, 'captioning', 0.80);

        // 5. Render: hand the script + look/length options to the video provider.
        //    With a provider connected this produces a real MP4 (realistic or
        //    cartoon); with none, it returns the browser-playable preview.
        set_status($reelId, 'rendering', 0.92);
        $duration = empty($scenes) ? 0.0 : (float) end($scenes)['end_sec'];
        $reel['script'] = $reel['script'] ?? '';

        $result = generate_video($reel, $scenes);

        $output = $result['video_path'] ?? ('reel.php?id=' . $reelId . '&play=1');
        $finalStatus = $result['status'] === 'rendering' ? 'rendering' : 'done';

        $upd = $pdo->prepare(
            'UPDATE reels
                SET status = :status, progress = :progress, duration_sec = :dur,
                    provider = :provider, video_path = :video_path,
                    external_job_id = :job_id, output_url = :out, error = NULL
              WHERE id = :id'
        );
        $upd->execute([
            ':status'     => $finalStatus,
            ':progress'   => $finalStatus === 'done' ? 1 : 0.92,
            ':dur'        => $duration,
            ':provider'   => $result['provider'] ?? null,
            ':video_path' => $result['video_path'] ?? null,
            ':job_id'     => $result['external_job_id'] ?? null,
            ':out'        => $output,
            ':id'         => $reelId,
        ]);
    } catch (Throwable $e) {
        $upd = $pdo->prepare('UPDATE reels SET status = "failed", error = :err WHERE id = :id');
        $upd->execute([':err' => mb_substr($e->getMessage(), 0, 255), ':id' => $reelId]);
    }
}

/** Updates a reel's status + coarse progress. */
function set_status(int $reelId, string $status, float $progress): void
{
    $stmt = db()->prepare('UPDATE reels SET status = :s, progress = :p WHERE id = :id');
    $stmt->execute([':s' => $status, ':p' => $progress, ':id' => $reelId]);
}

/**
 * Splits a topic or supplied script into ~sentence-sized, evenly timed scenes.
 * `$lengthMode` ('short'|'long') controls the auto-written script length.
 *
 * @return list<array<string,mixed>>
 */
function plan_scenes(string $topic, string $script, string $captionStyle, string $lengthMode = 'short'): array
{
    $perScene = (int) (config()['app']['seconds_per_scene'] ?? 4);

    $raw = trim($script);
    if ($raw === '') {
        $short = [
            "Here's something wild about {$topic}.",
            "Most people never stop to think about {$topic}.",
            "But once you see it, you can't unsee it.",
            "Follow for more on {$topic}.",
        ];
        $longExtra = [
            "Let's start with what everyone gets wrong about {$topic}.",
            "The real story goes deeper than that.",
            "Experts have studied {$topic} for years.",
            "And the findings are genuinely surprising.",
            "Here's the part nobody talks about.",
            "It changes how you look at {$topic} completely.",
            "So next time {$topic} comes up, you'll know the truth.",
            "Save this so you don't forget it.",
        ];
        $raw = $lengthMode === 'long'
            ? implode(' ', array_merge($short, $longExtra))
            : implode(' ', $short);
    }

    $sentences = preg_split('/(?<=[.!?])\s+/', $raw, -1, PREG_SPLIT_NO_EMPTY) ?: [$raw];
    $count = count($sentences);

    $scenes = [];
    foreach ($sentences as $i => $text) {
        $text = trim($text);
        if ($text === '') {
            continue;
        }
        $scenes[] = [
            'text'           => $text,
            'start_sec'      => $i * $perScene,
            'end_sec'        => ($i + 1) * $perScene,
            'visual_type'    => 'stock',
            'visual_query'   => scene_keyword($text, $topic),
            'motion'         => $i % 2 === 0 ? 'zoom-in' : 'zoom-out',
            'caption_style'  => $captionStyle,
            'transition_out' => $i < $count - 1 ? 'whip-pan' : 'fade',
        ];
    }

    return $scenes;
}

/** Derives per-word timings spread evenly across a scene's span. */
function synth_word_timings(array $scene): array
{
    $tokens = preg_split('/\s+/', trim((string) $scene['text']), -1, PREG_SPLIT_NO_EMPTY) ?: [];
    $span = max(0.001, (float) $scene['end_sec'] - (float) $scene['start_sec']);
    $per  = $span / max(1, count($tokens));

    $words = [];
    foreach ($tokens as $i => $word) {
        $words[] = [
            'word'      => $word,
            'start_sec' => round((float) $scene['start_sec'] + $i * $per, 3),
            'end_sec'   => round((float) $scene['start_sec'] + ($i + 1) * $per, 3),
        ];
    }
    return $words;
}

/** Picks a representative keyword from a sentence for the visual search query. */
function scene_keyword(string $text, string $topic): string
{
    static $stop = [
        'here' => 1, 'heres' => 1, 'something' => 1, 'about' => 1, 'most' => 1,
        'people' => 1, 'never' => 1, 'stop' => 1, 'think' => 1, 'once' => 1,
        'you' => 1, 'youre' => 1, 'see' => 1, 'cant' => 1, 'unsee' => 1,
        'follow' => 1, 'more' => 1, 'the' => 1, 'and' => 1, 'but' => 1,
        'for' => 1, 'with' => 1, 'this' => 1, 'that' => 1, 'wild' => 1,
    ];

    $clean = preg_replace('/[^a-z\s]/', '', strtolower($text)) ?? '';
    foreach (preg_split('/\s+/', $clean, -1, PREG_SPLIT_NO_EMPTY) ?: [] as $w) {
        if (strlen($w) > 3 && !isset($stop[$w])) {
            return $w;
        }
    }
    return $topic;
}

/* ------------------------------------------------------------------ */
/* Read helpers                                                        */
/* ------------------------------------------------------------------ */

/** @return array<string,mixed>|null */
function get_reel(int $id): ?array
{
    $stmt = db()->prepare('SELECT * FROM reels WHERE id = :id');
    $stmt->execute([':id' => $id]);
    $row = $stmt->fetch();
    return $row === false ? null : $row;
}

/** @return list<array<string,mixed>> */
function list_reels(int $limit = 20): array
{
    $limit = max(1, min(100, $limit));
    $stmt = db()->query(
        'SELECT id, topic, status, progress, duration_sec, created_at
           FROM reels ORDER BY created_at DESC, id DESC LIMIT ' . $limit
    );
    return $stmt->fetchAll();
}

/** @return list<array<string,mixed>> */
function get_scenes(int $reelId): array
{
    $stmt = db()->prepare('SELECT * FROM scenes WHERE reel_id = :id ORDER BY scene_index ASC');
    $stmt->execute([':id' => $reelId]);
    return $stmt->fetchAll();
}

/** @return list<array<string,mixed>> */
function get_words(int $reelId): array
{
    $stmt = db()->prepare(
        'SELECT scene_id, ordinal, word, start_sec, end_sec
           FROM caption_words WHERE reel_id = :id ORDER BY ordinal ASC'
    );
    $stmt->execute([':id' => $reelId]);
    return $stmt->fetchAll();
}

/* ------------------------------------------------------------------ */
/* Uploads                                                             */
/* ------------------------------------------------------------------ */

/**
 * Validates and stores an uploaded video ($_FILES entry), recording it in the
 * uploads table. Returns the new upload id.
 *
 * @param array<string,mixed> $file A single entry from $_FILES.
 */
function save_upload(array $file): int
{
    $cfg = config()['uploads'];

    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Upload failed (error code ' . ($file['error'] ?? '?') . ').');
    }
    $size = (int) ($file['size'] ?? 0);
    if ($size <= 0 || $size > (int) $cfg['max_bytes']) {
        throw new RuntimeException('File is empty or exceeds the ' . round($cfg['max_bytes'] / 1048576) . ' MB limit.');
    }

    $tmp  = (string) ($file['tmp_name'] ?? '');
    $orig = (string) ($file['name'] ?? 'upload');
    $ext  = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
    if (!in_array($ext, $cfg['allowed_ext'], true)) {
        throw new RuntimeException('Unsupported file type. Allowed: ' . implode(', ', $cfg['allowed_ext']) . '.');
    }

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime  = is_uploaded_file($tmp) ? ((string) $finfo->file($tmp)) : ((string) ($file['type'] ?? ''));
    if (!in_array($mime, $cfg['allowed_mime'], true)) {
        throw new RuntimeException('Unsupported video format (' . h_safe($mime) . ').');
    }

    $dir = (string) $cfg['dir'];
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('Cannot create the uploads directory.');
    }

    $stored   = bin2hex(random_bytes(8)) . '.' . $ext;
    $destPath = rtrim($dir, '/\\') . DIRECTORY_SEPARATOR . $stored;

    $moved = is_uploaded_file($tmp) ? move_uploaded_file($tmp, $destPath) : rename($tmp, $destPath);
    if (!$moved) {
        throw new RuntimeException('Could not save the uploaded file.');
    }

    $stmt = db()->prepare(
        'INSERT INTO uploads (original_name, stored_path, mime, size_bytes)
         VALUES (:name, :path, :mime, :size)'
    );
    $stmt->execute([
        ':name' => mb_substr($orig, 0, 255),
        ':path' => 'uploads/' . $stored, // web-relative, playable
        ':mime' => $mime,
        ':size' => $size,
    ]);

    return (int) db()->lastInsertId();
}

/** @return list<array<string,mixed>> */
function list_uploads(int $limit = 12): array
{
    $limit = max(1, min(50, $limit));
    $stmt = db()->query(
        'SELECT id, original_name, stored_path, mime, size_bytes, created_at
           FROM uploads ORDER BY created_at DESC, id DESC LIMIT ' . $limit
    );
    return $stmt->fetchAll();
}

/** Minimal escape usable before helpers.php is loaded. */
function h_safe(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
