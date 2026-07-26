<?php
/** Single reel: scene breakdown + in-browser 9:16 player. */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/layout.php';

$id = (int) ($_GET['id'] ?? 0);
if ($id <= 0) {
    redirect('index.php');
}

$reel = get_reel($id);
if ($reel === null) {
    layout_header('Not found');
    echo '<div class="alert">Reel #' . $id . ' was not found.</div>';
    echo '<p><a class="btn-link" href="' . h(url('index.php')) . '">← Back</a></p>';
    layout_footer();
    exit;
}

$scenes = get_scenes($id);

layout_header('Reel #' . $id);
?>

<p><a class="btn-link" href="<?= h(url('index.php')) ?>">← All reels</a></p>

<section class="reel-head">
    <div>
        <span class="eyebrow">Reel #<?= (int) $reel['id'] ?></span>
        <h1 class="reel-title"><?= h($reel['topic']) ?></h1>
        <div class="reel-tags">
            <span class="status status-<?= h($reel['status']) ?>"><?= h(status_label($reel['status'])) ?></span>
            <span class="tag"><?= h(ucfirst((string) ($reel['render_style'] ?? 'cartoon'))) ?></span>
            <span class="tag"><?= h(ucfirst((string) ($reel['length_mode'] ?? 'short'))) ?></span>
            <span class="tag"><?= h($reel['aspect']) ?> · <?= (int) $reel['fps'] ?>fps</span>
            <span class="tag"><?= number_format((float) $reel['duration_sec'], 1) ?>s</span>
            <span class="tag"><?= count($scenes) ?> scenes</span>
            <?php if (!empty($reel['provider']) && $reel['provider'] !== 'preview'): ?>
                <span class="tag">via <?= h($reel['provider']) ?></span>
            <?php endif; ?>
        </div>
    </div>
</section>

<?php if ($reel['status'] === 'failed'): ?>
    <div class="alert"><strong>Generation failed.</strong> <?= h($reel['error'] ?? 'Unknown error') ?></div>
<?php endif; ?>

<?php
    $videoPath = (string) ($reel['video_path'] ?? '');
    $hasFile   = $videoPath !== '' && !str_starts_with($videoPath, 'reel.php');
    $videoSrc  = $hasFile
        ? (preg_match('#^https?://#i', $videoPath) ? $videoPath : url($videoPath))
        : null;
?>
<div class="reel-layout">
    <div class="player-col">
        <?php if ($hasFile): ?>
            <div class="phone">
                <div class="screen">
                    <div class="notch"></div>
                    <video class="rendered" controls autoplay playsinline
                           src="<?= h($videoSrc) ?>"></video>
                </div>
            </div>
            <p class="muted small">Rendered <?= h((string) ($reel['render_style'] ?? '')) ?> video via
                <code><?= h((string) ($reel['provider'] ?? 'provider')) ?></code>.</p>
        <?php else: ?>
            <div class="phone" id="player"
                 data-reel-id="<?= (int) $id ?>"
                 data-api="<?= h(url('api.php')) ?>">
                <div class="screen">
                    <div class="notch"></div>
                    <div class="scene-bg" id="sceneBg"></div>
                    <div class="screen-top">
                        <span class="stage-pill"><span class="live"></span> <span id="stageText">ready</span></span>
                        <span class="ratio-tag" id="ratioText">9:16</span>
                    </div>
                    <div class="caption-zone">
                        <div class="caption" id="caption"></div>
                    </div>
                    <div class="progress"><i id="progressBar"></i></div>
                </div>
            </div>
            <div class="player-controls">
                <button id="playBtn" type="button">▶ Play</button>
                <span class="time"><span id="curTime">0.0</span>s / <span id="totTime"><?= number_format((float) $reel['duration_sec'], 1) ?></span>s</span>
            </div>
            <p class="muted small">
                In-browser preview from the database (scenes + word timings).
                Connect a video provider to render a real <?= h((string) ($reel['render_style'] ?? '')) ?> MP4.
            </p>
        <?php endif; ?>
    </div>

    <div class="scenes-col">
        <h2>Scene breakdown</h2>
        <?php if (empty($scenes)): ?>
            <p class="muted">No scenes were generated.</p>
        <?php else: ?>
            <ol class="scene-list">
                <?php foreach ($scenes as $s): ?>
                    <li class="scene-item">
                        <div class="scene-time">
                            <?= number_format((float) $s['start_sec'], 1) ?>–<?= number_format((float) $s['end_sec'], 1) ?>s
                        </div>
                        <div class="scene-body">
                            <div class="scene-text"><?= h($s['text']) ?></div>
                            <div class="scene-visual">visual: <code><?= h($s['visual_query']) ?></code> · <?= h($s['motion']) ?></div>
                        </div>
                    </li>
                <?php endforeach; ?>
            </ol>
        <?php endif; ?>
    </div>
</div>

<script src="<?= h(url('assets/player.js')) ?>" defer></script>
<?php if (isset($_GET['play'])): ?>
<script>window.__REEL_AUTOPLAY = true;</script>
<?php endif; ?>

<?php
layout_footer();
