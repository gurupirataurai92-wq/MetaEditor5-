<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager', 'cashier']);

$orders = db()->query(
    'SELECT o.*, u.full_name AS cashier,
            (SELECT method FROM payments p WHERE p.order_id = o.id LIMIT 1) AS method
     FROM orders o
     LEFT JOIN users u ON u.id = o.cashier_id
     ORDER BY o.created_at DESC
     LIMIT 100'
)->fetchAll();

$itemStmt = db()->prepare('SELECT item_name, qty FROM order_items WHERE order_id = ?');

$page_title = 'Orders';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Orders <span class="sub">— last 100</span></h1>
<div class="table-wrap">
<table class="grid-table">
  <thead>
    <tr><th>#</th><th>When</th><th>Channel</th><th>Items</th><th>Customer / Cashier</th><th>Pay</th><th class="r">Total</th><th>Status</th></tr>
  </thead>
  <tbody>
  <?php foreach ($orders as $o):
      $itemStmt->execute([$o['id']]);
      $names = array_map(fn($r) => $r['qty'] . '× ' . $r['item_name'], $itemStmt->fetchAll());
      if (!empty($o['customer_name'])) {
          $who = $o['customer_name'] . ' · ' . $o['customer_phone']
               . ' (' . ($o['order_type'] ?: 'pickup') . ')';
      } else {
          $who = $o['cashier'] ?? '—';
      }
  ?>
    <tr>
      <td class="mono">#<?= (int) $o['id'] ?></td>
      <td class="mono"><?= e(date('d M H:i', strtotime($o['created_at']))) ?></td>
      <td><?= e(str_replace('_', ' ', $o['channel'])) ?></td>
      <td class="items"><?= e(implode(', ', $names)) ?></td>
      <td><?= e($who) ?></td>
      <td><?= e($o['method'] ?? '—') ?><?= ($o['payment_status'] ?? '') === 'unpaid' && $o['channel'] === 'online' ? ' <span class="badge b-placed">pending</span>' : '' ?></td>
      <td class="r mono">$<?= money((float) $o['total']) ?></td>
      <td><span class="badge b-<?= e($o['status']) ?>"><?= e($o['status']) ?></span></td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
