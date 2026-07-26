<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager']);

$pdo = db();

// Today's headline figures (exclude voided orders).
$today = $pdo->query(
    "SELECT
        COUNT(*)                          AS orders,
        COALESCE(SUM(total),0)            AS revenue,
        COALESCE(SUM(subtotal),0)         AS net_sales,
        COALESCE(SUM(tax_amount),0)       AS tax
     FROM orders
     WHERE status <> 'void' AND DATE(created_at) = CURDATE()"
)->fetch();

// Estimated food cost today (recipe cost of everything sold).
$foodCost = (float) $pdo->query(
    "SELECT COALESCE(SUM(oi.qty * mi.cost),0)
     FROM order_items oi
     JOIN orders o      ON o.id = oi.order_id AND o.status <> 'void' AND DATE(o.created_at) = CURDATE()
     JOIN menu_items mi ON mi.id = oi.menu_item_id"
)->fetchColumn();

$revenue   = (float) $today['revenue'];
$netSales  = (float) $today['net_sales'];
$foodPct   = $netSales > 0 ? ($foodCost / $netSales) * 100 : 0;

// Top sellers today.
$top = $pdo->query(
    "SELECT oi.item_name, SUM(oi.qty) AS units, SUM(oi.qty * oi.unit_price) AS sales
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id AND o.status <> 'void' AND DATE(o.created_at) = CURDATE()
     GROUP BY oi.item_name ORDER BY units DESC LIMIT 5"
)->fetchAll();

// Payment mix today.
$mix = $pdo->query(
    "SELECT p.method, COUNT(*) AS n, COALESCE(SUM(p.amount),0) AS amt
     FROM payments p
     JOIN orders o ON o.id = p.order_id AND o.status <> 'void' AND DATE(o.created_at) = CURDATE()
     GROUP BY p.method ORDER BY amt DESC"
)->fetchAll();

// Low-stock ingredients.
$low = $pdo->query(
    'SELECT name, stock_qty, reorder_point, unit
     FROM ingredients WHERE stock_qty <= reorder_point ORDER BY stock_qty ASC'
)->fetchAll();

$page_title = 'Dashboard';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Dashboard <span class="sub">— today</span></h1>

<div class="kpis">
  <div class="kpi"><span>Revenue</span><b>$<?= money($revenue) ?></b></div>
  <div class="kpi"><span>Orders</span><b><?= (int) $today['orders'] ?></b></div>
  <div class="kpi"><span>Net sales</span><b>$<?= money($netSales) ?></b></div>
  <div class="kpi"><span>Food cost</span><b>$<?= money($foodCost) ?></b></div>
  <div class="kpi accent"><span>Food cost %</span><b><?= number_format($foodPct, 1) ?>%</b></div>
</div>

<div class="cols2">
  <section class="panel">
    <h2>Top sellers</h2>
    <?php if (!$top): ?><p class="empty sm">No sales yet today.</p><?php else: ?>
    <table class="mini">
      <?php foreach ($top as $t): ?>
        <tr><td class="mono"><?= (int) $t['units'] ?>×</td><td><?= e($t['item_name']) ?></td>
            <td class="r mono">$<?= money((float) $t['sales']) ?></td></tr>
      <?php endforeach; ?>
    </table>
    <?php endif; ?>
  </section>

  <section class="panel">
    <h2>Payment mix</h2>
    <?php if (!$mix): ?><p class="empty sm">No payments yet today.</p><?php else: ?>
    <table class="mini">
      <?php foreach ($mix as $m): ?>
        <tr><td><?= e($m['method']) ?></td><td class="mono"><?= (int) $m['n'] ?> txn</td>
            <td class="r mono">$<?= money((float) $m['amt']) ?></td></tr>
      <?php endforeach; ?>
    </table>
    <?php endif; ?>
  </section>
</div>

<section class="panel <?= $low ? 'alert' : '' ?>">
  <h2>Low stock <?= $low ? '— reorder now' : '— all good' ?></h2>
  <?php if (!$low): ?>
    <p class="empty sm">Every ingredient is above its reorder point.</p>
  <?php else: ?>
    <div class="lowgrid">
    <?php foreach ($low as $l): ?>
      <div class="lowitem">
        <b><?= e($l['name']) ?></b>
        <span><?= number_format((float) $l['stock_qty'], 0) ?> <?= e($l['unit']) ?>
          <em>(reorder ≤ <?= number_format((float) $l['reorder_point'], 0) ?>)</em></span>
      </div>
    <?php endforeach; ?>
    </div>
  <?php endif; ?>
</section>
<?php require __DIR__ . '/includes/footer.php'; ?>
