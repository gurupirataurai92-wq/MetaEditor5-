<?php
/** Home: create form + list of recent reels. */

declare(strict_types=1);

require_once __DIR__ . '/includes/pipeline.php';
require_once __DIR__ . '/includes/layout.php';

$error = null;
$reels = [];
try {
    $reels = list_reels(20);
} catch (Throwable $e) {
    $error = $e->getMessage();
}

layout_header('Create a reel');
?>

<section class="hero">
    <span class="eyebrow">Faceless short-form video</span>
    <h1>A topic in. A <span class="hl">reel</span> out.</h1>
    <p class="lede">
        Type a topic and the pipeline writes the script, times a voiceover,
        sources visuals, and syncs karaoke captions — then plays the finished
        9:16 reel right in your browser.
    </p>
</section>

<?php if ($error !== null): ?>
    <div class="alert">
        <strong>Database error.</strong> <?= h($error) ?><br>
        Start XAMPP's <em>Apache</em> and <em>MySQL</em> modules, then reload.
    </div>
<?php endif; ?>

<section class="panel">
    <form method="post" action="<?= h(url('create.php')) ?>" class="reel-form">
        <label for="topic">Topic</label>
        <input id="topic" name="topic" required maxlength="255"
               placeholder="e.g. why octopuses have three hearts"
               value="<?= h($_GET['topic'] ?? '') ?>">

        <label for="script">Script <span class="muted">(optional — leave blank to auto-write)</span></label>
        <textarea id="script" name="script" rows="4"
                  placeholder="Paste your own narration, or let the generator write it."></textarea>

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

        <button type="submit">Generate reel</button>
    </form>
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
