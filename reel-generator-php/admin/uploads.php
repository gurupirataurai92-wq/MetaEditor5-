<?php
/** Operator view: manage uploaded videos. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/admin.php';
require_once __DIR__ . '/../includes/pipeline.php';

$op = require_login();
$msg = null;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    if (!csrf_verify($_POST['csrf'] ?? null)) {
        $msg = 'Session expired — try again.';
    } elseif (($_POST['action'] ?? '') === 'delete') {
        delete_upload((int) ($_POST['id'] ?? 0));
        $msg = 'Upload deleted.';
    }
}

$uploads = list_uploads(100);

admin_header('Uploads', $op);
?>
<h1>Uploads <span class="count"><?= count($uploads) ?></span></h1>
<?php if ($msg !== null): ?><div class="note"><?= h($msg) ?></div><?php endif; ?>

<?php if (empty($uploads)): ?>
    <p class="muted">No uploads yet.</p>
<?php else: ?>
<div class="table-wrap">
    <table>
        <thead><tr><th>#</th><th>File</th><th>Type</th><th>Size</th><th>Uploaded</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($uploads as $u): ?>
            <tr>
                <td><?= (int) $u['id'] ?></td>
                <td><a href="../<?= h($u['stored_path']) ?>" target="_blank" rel="noopener"><?= h($u['original_name']) ?></a></td>
                <td class="muted small"><?= h($u['mime']) ?></td>
                <td><?= number_format((float) $u['size_bytes'] / 1048576, 1) ?> MB</td>
                <td class="muted small"><?= h((string) $u['created_at']) ?></td>
                <td>
                    <form method="post" onsubmit="return confirm('Delete this upload and its file?');">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="id" value="<?= (int) $u['id'] ?>">
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
