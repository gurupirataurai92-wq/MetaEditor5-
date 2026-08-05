<?php
/**
 * App + database + provider configuration.
 *
 * Database defaults match a stock XAMPP install (MySQL on 127.0.0.1:3306,
 * user "root", empty password). Change these if your MySQL is secured
 * differently.
 *
 * Realistic human / cartoon video generation is done by a THIRD-PARTY video
 * API (e.g. a text-to-video or licensed-avatar service). Bring your own key:
 * set the environment variables below (or edit the values). With no key, the
 * app falls back to the built-in browser-playable preview.
 */

declare(strict_types=1);

return [
    'db' => [
        'host'    => '127.0.0.1',
        'port'    => 3306,
        'name'    => 'reel_generator',
        'user'    => 'root',
        'pass'    => '',
        'charset' => 'utf8mb4',
    ],

    'app' => [
        'name'              => 'Reel Generator',
        'seconds_per_scene' => 4,
        'auto_install'      => true,
    ],

    // Real video generation provider (optional). A generic REST adapter:
    // the app POSTs { script, style, length, aspect } and expects JSON back
    // with either a ready `video_url` or an async `job_id`.
    'video' => [
        'endpoint' => getenv('REELGEN_VIDEO_ENDPOINT') ?: '',
        'api_key'  => getenv('REELGEN_VIDEO_API_KEY') ?: '',
        // Filled automatically: enabled only when both endpoint + key are set.
        'enabled'  => (getenv('REELGEN_VIDEO_ENDPOINT') && getenv('REELGEN_VIDEO_API_KEY')) ? true : false,
        'timeout'  => 30,
    ],

    'uploads' => [
        // Web-accessible folder so uploaded videos can be played back.
        'dir'          => dirname(__DIR__) . '/uploads',
        'max_bytes'    => 200 * 1024 * 1024, // 200 MB
        'allowed_mime' => ['video/mp4', 'video/webm', 'video/quicktime', 'video/x-m4v'],
        'allowed_ext'  => ['mp4', 'webm', 'mov', 'm4v'],
    ],
];
