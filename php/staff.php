<?php
/**
 * Staff & Duty. Managers/owners see who is on/off duty, add operators (each
 * gets a confidential password, stored only as a hash — NEVER shown anywhere),
 * assign branches, toggle duty, and remove staff. Only the owner may create
 * or remove another owner/manager.
 */
$PAGE  = 'staff.php';
$TITLE = 'Staff & Duty';
require_once __DIR__ . '/includes/auth.php';
$user = require_page('staff.php');
$pdo  = db();

$assignableRoles = $user['role'] === 'owner'
    ? ['cashier' => 'Till Operator', 'manager' => 'Manager', 'owner' => 'Owner']
    : ['cashier' => 'Till Operator'];   // managers can only add till operators

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = $_POST['action'] ?? '';

    if ($action === 'add') {
        $name  = trim($_POST['name'] ?? '');
        $email = strtolower(trim($_POST['email'] ?? ''));
        $pass  = $_POST['password'] ?? '';
        $role  = $_POST['role'] ?? 'cashier';
        $branch = (int) ($_POST['branch_id'] ?? 1);
        if (!isset($assignableRoles[$role])) {
            $role = 'cashier';
        }
        if ($name === '' || $email === '' || strlen($pass) < 6) {
            flash_set('error', 'Name, email and a password of at least 6 characters are required.');
        } else {
            try {
                $st = $pdo->prepare(
                    'INSERT INTO users (name, email, password_hash, role, branch_id, active)
                     VALUES (?, ?, ?, ?, ?, 1)'
                );
                $st->execute([$name, $email, password_hash($pass, PASSWORD_DEFAULT), $role, $branch]);
                flash_set('ok', $name . ' was added. Their password is confidential to them.');
            } catch (PDOException $e) {
                flash_set('error', $e->getCode() === '23000'
                    ? 'That email is already registered.'
                    : 'Could not add the operator.');
            }
        }
        redirect('staff.php');
    }

    if ($action === 'toggle') {
        $id = (int) ($_POST['id'] ?? 0);
        $st = $pdo->prepare('UPDATE users SET on_duty = 1 - on_duty WHERE id = ?');
        $st->execute([$id]);
        redirect('staff.php');
    }

    if ($action === 'remove') {
        $id = (int) ($_POST['id'] ?? 0);
        // Managers cannot remove owners/managers; nobody can remove themselves.
        $target = $pdo->prepare('SELECT role FROM users WHERE id = ?');
        $target->execute([$id]);
        $trole = $target->fetchColumn();
        $allowed = $id !== (int)$user['id']
            && ($user['role'] === 'owner' || $trole === 'cashier');
        if ($allowed) {
            $pdo->prepare('UPDATE users SET active = 0, on_duty = 0 WHERE id = ?')->execute([$id]);
            flash_set('ok', 'Operator removed.');
        } else {
            flash_set('error', 'You cannot remove that account.');
        }
        redirect('staff.php');
    }
}

$branches = $pdo->query('SELECT * FROM branches ORDER BY id')->fetchAll();
$branchName = [];
foreach ($branches as $b) { $branchName[$b['id']] = $b['name']; }

$staff = $pdo->query(
    'SELECT * FROM users WHERE active = 1 ORDER BY FIELD(role,"owner","manager","cashier"), name'
)->fetchAll();

require __DIR__ . '/includes/layout_top.php';
?>
<section class="card">
  <h2>Add an operator</h2>
  <p class="muted">The operator sets their own <b>confidential password</b> at hiring.
  It is stored as an unreadable hash and is never displayed anywhere in the system.</p>
  <form method="post" class="form-row"><?= csrf_field() ?>
    <input type="hidden" name="action" value="add">
    <label>Full name *<input name="name" required></label>
    <label>Email *<input name="email" type="email" required></label>
    <label>Password *<input name="password" type="password" required minlength="6" placeholder="min 6 characters"></label>
    <label>Role
      <select name="role">
        <?php foreach ($assignableRoles as $val => $lbl): ?>
          <option value="<?= h($val) ?>"><?= h($lbl) ?></option>
        <?php endforeach; ?>
      </select>
    </label>
    <label>Branch
      <select name="branch_id">
        <?php foreach ($branches as $b): ?>
          <option value="<?= (int)$b['id'] ?>"><?= h($b['name']) ?></option>
        <?php endforeach; ?>
      </select>
    </label>
    <button class="btn btn-primary" type="submit">Add operator</button>
  </form>
</section>

<section class="card">
  <h2>Team (<?= count($staff) ?>)</h2>
  <div class="table-scroll">
    <table class="table">
      <thead><tr><th>Name</th><th>Role</th><th>Branch</th><th>Duty</th><th></th></tr></thead>
      <tbody>
        <?php foreach ($staff as $s): ?>
          <tr>
            <td><?= h($s['name']) ?><div class="sub"><?= h($s['email']) ?></div></td>
            <td><span class="tag role-<?= h($s['role']) ?>"><?= h(ROLE_LABEL[$s['role']] ?? $s['role']) ?></span></td>
            <td><?= h($branchName[$s['branch_id']] ?? '—') ?></td>
            <td>
              <form method="post" class="inline"><?= csrf_field() ?>
                <input type="hidden" name="action" value="toggle">
                <input type="hidden" name="id" value="<?= (int)$s['id'] ?>">
                <button type="submit" class="duty <?= $s['on_duty'] ? 'on' : 'off' ?>">
                  <?= $s['on_duty'] ? 'On duty' : 'Off duty' ?>
                </button>
              </form>
            </td>
            <td class="row-actions">
              <?php if ((int)$s['id'] !== (int)$user['id'] && ($user['role'] === 'owner' || $s['role'] === 'cashier')): ?>
                <form method="post" class="inline" onsubmit="return confirm('Remove <?= h(addslashes($s['name'])) ?>?')"><?= csrf_field() ?>
                  <input type="hidden" name="action" value="remove">
                  <input type="hidden" name="id" value="<?= (int)$s['id'] ?>">
                  <button class="btn btn-ghost btn-sm danger" type="submit">Remove</button>
                </form>
              <?php else: ?>
                <span class="muted">—</span>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
