<?php
/**
 * Inventory. Managers/owners add products (a product CODE / barcode is
 * REQUIRED), update prices and stock, and retire products.
 */
$PAGE  = 'inventory.php';
$TITLE = 'Inventory';
require_once __DIR__ . '/includes/auth.php';
$user = require_page('inventory.php');
$pdo  = db();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = $_POST['action'] ?? '';

    if ($action === 'add') {
        $code  = trim($_POST['code'] ?? '');
        $name  = trim($_POST['name'] ?? '');
        $price = (float) ($_POST['price'] ?? 0);
        $cost  = (float) ($_POST['cost'] ?? 0);
        $stock = (int) ($_POST['stock'] ?? 0);
        if ($code === '' || $name === '') {
            flash_set('error', 'A product name and code are both required.');
        } else {
            try {
                $st = $pdo->prepare(
                    'INSERT INTO products (code, name, price, cost, stock) VALUES (?, ?, ?, ?, ?)'
                );
                $st->execute([$code, $name, $price, $cost, $stock]);
                flash_set('ok', 'Added "' . $name . '".');
            } catch (PDOException $e) {
                $msg = $e->getCode() === '23000'
                    ? 'That product code is already in use.'
                    : 'Could not add product.';
                flash_set('error', $msg);
            }
        }
        redirect('inventory.php');
    }

    if ($action === 'update') {
        $id    = (int) ($_POST['id'] ?? 0);
        $price = (float) ($_POST['price'] ?? 0);
        $stock = (int) ($_POST['stock'] ?? 0);
        $st = $pdo->prepare('UPDATE products SET price = ?, stock = ? WHERE id = ?');
        $st->execute([$price, $stock, $id]);
        flash_set('ok', 'Product updated.');
        redirect('inventory.php');
    }

    if ($action === 'retire') {
        $st = $pdo->prepare('UPDATE products SET active = 0 WHERE id = ?');
        $st->execute([(int) ($_POST['id'] ?? 0)]);
        flash_set('ok', 'Product retired.');
        redirect('inventory.php');
    }
}

$products = $pdo->query('SELECT * FROM products WHERE active = 1 ORDER BY name')->fetchAll();
require __DIR__ . '/includes/layout_top.php';
?>
<section class="card">
  <h2>Add a product</h2>
  <form method="post" class="form-row"><?= csrf_field() ?>
    <input type="hidden" name="action" value="add">
    <label>Product code / barcode *
      <input name="code" required placeholder="Scan or type" id="new-code">
      <button type="button" class="btn btn-ghost btn-sm" id="cam-btn" title="Scan with camera">📷</button>
    </label>
    <label>Name *<input name="name" required placeholder="e.g. Sugar 2kg"></label>
    <label>Price (<?= h(CUR_SYMBOL) ?>)<input name="price" type="number" step="0.01" min="0" value="0.00"></label>
    <label>Cost (<?= h(CUR_SYMBOL) ?>)<input name="cost" type="number" step="0.01" min="0" value="0.00"></label>
    <label>Opening stock<input name="stock" type="number" min="0" value="0"></label>
    <button class="btn btn-primary" type="submit">Add product</button>
  </form>
  <div id="cam-wrap" hidden>
    <video id="cam-video" playsinline></video>
    <button class="btn btn-ghost btn-sm" type="button" id="cam-stop">Stop camera</button>
  </div>
</section>

<section class="card">
  <h2>Products (<?= count($products) ?>)</h2>
  <div class="table-scroll">
    <table class="table">
      <thead><tr><th>Code</th><th>Name</th><th>Price</th><th>Stock</th><th></th></tr></thead>
      <tbody>
        <?php foreach ($products as $p): ?>
          <tr>
            <td class="mono"><?= h($p['code']) ?></td>
            <td><?= h($p['name']) ?></td>
            <td>
              <form method="post" class="row-edit" id="edit-<?= (int)$p['id'] ?>"><?= csrf_field() ?>
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="id" value="<?= (int)$p['id'] ?>">
                <input name="price" type="number" step="0.01" min="0" value="<?= h($p['price']) ?>" class="mini">
              </form>
            </td>
            <td>
              <input name="stock" type="number" min="0" value="<?= (int)$p['stock'] ?>" class="mini"
                     form="edit-<?= (int)$p['id'] ?>">
            </td>
            <td class="row-actions">
              <button class="btn btn-ghost btn-sm" type="submit" form="edit-<?= (int)$p['id'] ?>">Save</button>
              <form method="post" class="inline"
                    onsubmit="return confirm('Retire this product?')"><?= csrf_field() ?>
                <input type="hidden" name="action" value="retire">
                <input type="hidden" name="id" value="<?= (int)$p['id'] ?>">
                <button class="btn btn-ghost btn-sm danger" type="submit">Retire</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
