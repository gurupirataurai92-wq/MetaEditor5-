<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager', 'cook']);

// Bump an item ready, or mark a whole order served.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $pdo = db();
    if (isset($_POST['bump_item'])) {
        $pdo->prepare('UPDATE order_items SET status = "ready" WHERE id = ?')
            ->execute([(int) $_POST['bump_item']]);
        // If every line is ready, the order is ready.
        $oid = (int) $_POST['order_id'];
        $pending = $pdo->prepare('SELECT COUNT(*) FROM order_items WHERE order_id = ? AND status <> "ready"');
        $pending->execute([$oid]);
        if ((int) $pending->fetchColumn() === 0) {
            $pdo->prepare('UPDATE orders SET status = "ready" WHERE id = ?')->execute([$oid]);
        } else {
            $pdo->prepare('UPDATE orders SET status = "cooking" WHERE id = ?')->execute([$oid]);
        }
    }
    if (isset($_POST['serve_order'])) {
        $pdo->prepare('UPDATE orders SET status = "served" WHERE id = ?')
            ->execute([(int) $_POST['serve_order']]);
    }
    header('Location: kitchen.php');
    exit;
}

// Active tickets (not yet served / void), oldest first.
$orders = db()->query(
    "SELECT * FROM orders WHERE status IN ('placed','cooking','ready') ORDER BY created_at ASC"
)->fetchAll();

$itemStmt = db()->prepare('SELECT * FROM order_items WHERE order_id = ? ORDER BY station');

$page_title = 'Kitchen Display';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Kitchen Display <span class="sub">— tickets oldest first, auto-refresh 15s</span></h1>
<meta http-equiv="refresh" content="15">

<?php if (!$orders): ?>
  <p class="empty">No active tickets. Nicely done, chef. 🍗</p>
<?php else: ?>
<div class="kds">
  <?php foreach ($orders as $o):
      $itemStmt->execute([$o['id']]);
      $items = $itemStmt->fetchAll();
      $ageMin = floor((time() - strtotime($o['created_at'])) / 60);
      $ageClass = $ageMin >= 8 ? 'late' : ($ageMin >= 4 ? 'warn' : 'fresh');
  ?>
  <div class="ticket <?= $ageClass ?>">
    <div class="tk-head">
      <b>#<?= (int) $o['id'] ?></b>
      <span class="ch"><?= e(str_replace('_', ' ', $o['channel'])) ?></span>
      <span class="age"><?= (int) $ageMin ?>m</span>
    </div>
    <div class="tk-items">
      <?php foreach ($items as $it): ?>
        <form method="post" class="tk-line <?= $it['status'] === 'ready' ? 'done' : '' ?>">
          <span class="st st-<?= e($it['station']) ?>"><?= e($it['station'][0]) ?></span>
          <span class="qn"><?= (int) $it['qty'] ?>×</span>
          <span class="nm"><?= e($it['item_name']) ?></span>
          <?php if ($it['status'] !== 'ready'): ?>
            <input type="hidden" name="order_id" value="<?= (int) $o['id'] ?>">
            <button name="bump_item" value="<?= (int) $it['id'] ?>" class="bump">bump</button>
          <?php else: ?>
            <span class="rdy">✓</span>
          <?php endif; ?>
        </form>
      <?php endforeach; ?>
    </div>
    <?php if ($o['status'] === 'ready'): ?>
      <form method="post" class="tk-serve">
        <button name="serve_order" value="<?= (int) $o['id'] ?>" class="serve">Hand out — served</button>
      </form>
    <?php endif; ?>
  </div>
  <?php endforeach; ?>
</div>
<?php endif; ?>
<?php require __DIR__ . '/includes/footer.php'; ?>
