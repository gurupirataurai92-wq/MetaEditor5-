<?php
/** Branches — owner opens/closes shops and sees staffing + revenue per branch. */
$PAGE  = 'branches.php';
$TITLE = 'Branches';
require_once __DIR__ . '/includes/auth.php';
$user = require_page('branches.php');
$pdo  = db();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = $_POST['action'] ?? '';

    if ($action === 'add') {
        $name = trim($_POST['name'] ?? '');
        $loc  = trim($_POST['location'] ?? '');
        if ($name === '') {
            flash_set('error', 'A branch name is required.');
        } else {
            $pdo->prepare('INSERT INTO branches (name, location) VALUES (?, ?)')->execute([$name, $loc]);
            flash_set('ok', 'Branch "' . $name . '" opened.');
        }
        redirect('branches.php');
    }

    if ($action === 'close') {
        $id = (int) ($_POST['id'] ?? 0);
        $staff = (int) $pdo->query('SELECT COUNT(*) FROM users WHERE active=1 AND branch_id=' . $id)->fetchColumn();
        $sales = (int) $pdo->query('SELECT COUNT(*) FROM sales WHERE branch_id=' . $id)->fetchColumn();
        if ($staff > 0 || $sales > 0) {
            flash_set('error', 'Reassign staff and note that sales history exists before closing this branch.');
        } else {
            $pdo->prepare('DELETE FROM branches WHERE id = ?')->execute([$id]);
            flash_set('ok', 'Branch closed.');
        }
        redirect('branches.php');
    }
}

$rows = $pdo->query(
    'SELECT b.*,
            (SELECT COUNT(*) FROM users u WHERE u.active=1 AND u.branch_id=b.id) AS staff,
            (SELECT COALESCE(SUM(total),0) FROM sales s WHERE s.branch_id=b.id)    AS revenue
     FROM branches b ORDER BY b.id'
)->fetchAll();

require __DIR__ . '/includes/layout_top.php';
?>
<section class="card">
  <h2>Open a branch</h2>
  <form method="post" class="form-row"><?= csrf_field() ?>
    <input type="hidden" name="action" value="add">
    <label>Branch name *<input name="name" required placeholder="e.g. Mutare Branch"></label>
    <label>Location<input name="location" placeholder="Town / suburb"></label>
    <button class="btn btn-primary" type="submit">Open branch</button>
  </form>
</section>

<section class="card">
  <h2>Branches (<?= count($rows) ?>)</h2>
  <div class="table-scroll">
    <table class="table">
      <thead><tr><th>Branch</th><th>Location</th><th class="num">Staff</th><th class="num">Revenue</th><th></th></tr></thead>
      <tbody>
        <?php foreach ($rows as $b): ?>
          <tr>
            <td><?= h($b['name']) ?></td>
            <td><?= h($b['location'] ?: '—') ?></td>
            <td class="num"><?= (int)$b['staff'] ?></td>
            <td class="num"><?= money($b['revenue']) ?></td>
            <td class="row-actions">
              <form method="post" class="inline" onsubmit="return confirm('Close this branch?')"><?= csrf_field() ?>
                <input type="hidden" name="action" value="close">
                <input type="hidden" name="id" value="<?= (int)$b['id'] ?>">
                <button class="btn btn-ghost btn-sm danger" type="submit">Close</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>
<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
