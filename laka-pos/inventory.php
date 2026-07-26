<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager']);

$flash = '';

// Restock an ingredient (adds stock + records a movement).
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['restock_id'])) {
    $id  = (int) $_POST['restock_id'];
    $qty = (float) $_POST['qty'];
    if ($qty > 0) {
        $pdo = db();
        $pdo->beginTransaction();
        $pdo->prepare('UPDATE ingredients SET stock_qty = stock_qty + ? WHERE id = ?')->execute([$qty, $id]);
        $pdo->prepare('INSERT INTO stock_movements (ingredient_id, change_qty, reason) VALUES (?,?,?)')
            ->execute([$id, $qty, 'Restock']);
        $pdo->commit();
        log_action('restock', "Ingredient #$id +$qty");
        $flash = 'Stock updated.';
    }
    header('Location: inventory.php?ok=1');
    exit;
}

$ings = db()->query('SELECT * FROM ingredients ORDER BY name')->fetchAll();

$page_title = 'Inventory';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Inventory</h1>
<?php if (isset($_GET['ok'])): ?><div class="flash ok">Stock updated.</div><?php endif; ?>

<div class="table-wrap">
<table class="grid-table">
  <thead>
    <tr><th>Ingredient</th><th class="r">On hand</th><th class="r">Reorder ≤</th>
        <th class="r">Unit cost</th><th class="r">Stock value</th><th>Status</th><th>Restock</th></tr>
  </thead>
  <tbody>
  <?php foreach ($ings as $i):
      $low = (float) $i['stock_qty'] <= (float) $i['reorder_point'];
      $val = (float) $i['stock_qty'] * (float) $i['unit_cost'];
  ?>
    <tr class="<?= $low ? 'row-low' : '' ?>">
      <td><b><?= e($i['name']) ?></b></td>
      <td class="r mono"><?= number_format((float) $i['stock_qty'], 0) ?> <?= e($i['unit']) ?></td>
      <td class="r mono"><?= number_format((float) $i['reorder_point'], 0) ?></td>
      <td class="r mono">$<?= money((float) $i['unit_cost']) ?></td>
      <td class="r mono">$<?= money($val) ?></td>
      <td><span class="badge <?= $low ? 'b-void' : 'b-served' ?>"><?= $low ? 'LOW' : 'OK' ?></span></td>
      <td>
        <form method="post" class="restock">
          <input type="hidden" name="restock_id" value="<?= (int) $i['id'] ?>">
          <input type="number" name="qty" min="1" step="1" placeholder="qty" required>
          <button type="submit">+ Add</button>
        </form>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
