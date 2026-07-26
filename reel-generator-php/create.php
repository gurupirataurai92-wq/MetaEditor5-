<?php
/** POST handler: create a reel, run the pipeline, redirect to its page. */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/helpers.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    redirect('index.php');
}

try {
    $reelId = create_reel($_POST);
    process_reel($reelId);
    redirect('reel.php?id=' . $reelId . '&play=1');
} catch (InvalidArgumentException $e) {
    redirect('index.php?topic=' . rawurlencode((string) ($_POST['topic'] ?? '')));
} catch (Throwable $e) {
    require_once __DIR__ . '/includes/layout.php';
    layout_header('Error');
    echo '<div class="alert"><strong>Could not generate the reel.</strong><br>' . h($e->getMessage())
        . '<br><br>Make sure XAMPP\'s MySQL module is running.</div>';
    echo '<p><a class="btn-link" href="' . h(url('index.php')) . '">← Back</a></p>';
    layout_footer();
}
