<?php
/** Operator dashboard. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/admin.php';
require_once __DIR__ . '/../includes/pipeline.php';

$op = require_login();
$stats = admin_stats();
$providerOn = (bool) (config()['video']['enabled'] ?? false);

admin_header('Dashboard', $op);
?>
<h1>Dashboard</h1>
<p class="muted">Signed in as <strong><?= h($op['username']) ?></strong> (<?= h($op['role']) ?>).</p>

<div class="stat-grid">
    <div class="stat-box"><div class="n"><?= (int) $stats['reels'] ?></div><div class="l">Reels</div></div>
    <div class="stat-box"><div class="n"><?= (int) $stats['scenes'] ?></div><div class="l">Scenes</div></div>
    <div class="stat-box"><div class="n"><?= (int) $stats['uploads'] ?></div><div class="l">Uploads</div></div>
    <div class="stat-box"><div class="n"><?= (int) $stats['operators'] ?></div><div class="l">Operators</div></div>
</div>

<div class="admin-cards">
    <a class="admin-card" href="reels.php"><h3>Manage reels →</h3><p>Review and delete generated reels.</p></a>
    <a class="admin-card" href="uploads.php"><h3>Manage uploads →</h3><p>Review and remove uploaded videos.</p></a>
    <a class="admin-card" href="operators.php"><h3>Manage operators →</h3><p>Add operators or change passwords.</p></a>
</div>

<div class="provider-banner <?= $providerOn ? 'on' : 'off' ?>">
    <?php if ($providerOn): ?>
        <strong>Video provider connected.</strong> Reels render to real MP4s.
    <?php else: ?>
        <strong>Preview mode.</strong> No video provider configured — reels play as in-browser previews.
    <?php endif; ?>
</div>

<div class="note">
    <strong>Security reminder.</strong> If the default <code>admin</code> account still uses its
    starter password, change it now on the <a href="operators.php">Operators</a> page.
</div>
<?php
admin_footer();
