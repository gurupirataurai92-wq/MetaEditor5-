<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager']);

$pdo = db();

// Update a price or toggle availability inline.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['save_price'])) {
        $id    = (int) $_POST['id'];
        $price = (float) $_POST['price'];
        if ($price >= 0) {
            $pdo->prepare('UPDATE menu_items SET price = ? WHERE id = ?')->execute([$price, $id]);
            log_action('price_change', "Item #$id -> $" . money($price));
        }
    }
    if (isset($_POST['toggle'])) {
        $id = (int) $_POST['toggle'];
        $pdo->prepare('UPDATE menu_items SET is_available = 1 - is_available WHERE id = ?')->execute([$id]);
        log_action('86_toggle', "Item #$id availability toggled");
    }
    header('Location: menu.php');
    exit;
}

$items = $pdo->query(
    'SELECT m.*, c.name AS category FROM menu_items m
     JOIN categories c ON c.id = m.category_id
     ORDER BY c.sort_order, m.name'
)->fetchAll();

$page_title = 'Menu';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Menu <span class="sub">— prices &amp; availability</span></h1>

<div class="table-wrap">
<table class="grid-table">
  <thead>
    <tr><th>Item</th><th>Category</th><th>Station</th><th class="r">Cost</th>
        <th class="r">Price</th><th class="r">Margin</th><th>Available</th></tr>
  </thead>
  <tbody>
  <?php foreach ($items as $m):
      $margin = (float) $m['price'] - (float) $m['cost'];
  ?>
    <tr class="<?= $m['is_available'] ? '' : 'row-off' ?>">
      <td><b><?= e($m['name']) ?></b></td>
      <td><?= e($m['category']) ?></td>
      <td class="mono"><?= e($m['station']) ?></td>
      <td class="r mono">$<?= money((float) $m['cost']) ?></td>
      <td class="r">
        <form method="post" class="price-form">
          <input type="hidden" name="id" value="<?= (int) $m['id'] ?>">
          <input type="number" name="price" step="0.01" min="0" value="<?= number_format((float) $m['price'], 2, '.', '') ?>">
          <button name="save_price" value="1">save</button>
        </form>
      </td>
      <td class="r mono">$<?= money($margin) ?></td>
      <td>
        <form method="post">
          <button name="toggle" value="<?= (int) $m['id'] ?>" class="badge <?= $m['is_available'] ? 'b-served' : 'b-void' ?> btn-badge">
            <?= $m['is_available'] ? 'ON' : '86' ?>
          </button>
        </form>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<p class="hint">Tap <b>86</b> to pull an item — it instantly disappears from the POS across every channel.</p>
<?php require __DIR__ . '/includes/footer.php'; ?>
