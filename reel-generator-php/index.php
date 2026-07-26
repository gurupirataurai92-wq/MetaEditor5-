<?php
/** Home: create form (with look/length options), uploads, and recent reels. */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/layout.php';

$error   = null;
$reels   = [];
$uploads = [];
try {
    $reels   = list_reels(20);
    $uploads = list_uploads(12);
} catch (Throwable $e) {
    $error = $e->getMessage();
}

$providerOn = (bool) (config()['video']['enabled'] ?? false);
$flash = isset($_GET['msg']) ? (string) $_GET['msg'] : null;

layout_header('Create a reel');
?>

<section class="hero">
    <span class="eyebrow">Script-to-video</span>
    <h1>A script in. A <span class="hl">video</span> out.</h1>
    <p class="lede">
        Generate a reel from a topic or full script — pick <strong>realistic</strong>
        or <strong>cartoon</strong>, <strong>short</strong> or <strong>long</strong> —
        or upload your own footage. The finished video plays right here.
    </p>
</section>

<?php if ($flash !== null): ?>
    <div class="note"><?= h($flash) ?></div>
<?php endif; ?>

<?php if ($error !== null): ?>
    <div class="alert">
        <strong>Database error.</strong> <?= h($error) ?><br>
        Start XAMPP's <em>Apache</em> and <em>MySQL</em> modules, then reload.
    </div>
<?php endif; ?>

<div class="provider-banner <?= $providerOn ? 'on' : 'off' ?>">
    <?php if ($providerOn): ?>
        <strong>Video provider connected.</strong> Reels render to real MP4s via your configured service.
    <?php else: ?>
        <strong>Preview mode.</strong> Realistic &amp; cartoon reels play as an in-browser preview.
        Connect a video-generation API (endpoint + key in <code>config/config.php</code>) to render real MP4s.
    <?php endif; ?>
</div>

<section class="panel">
    <form method="post" action="<?= h(url('create.php')) ?>" class="reel-form">
        <label for="topic">Topic</label>
        <input id="topic" name="topic" required maxlength="255"
               placeholder="e.g. why octopuses have three hearts"
               value="<?= h($_GET['topic'] ?? '') ?>">

        <label for="script">Script <span class="muted">(optional — leave blank to auto-write)</span></label>
        <textarea id="script" name="script" rows="4"
                  placeholder="Paste your own narration, or let the generator write it."></textarea>

        <div class="options">
            <fieldset>
                <legend>Look</legend>
                <label class="radio"><input type="radio" name="render_style" value="realistic" checked> Realistic people</label>
                <label class="radio"><input type="radio" name="render_style" value="cartoon"> Cartoon</label>
            </fieldset>
            <fieldset>
                <legend>Length</legend>
                <label class="radio"><input type="radio" name="length_mode" value="short" checked> Short</label>
                <label class="radio"><input type="radio" name="length_mode" value="long"> Long</label>
            </fieldset>
        </div>

        <div class="row">
            <div>
                <label for="caption_style">Caption style</label>
                <select id="caption_style" name="caption_style">
                    <option value="karaoke-bold-yellow">Karaoke · bold yellow</option>
                    <option value="minimal-white">Minimal · white</option>
                    <option value="gradient-pop">Gradient pop</option>
                </select>
            </div>
            <div>
                <label for="voice_id">Voice</label>
                <select id="voice_id" name="voice_id">
                    <option value="narrator-warm">Narrator · warm</option>
                    <option value="narrator-bright">Narrator · bright</option>
                    <option value="narrator-deep">Narrator · deep</option>
                </select>
            </div>
        </div>

        <button type="submit">Generate video</button>
    </form>
</section>

<section id="uploads" class="uploads">
    <h2>Upload a video</h2>
    <form method="post" action="<?= h(url('upload.php')) ?>" enctype="multipart/form-data" class="upload-form">
        <input type="file" name="video" accept="video/mp4,video/webm,video/quicktime,.mp4,.webm,.mov" required>
        <button type="submit" class="ghost">Upload</button>
    </form>
    <p class="muted small">MP4, WebM, or MOV · up to <?= (int) round(config()['uploads']['max_bytes'] / 1048576) ?> MB.</p>

    <?php if (!empty($uploads)): ?>
        <div class="upload-grid">
            <?php foreach ($uploads as $u): ?>
                <figure class="upload-card">
                    <video controls preload="metadata" src="<?= h(url($u['stored_path'])) ?>"></video>
                    <figcaption title="<?= h($u['original_name']) ?>"><?= h($u['original_name']) ?></figcaption>
                </figure>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</section>

<section class="reels">
    <h2>Recent reels</h2>
    <?php if (empty($reels)): ?>
        <p class="muted">No reels yet — generate your first one above.</p>
    <?php else: ?>
        <div class="reel-list">
            <?php foreach ($reels as $r): ?>
                <a class="reel-card" href="<?= h(url('reel.php?id=' . (int) $r['id'])) ?>">
                    <div class="reel-card-top">
                        <span class="status status-<?= h($r['status']) ?>"><?= h(status_label($r['status'])) ?></span>
                        <span class="dur"><?= number_format((float) $r['duration_sec'], 0) ?>s</span>
                    </div>
                    <div class="reel-topic"><?= h($r['topic']) ?></div>
                    <div class="reel-meta">#<?= (int) $r['id'] ?> · <?= h((string) $r['created_at']) ?></div>
                </a>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</section>

<?php
layout_footer();
