<?php
/** Owner dashboard: finance overview, per-branch performance, 14-day chart. */
$PAGE  = 'dashboard.php';
$TITLE = 'Dashboard';
require_once __DIR__ . '/includes/auth.php';
require_page('dashboard.php');
$pdo = db();

// Branch filter (owner can drill into one shop or view all).
$branches = $pdo->query('SELECT * FROM branches ORDER BY id')->fetchAll();
$bf = isset($_GET['branch']) ? (int) $_GET['branch'] : 0;   // 0 = all
$where = $bf ? 'WHERE s.branch_id = ' . $bf : '';

// Headline figures.
$rev = (float) $pdo->query("SELECT COALESCE(SUM(total),0) FROM sales s $where")->fetchColumn();
$vat = (float) $pdo->query("SELECT COALESCE(SUM(vat),0) FROM sales s $where")->fetchColumn();
$cnt = (int)   $pdo->query("SELECT COUNT(*) FROM sales s $where")->fetchColumn();
$cogs = (float) $pdo->query(
    "SELECT COALESCE(SUM(si.qty * si.unit_cost),0)
     FROM sale_items si JOIN sales s ON s.id = si.sale_id $where"
)->fetchColumn();
$expWhere = $bf ? 'WHERE branch_id = ' . $bf : '';
$exp = (float) $pdo->query("SELECT COALESCE(SUM(amount),0) FROM expenses $expWhere")->fetchColumn();
$grossProfit = $rev - $vat - $cogs;
$netProfit   = $grossProfit - $exp;
$avgSale     = $cnt ? $rev / $cnt : 0;

// Per-branch performance table.
$perBranch = $pdo->query(
    "SELECT b.name,
            COALESCE(SUM(s.total),0)                    AS revenue,
            COUNT(s.id)                                 AS sales,
            COALESCE(SUM(si2.cost),0)                   AS cogs
     FROM branches b
     LEFT JOIN sales s ON s.branch_id = b.id
     LEFT JOIN (SELECT sale_id, SUM(qty*unit_cost) cost FROM sale_items GROUP BY sale_id) si2
            ON si2.sale_id = s.id
     GROUP BY b.id, b.name ORDER BY revenue DESC"
)->fetchAll();

// 14-day revenue series for the chart.
$rows = $pdo->query(
    "SELECT DATE(created_at) d, SUM(total) t
     FROM sales s $where
     GROUP BY DATE(created_at) ORDER BY d"
)->fetchAll();
$byDay = [];
foreach ($rows as $r) { $byDay[$r['d']] = (float) $r['t']; }
$series = [];
for ($i = 13; $i >= 0; $i--) {
    $day = date('Y-m-d', strtotime("-$i days"));
    $series[] = ['label' => date('j M', strtotime($day)), 'v' => $byDay[$day] ?? 0];
}
$maxV = max(1, max(array_map(fn($p) => $p['v'], $series)));

// Low-stock watch.
$low = $pdo->query('SELECT name, stock FROM products WHERE active=1 AND stock <= 15 ORDER BY stock ASC LIMIT 6')->fetchAll();

require __DIR__ . '/includes/layout_top.php';
?>
<form method="get" class="filter-bar">
  <label>Branch
    <select name="branch" onchange="this.form.submit()">
      <option value="0"<?= $bf === 0 ? ' selected' : '' ?>>All branches</option>
      <?php foreach ($branches as $b): ?>
        <option value="<?= (int)$b['id'] ?>"<?= $bf === (int)$b['id'] ? ' selected' : '' ?>><?= h($b['name']) ?></option>
      <?php endforeach; ?>
    </select>
  </label>
</form>

<div class="kpi-grid">
  <div class="kpi"><div class="kpi-label">Revenue</div><div class="kpi-value"><?= money($rev) ?></div></div>
  <div class="kpi"><div class="kpi-label">Net profit</div><div class="kpi-value"><?= money($netProfit) ?></div></div>
  <div class="kpi"><div class="kpi-label">Sales</div><div class="kpi-value"><?= number_format($cnt) ?></div></div>
  <div class="kpi"><div class="kpi-label">Avg. sale</div><div class="kpi-value"><?= money($avgSale) ?></div></div>
</div>

<div class="grid-2">
  <section class="card">
    <h2>Revenue — last 14 days</h2>
    <div class="chart">
      <?php foreach ($series as $p): ?>
        <div class="bar" style="height:<?= max(2, round($p['v'] / $maxV * 100)) ?>%" title="<?= h($p['label']) ?>: <?= money($p['v']) ?>">
          <span class="bar-cap"><?= $p['v'] ? h(number_format($p['v'], 0)) : '' ?></span>
        </div>
      <?php endforeach; ?>
    </div>
    <div class="chart-x">
      <?php foreach ($series as $p): ?><span><?= h($p['label']) ?></span><?php endforeach; ?>
    </div>
  </section>

  <section class="card">
    <h2>Finance breakdown</h2>
    <table class="table">
      <tr><td>Gross revenue</td><td class="num"><?= money($rev) ?></td></tr>
      <tr><td>VAT (<?= (int)(VAT_RATE*100) ?>%) collected</td><td class="num"><?= money($vat) ?></td></tr>
      <tr><td>Cost of goods sold</td><td class="num"><?= money($cogs) ?></td></tr>
      <tr><td>Gross profit</td><td class="num"><?= money($grossProfit) ?></td></tr>
      <tr><td>Operating expenses</td><td class="num"><?= money($exp) ?></td></tr>
      <tr class="total"><td>Net profit</td><td class="num"><?= money($netProfit) ?></td></tr>
    </table>
  </section>
</div>

<div class="grid-2">
  <section class="card">
    <h2>Performance by branch</h2>
    <table class="table">
      <thead><tr><th>Branch</th><th class="num">Revenue</th><th class="num">Sales</th><th class="num">Gross profit</th></tr></thead>
      <tbody>
        <?php foreach ($perBranch as $r): $gp = (float)$r['revenue'] - (float)$r['cogs']; ?>
          <tr>
            <td><?= h($r['name']) ?></td>
            <td class="num"><?= money($r['revenue']) ?></td>
            <td class="num"><?= number_format($r['sales']) ?></td>
            <td class="num"><?= money($gp) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </section>

  <section class="card">
    <h2>Low stock watch</h2>
    <?php if ($low): ?>
      <table class="table">
        <thead><tr><th>Product</th><th class="num">Units left</th></tr></thead>
        <tbody>
          <?php foreach ($low as $l): ?>
            <tr><td><?= h($l['name']) ?></td><td class="num"><span class="tag warn"><?= (int)$l['stock'] ?></span></td></tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php else: ?>
      <p class="muted">All products are well stocked.</p>
    <?php endif; ?>
  </section>
</div>

<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
