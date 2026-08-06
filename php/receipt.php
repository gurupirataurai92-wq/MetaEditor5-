<?php
/** Printable receipt for a completed sale. Operators see only their own. */
$PAGE  = 'receipt.php';
$TITLE = 'Receipt';
require_once __DIR__ . '/includes/auth.php';
$user = require_page('receipt.php');
$pdo  = db();

$id = (int) ($_GET['id'] ?? 0);
$st = $pdo->prepare(
    'SELECT s.*, b.name AS branch, u.name AS cashier
     FROM sales s JOIN branches b ON b.id = s.branch_id
     JOIN users u ON u.id = s.user_id WHERE s.id = ?'
);
$st->execute([$id]);
$sale = $st->fetch();

// Till operators can only view receipts they rang up.
if (!$sale || ($user['role'] === 'cashier' && (int)$sale['user_id'] !== (int)$user['id'])) {
    flash_set('error', 'Receipt not found.');
    redirect(ROLE_HOME[$user['role']] ?? 'login.php');
}
$items = $pdo->prepare('SELECT * FROM sale_items WHERE sale_id = ?');
$items->execute([$id]);
$items = $items->fetchAll();

require __DIR__ . '/includes/layout_top.php';
?>
<div class="receipt-wrap">
  <div class="receipt" id="receipt">
    <div class="r-brand">◆ <?= h(APP_NAME) ?></div>
    <div class="r-sub"><?= h($sale['branch']) ?></div>
    <div class="r-meta">
      Receipt #<?= (int)$sale['id'] ?><br>
      <?= h(date('d M Y, H:i', strtotime($sale['created_at']))) ?><br>
      Served by <?= h($sale['cashier']) ?>
    </div>
    <hr>
    <table class="r-items">
      <?php foreach ($items as $it): ?>
        <tr>
          <td><?= h($it['name']) ?><br><span class="r-q"><?= (int)$it['qty'] ?> × <?= money($it['unit_price']) ?></span></td>
          <td class="num"><?= money($it['qty'] * $it['unit_price']) ?></td>
        </tr>
      <?php endforeach; ?>
    </table>
    <hr>
    <table class="r-items">
      <tr><td>VAT (<?= (int)(VAT_RATE*100) ?>%)</td><td class="num"><?= money($sale['vat']) ?></td></tr>
      <tr class="r-total"><td>Total</td><td class="num"><?= money($sale['total']) ?></td></tr>
      <tr><td>Paid by</td><td class="num"><?= h(ucfirst($sale['method'])) ?></td></tr>
    </table>
    <hr>
    <div class="r-foot">Thank you for your business!</div>
  </div>

  <div class="receipt-actions">
    <button class="btn btn-primary" onclick="window.print()">🖶 Print receipt</button>
    <a class="btn btn-ghost" href="pos.php">New sale →</a>
  </div>
</div>
<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
