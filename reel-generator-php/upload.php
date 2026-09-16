<?php
/** Handles a video upload, then returns to the home page. */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/helpers.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    redirect('index.php');
}

try {
    if (empty($_FILES['video']) || ($_FILES['video']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
        redirect('index.php?msg=' . rawurlencode('Choose a video file to upload.'));
    }
    save_upload($_FILES['video']);
    redirect('index.php?msg=' . rawurlencode('Video uploaded.') . '#uploads');
} catch (Throwable $e) {
    redirect('index.php?msg=' . rawurlencode('Upload failed: ' . $e->getMessage()) . '#uploads');
}
