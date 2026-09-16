<?php
/** Operator view: manage operator accounts. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/admin.php';

$op = require_login();
$msg = null;
$err = null;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    if (!csrf_verify($_POST['csrf'] ?? null)) {
        $err = 'Session expired — try again.';
    } else {
        $action = (string) ($_POST['action'] ?? '');
        try {
            if ($action === 'create') {
                create_operator(
                    (string) ($_POST['username'] ?? ''),
                    (string) ($_POST['password'] ?? ''),
                    (string) ($_POST['role'] ?? 'operator')
                );
                $msg = 'Operator added.';
            } elseif ($action === 'delete') {
                $id = (int) ($_POST['id'] ?? 0);
                if ($id === (int) $op['id']) {
                    throw new RuntimeException('You cannot delete the account you are signed in as.');
                }
                delete_operator($id);
                $msg = 'Operator removed.';
            } elseif ($action === 'password') {
                set_operator_password((int) ($_POST['id'] ?? 0), (string) ($_POST['password'] ?? ''));
                $msg = 'Password updated.';
            }
        } catch (Throwable $e) {
            $err = $e->getMessage();
        }
    }
}

$operators = list_operators();

admin_header('Operators', $op);
?>
<h1>Operators <span class="count"><?= count($operators) ?></span></h1>
<?php if ($msg !== null): ?><div class="note"><?= h($msg) ?></div><?php endif; ?>
<?php if ($err !== null): ?><div class="alert"><?= h($err) ?></div><?php endif; ?>

<div class="admin-two">
    <section class="panel">
        <h3>Add operator</h3>
        <form method="post">
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="create">
            <label for="nu">Username</label>
            <input id="nu" name="username" required maxlength="64">
            <label for="np">Password <span class="muted">(min 6 chars)</span></label>
            <input id="np" name="password" type="password" required minlength="6">
            <label for="nr">Role</label>
            <select id="nr" name="role">
                <option value="operator">Operator</option>
                <option value="admin">Admin</option>
            </select>
            <button type="submit">Add operator</button>
        </form>
    </section>

    <section class="table-wrap">
        <table>
            <thead><tr><th>#</th><th>Username</th><th>Role</th><th>Last login</th><th>Reset password</th><th></th></tr></thead>
            <tbody>
            <?php foreach ($operators as $o): ?>
                <tr>
                    <td><?= (int) $o['id'] ?></td>
                    <td><?= h($o['username']) ?><?= ((int) $o['id'] === (int) $op['id']) ? ' <span class="you">you</span>' : '' ?></td>
                    <td><span class="op-role"><?= h($o['role']) ?></span></td>
                    <td class="muted small"><?= h((string) ($o['last_login'] ?? '—')) ?></td>
                    <td>
                        <form method="post" class="inline-form">
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="password">
                            <input type="hidden" name="id" value="<?= (int) $o['id'] ?>">
                            <input name="password" type="password" placeholder="new password" minlength="6" required>
                            <button type="submit">Set</button>
                        </form>
                    </td>
                    <td>
                        <?php if ((int) $o['id'] !== (int) $op['id']): ?>
                            <form method="post" onsubmit="return confirm('Remove operator <?= h($o['username']) ?>?');">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="id" value="<?= (int) $o['id'] ?>">
                                <button class="danger" type="submit">Delete</button>
                            </form>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </section>
</div>
<?php
admin_footer();
