<?php
/** Operator view: manage generated reels. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/admin.php';
require_once __DIR__ . '/../includes/pipeline.php';

$op = require_login();
$msg = null;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    if (!csrf_verify($_POST['csrf'] ?? null)) {
        $msg = 'Session expired — try again.';
    } elseif (($_POST['action'] ?? '') === 'delete') {
        delete_reel((int) ($_POST['id'] ?? 0));
        $msg = 'Reel deleted.';
    }
}

$reels = list_reels(100);

admin_header('Reels', $op);
?>
<h1>Reels <span class="count"><?= count($reels) ?></span></h1>
<?php if ($msg !== null): ?><div class="note"><?= h($msg) ?></div><?php endif; ?>

<?php if (empty($reels)): ?>
    <p class="muted">No reels yet.</p>
<?php else: ?>
<div class="table-wrap">
    <table>
        <thead><tr><th>#</th><th>Topic</th><th>Status</th><th>Duration</th><th>Created</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($reels as $r): ?>
            <tr>
                <td><?= (int) $r['id'] ?></td>
                <td><a href="../reel.php?id=<?= (int) $r['id'] ?>"><?= h($r['topic']) ?></a></td>
                <td><span class="status status-<?= h($r['status']) ?>"><?= h(status_label($r['status'])) ?></span></td>
                <td><?= number_format((float) $r['duration_sec'], 0) ?>s</td>
                <td class="muted small"><?= h((string) $r['created_at']) ?></td>
                <td>
                    <form method="post" onsubmit="return confirm('Delete reel #<?= (int) $r['id'] ?>?');">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="id" value="<?= (int) $r['id'] ?>">
                        <button class="danger" type="submit">Delete</button>
                    </form>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</div>
<?php endif; ?>
<?php
admin_footer();
