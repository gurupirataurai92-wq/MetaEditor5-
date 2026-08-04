<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager']);

$pdo = db();
$flash = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Add a brand-new menu item.
    if (isset($_POST['add_item'])) {
        $name = trim($_POST['name'] ?? '');
        $cat  = (int) ($_POST['category_id'] ?? 0);
        $price = (float) ($_POST['price'] ?? 0);
        $cost  = (float) ($_POST['cost'] ?? 0);
        $station = in_array($_POST['station'] ?? '', ['fryer','grill','drinks','assembly'], true)
            ? $_POST['station'] : 'fryer';
        $prep = max(1, (int) ($_POST['prep_minutes'] ?? 4));
        $img  = trim($_POST['image'] ?? '');
        if ($name !== '' && $cat > 0 && $price >= 0) {
            $pdo->prepare(
                'INSERT INTO menu_items (name, category_id, price, cost, station, prep_minutes, image)
                 VALUES (?,?,?,?,?,?,?)'
            )->execute([$name, $cat, $price, $cost, $station, $prep, $img !== '' ? $img : null]);
            log_action('menu_add', "Added item: $name");
            $_SESSION['flash'] = "Added “$name” to the menu.";
        } else {
            $_SESSION['flash'] = 'Please give the item a name, category and price.';
        }
    }
    if (isset($_POST['save_price'])) {
        $id = (int) $_POST['id']; $price = (float) $_POST['price'];
        if ($price >= 0) {
            $pdo->prepare('UPDATE menu_items SET price = ? WHERE id = ?')->execute([$price, $id]);
            log_action('price_change', "Item #$id -> $" . money($price));
        }
    }
    if (isset($_POST['save_image'])) {
        $id = (int) $_POST['id']; $img = trim($_POST['image'] ?? '');
        $pdo->prepare('UPDATE menu_items SET image = ? WHERE id = ?')
            ->execute([$img !== '' ? $img : null, $id]);
        log_action('image_change', "Item #$id photo updated");
    }
    if (isset($_POST['toggle'])) {
        $id = (int) $_POST['toggle'];
        $pdo->prepare('UPDATE menu_items SET is_available = 1 - is_available WHERE id = ?')->execute([$id]);
        log_action('86_toggle', "Item #$id availability toggled");
    }
    if (isset($_POST['delete_item'])) {
        $id = (int) $_POST['delete_item'];
        try {
            // Recipe rows cascade; this fails if the item is referenced by past orders.
            $pdo->prepare('DELETE FROM menu_items WHERE id = ?')->execute([$id]);
            log_action('menu_delete', "Deleted item #$id");
            $_SESSION['flash'] = 'Item deleted.';
        } catch (Throwable $ex) {
            // Referenced by existing orders — hide it instead of breaking history.
            $pdo->prepare('UPDATE menu_items SET is_available = 0 WHERE id = ?')->execute([$id]);
            log_action('menu_hide', "Item #$id has orders — hidden instead of deleted");
            $_SESSION['flash'] = 'That item has past orders, so it was hidden (86) instead of deleted.';
        }
    }
    header('Location: menu.php');
    exit;
}

if (!empty($_SESSION['flash'])) { $flash = $_SESSION['flash']; unset($_SESSION['flash']); }

$cats  = $pdo->query('SELECT id, name FROM categories ORDER BY sort_order, name')->fetchAll();
$items = $pdo->query(
    'SELECT m.*, c.name AS category FROM menu_items m
     JOIN categories c ON c.id = m.category_id
     ORDER BY c.sort_order, m.name'
)->fetchAll();

$page_title = 'Menu';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Menu <span class="sub">— operators manage every item here</span></h1>
<?php if ($flash): ?><div class="flash ok"><?= e($flash) ?></div><?php endif; ?>

<!-- Add a new item -->
<section class="panel" style="margin-bottom:20px">
  <h2 style="font-family:var(--display);text-transform:uppercase;font-size:16px;margin-bottom:12px">Add a menu item</h2>
  <form method="post" class="add-item">
    <label>Name <input name="name" required placeholder="e.g. Spicy Bucket (12pc)"></label>
    <label>Category
      <select name="category_id" required>
        <?php foreach ($cats as $c): ?><option value="<?= (int) $c['id'] ?>"><?= e($c['name']) ?></option><?php endforeach; ?>
      </select>
    </label>
    <label>Station
      <select name="station">
        <option value="fryer">fryer</option><option value="grill">grill</option>
        <option value="drinks">drinks</option><option value="assembly">assembly</option>
      </select>
    </label>
    <label>Price $ <input type="number" name="price" step="0.01" min="0" required value="0.00"></label>
    <label>Cost $ <input type="number" name="cost" step="0.01" min="0" value="0.00"></label>
    <label>Prep min <input type="number" name="prep_minutes" min="1" value="4"></label>
    <label class="wide">Photo URL / path <input name="image" placeholder="https://… or assets/food/photos/x.jpg"></label>
    <button type="submit" name="add_item" value="1" class="charge" style="width:auto;padding:12px 22px">Add item</button>
  </form>
</section>

<div class="table-wrap">
<table class="grid-table">
  <thead>
    <tr><th>Photo</th><th>Item</th><th>Station</th><th class="r">Price</th>
        <th>Photo URL / path</th><th>Available</th><th>Delete</th></tr>
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
      <td>
        <form method="post" onsubmit="return confirm('Delete <?= e(addslashes($m['name'])) ?>?');">
          <button name="delete_item" value="<?= (int) $m['id'] ?>" class="del-btn">🗑 delete</button>
        </form>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<p class="hint">Tap <b>86</b> to pull an item (hidden from every channel) or <b>delete</b> to remove it entirely.
   Items that already appear in past orders are hidden instead of deleted, to keep your sales history intact.</p>
<?php require __DIR__ . '/includes/footer.php'; ?>
