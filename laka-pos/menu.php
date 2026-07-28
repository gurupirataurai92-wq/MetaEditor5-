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
    if (isset($_POST['save_image'])) {
        $id  = (int) $_POST['id'];
        $img = trim($_POST['image'] ?? '');
        $pdo->prepare('UPDATE menu_items SET image = ? WHERE id = ?')
            ->execute([$img !== '' ? $img : null, $id]);
        log_action('image_change', "Item #$id photo updated");
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
    <tr><th>Photo</th><th>Item</th><th>Station</th><th class="r">Price</th>
        <th>Photo URL / path</th><th>Available</th></tr>
  </thead>
  <tbody>
  <?php foreach ($items as $m): ?>
    <tr class="<?= $m['is_available'] ? '' : 'row-off' ?>">
      <td class="menu-thumb"><?= food_img($m['image'] ?? null, $m['name']) ?></td>
      <td><b><?= e($m['name']) ?></b><br><span class="mono" style="color:var(--muted);font-size:11px"><?= e($m['category']) ?></span></td>
      <td class="mono"><?= e($m['station']) ?></td>
      <td class="r">
        <form method="post" class="price-form">
          <input type="hidden" name="id" value="<?= (int) $m['id'] ?>">
          <input type="number" name="price" step="0.01" min="0" value="<?= number_format((float) $m['price'], 2, '.', '') ?>">
          <button name="save_price" value="1">save</button>
        </form>
      </td>
      <td>
        <form method="post" class="image-form">
          <input type="hidden" name="id" value="<?= (int) $m['id'] ?>">
          <input type="text" name="image" placeholder="https://… or assets/food/photos/x.jpg"
                 value="<?= e($m['image'] ?? '') ?>">
          <button name="save_image" value="1">save</button>
        </form>
      </td>
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
