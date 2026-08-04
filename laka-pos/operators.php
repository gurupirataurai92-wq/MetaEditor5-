<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner']);   // only the owner manages operators

$pdo = db();
$flash = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['add_user'])) {
        $name = trim($_POST['full_name'] ?? '');
        $user = trim($_POST['username'] ?? '');
        $pass = $_POST['password'] ?? '';
        $role = in_array($_POST['role'] ?? '', ['owner','manager','cashier','cook'], true) ? $_POST['role'] : 'cashier';
        if ($name === '' || $user === '' || strlen($pass) < 4) {
            $_SESSION['flash'] = 'Enter a name, username and a password of at least 4 characters.';
        } else {
            try {
                $pdo->prepare('INSERT INTO users (full_name, username, password_hash, role) VALUES (?,?,?,?)')
                    ->execute([$name, $user, password_hash($pass, PASSWORD_BCRYPT), $role]);
                log_action('user_add', "Added operator $user ($role)");
                $_SESSION['flash'] = "Operator “$user” added.";
            } catch (Throwable $ex) {
                $_SESSION['flash'] = 'That username is already taken.';
            }
        }
    }
    if (isset($_POST['toggle_active'])) {
        $id = (int) $_POST['toggle_active'];
        if ($id !== (int) current_user()['id']) {
            $pdo->prepare('UPDATE users SET is_active = 1 - is_active WHERE id = ?')->execute([$id]);
            log_action('user_toggle', "Toggled operator #$id");
        }
    }
    if (isset($_POST['reset_pw'])) {
        $id = (int) $_POST['reset_pw']; $pw = $_POST['new_password'] ?? '';
        if (strlen($pw) >= 4) {
            $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
                ->execute([password_hash($pw, PASSWORD_BCRYPT), $id]);
            log_action('user_pw', "Reset password for operator #$id");
            $_SESSION['flash'] = 'Password updated.';
        }
    }
    if (isset($_POST['delete_user'])) {
        $id = (int) $_POST['delete_user'];
        if ($id !== (int) current_user()['id']) {
            try {
                $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$id]);
                log_action('user_delete', "Deleted operator #$id");
                $_SESSION['flash'] = 'Operator removed.';
            } catch (Throwable $ex) {
                $pdo->prepare('UPDATE users SET is_active = 0 WHERE id = ?')->execute([$id]);
                $_SESSION['flash'] = 'Operator has sales history, so they were deactivated instead of deleted.';
            }
        }
    }
    header('Location: operators.php');
    exit;
}

if (!empty($_SESSION['flash'])) { $flash = $_SESSION['flash']; unset($_SESSION['flash']); }

$users = $pdo->query('SELECT * FROM users ORDER BY role, full_name')->fetchAll();

$page_title = 'Operators';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Operators <span class="sub">— staff accounts &amp; access</span></h1>
<?php if ($flash): ?><div class="flash ok"><?= e($flash) ?></div><?php endif; ?>

<section class="panel" style="margin-bottom:20px">
  <h2 style="font-family:var(--display);text-transform:uppercase;font-size:16px;margin-bottom:12px">Add an operator</h2>
  <form method="post" class="add-item">
    <label>Full name <input name="full_name" required placeholder="e.g. Nyasha Moyo"></label>
    <label>Username <input name="username" required placeholder="e.g. nyasha"></label>
    <label>Password <input name="password" type="text" required placeholder="min 4 chars"></label>
    <label>Role
      <select name="role">
        <option value="cashier">Cashier / Till</option>
        <option value="cook">Line cook</option>
        <option value="manager">Manager</option>
        <option value="owner">Owner</option>
      </select>
    </label>
    <button type="submit" name="add_user" value="1" class="charge" style="width:auto;padding:12px 22px">Add operator</button>
  </form>
</section>

<div class="table-wrap">
<table class="grid-table">
  <thead>
    <tr><th>Name</th><th>Username</th><th>Role</th><th>Status</th><th>Reset password</th><th>Remove</th></tr>
  </thead>
  <tbody>
  <?php foreach ($users as $u):
      $isSelf = (int) $u['id'] === (int) current_user()['id'];
  ?>
    <tr class="<?= $u['is_active'] ? '' : 'row-off' ?>">
      <td><b><?= e($u['full_name']) ?></b><?= $isSelf ? ' <span class="mono" style="color:var(--muted)">(you)</span>' : '' ?></td>
      <td class="mono"><?= e($u['username']) ?></td>
      <td><span class="badge b-placed"><?= e($u['role']) ?></span></td>
      <td>
        <?php if ($isSelf): ?>
          <span class="badge b-served">active</span>
        <?php else: ?>
        <form method="post">
          <button name="toggle_active" value="<?= (int) $u['id'] ?>" class="badge <?= $u['is_active'] ? 'b-served' : 'b-void' ?> btn-badge">
            <?= $u['is_active'] ? 'active' : 'disabled' ?>
          </button>
        </form>
        <?php endif; ?>
      </td>
      <td>
        <form method="post" class="price-form">
          <input type="hidden" name="reset_pw" value="<?= (int) $u['id'] ?>">
          <input type="text" name="new_password" placeholder="new password">
          <button type="submit">set</button>
        </form>
      </td>
      <td>
        <?php if (!$isSelf): ?>
        <form method="post" onsubmit="return confirm('Remove <?= e(addslashes($u['username'])) ?>?');">
          <button name="delete_user" value="<?= (int) $u['id'] ?>" class="del-btn">🗑 remove</button>
        </form>
        <?php else: ?><span class="mono" style="color:var(--muted)">—</span><?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<p class="hint">New operators sign in at <b>staff.php</b>. Operators with sales history are deactivated instead of deleted so reports stay intact.</p>
<?php require __DIR__ . '/includes/footer.php'; ?>
