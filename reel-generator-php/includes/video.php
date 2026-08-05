<?php
/**
 * Video generation providers.
 *
 * "Realistic humans" and "cartoon" video are produced by a third-party AI
 * video service — this file is the integration layer, not the model. When a
 * provider is configured (endpoint + API key), the reel's script + options are
 * sent to it; otherwise we fall back to the built-in browser-playable preview
 * (the animated 9:16 reel), so the app always works out of the box.
 *
 * POLICY: this integration is for text-to-video and *licensed / consented*
 * synthetic-presenter services. It must not be used to fabricate videos that
 * impersonate real, identifiable individuals without their consent.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * Requests a rendered video for a reel. Returns a small result array:
 *   ['provider' => string, 'status' => 'done'|'rendering'|'preview',
 *    'video_path' => ?string, 'external_job_id' => ?string]
 *
 * @param array<string,mixed>       $reel
 * @param list<array<string,mixed>> $scenes
 */
function generate_video(array $reel, array $scenes): array
{
    $cfg = config()['video'];

    if (empty($cfg['enabled'])) {
        // No provider connected → browser-playable preview only.
        return [
            'provider'        => 'preview',
            'status'          => 'done',
            'video_path'      => null,
            'external_job_id' => null,
        ];
    }

    return rest_video_generate($reel, $scenes, $cfg);
}

/**
 * Generic REST adapter: POST the script + options as JSON, read back either a
 * ready `video_url` or an async `job_id`. Shape it to your provider as needed.
 *
 * @param array<string,mixed>       $reel
 * @param list<array<string,mixed>> $scenes
 * @param array<string,mixed>       $cfg
 * @return array<string,mixed>
 */
function rest_video_generate(array $reel, array $scenes, array $cfg): array
{
    $script = trim((string) ($reel['script'] ?? ''));
    if ($script === '') {
        $script = implode(' ', array_map(static fn ($s) => (string) $s['text'], $scenes));
    }

    $payload = [
        'script' => $script,
        'style'  => $reel['render_style'] ?? 'cartoon', // realistic | cartoon
        'length' => $reel['length_mode'] ?? 'short',    // short | long
        'aspect' => $reel['aspect'] ?? '9:16',
        'fps'    => (int) ($reel['fps'] ?? 30),
    ];

    $ch = curl_init($cfg['endpoint']);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => json_encode($payload, JSON_UNESCAPED_SLASHES),
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $cfg['api_key'],
        ],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => (int) ($cfg['timeout'] ?? 30),
    ]);

    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);

    if ($body === false || $curlErr !== '') {
        throw new RuntimeException('Video provider request failed: ' . $curlErr);
    }
    if ($status < 200 || $status >= 300) {
        throw new RuntimeException("Video provider returned HTTP {$status}: " . substr((string) $body, 0, 200));
    }

    $data = json_decode((string) $body, true);
    if (!is_array($data)) {
        throw new RuntimeException('Video provider returned a non-JSON response.');
    }

    // Ready immediately (some services return the URL synchronously).
    $videoUrl = $data['video_url'] ?? $data['url'] ?? null;
    if (is_string($videoUrl) && $videoUrl !== '') {
        return [
            'provider'        => (string) ($data['provider'] ?? 'rest'),
            'status'          => 'done',
            'video_path'      => $videoUrl,
            'external_job_id' => isset($data['job_id']) ? (string) $data['job_id'] : null,
        ];
    }

    // Async: a job id to poll later (poll_video_job()).
    $jobId = $data['job_id'] ?? $data['id'] ?? null;
    if (is_string($jobId) && $jobId !== '') {
        return [
            'provider'        => (string) ($data['provider'] ?? 'rest'),
            'status'          => 'rendering',
            'video_path'      => null,
            'external_job_id' => $jobId,
        ];
    }

    throw new RuntimeException('Video provider response had neither a video URL nor a job id.');
}
