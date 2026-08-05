<?php
/** Small view/util helpers shared across pages. */

declare(strict_types=1);

/** HTML-escape for safe output. */
function h(?string $s): string
{
    return htmlspecialchars($s ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Base URL path of the app (e.g. /reel-generator-php), so links work in any subfolder. */
function base_path(): string
{
    $dir = str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/'));
    return rtrim($dir, '/');
}

/** Build an app-relative URL. */
function url(string $path): string
{
    return base_path() . '/' . ltrim($path, '/');
}

/** Redirect and stop. */
function redirect(string $path): never
{
    header('Location: ' . url($path));
    exit;
}

/** Send a JSON response and stop. */
function json_out(mixed $data, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

/** Human label for a job status enum value. */
function status_label(string $status): string
{
    return [
        'queued'           => 'Queued',
        'scripting'        => 'Writing script',
        'voicing'          => 'Synthesizing voiceover',
        'sourcing_visuals' => 'Sourcing visuals',
        'captioning'       => 'Timing captions',
        'assembling'       => 'Assembling video',
        'rendering'        => 'Rendering video',
        'done'             => 'Done',
        'failed'           => 'Failed',
    ][$status] ?? ucfirst($status);
}
