<?php
/**
 * JSON endpoint: the full reel document (reel + scenes + word timings).
 * Consumed by the in-browser player and usable for polling job status.
 *
 *   GET api.php?id=123
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/helpers.php';

$id = (int) ($_GET['id'] ?? 0);
if ($id <= 0) {
    json_out(['error' => 'missing or invalid id'], 400);
}

try {
    $reel = get_reel($id);
    if ($reel === null) {
        json_out(['error' => 'reel not found'], 404);
    }

    $scenes = array_map(static function (array $s): array {
        return [
            'id'        => (int) $s['id'],
            'index'     => (int) $s['scene_index'],
            'speaker'   => $s['speaker'] ?? 'Narrator',
            'text'      => $s['text'],
            'startSec'  => (float) $s['start_sec'],
            'endSec'    => (float) $s['end_sec'],
            'motion'    => $s['motion'],
            'transition'=> $s['transition_out'],
            'visual'    => [
                'type'     => $s['visual_type'],
                'query'    => $s['visual_query'],
                'assetUrl' => $s['visual_asset_url'],
            ],
        ];
    }, get_scenes($id));

    $words = array_map(static function (array $w): array {
        return [
            'sceneId'  => (int) $w['scene_id'],
            'ordinal'  => (int) $w['ordinal'],
            'word'     => $w['word'],
            'startSec' => (float) $w['start_sec'],
            'endSec'   => (float) $w['end_sec'],
        ];
    }, get_words($id));

    json_out([
        'reel' => [
            'id'          => (int) $reel['id'],
            'topic'       => $reel['topic'],
            'status'      => $reel['status'],
            'progress'    => (float) $reel['progress'],
            'aspect'      => $reel['aspect'],
            'fps'         => (int) $reel['fps'],
            'durationSec' => (float) $reel['duration_sec'],
            'captionStyle'=> $reel['caption_style'],
            'outputUrl'   => $reel['output_url'],
            'error'       => $reel['error'],
        ],
        'scenes' => $scenes,
        'words'  => $words,
    ]);
} catch (Throwable $e) {
    json_out(['error' => $e->getMessage()], 500);
}
