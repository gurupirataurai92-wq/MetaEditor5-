<?php
/**
 * Point of Sale. Add products by click or by scanning/typing a barcode,
 * edit quantities in the side cart, and check out — which records the sale
 * and decrements stock. Till operators only ever see this and their receipts.
 */
$PAGE  = 'pos.php';
$TITLE = 'Point of Sale';
require_once __DIR__ . '/includes/auth.php';
$user = require_page('pos.php');
$pdo  = db();

if (!isset($_SESSION['cart'])) {
    $_SESSION['cart'] = [];   // product_id => qty
}

// --- Cart actions (POST) ----------------------------------------------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = $_POST['action'] ?? '';

    if ($action === 'add' || $action === 'scan') {
        if ($action === 'scan') {
            $code = trim($_POST['code'] ?? '');
            $st = $pdo->prepare('SELECT id FROM products WHERE code = ? AND active = 1');
            $st->execute([$code]);
            $pid = (int) $st->fetchColumn();
            if (!$pid) {
                flash_set('error', 'No active product with code "' . $code . '".');
                redirect('pos.php');
            }
        } else {
            $pid = (int) ($_POST['pid'] ?? 0);
        }
        $qty = max(1, (int) ($_POST['qty'] ?? 1));
        $_SESSION['cart'][$pid] = ($_SESSION['cart'][$pid] ?? 0) + $qty;
        redirect('pos.php');
    }

    if ($action === 'setqty') {
        $pid = (int) ($_POST['pid'] ?? 0);
        $qty = (int) ($_POST['qty'] ?? 0);
        if ($qty <= 0) {
            unset($_SESSION['cart'][$pid]);
        } else {
            $_SESSION['cart'][$pid] = $qty;
        }
        redirect('pos.php');
    }

    if ($action === 'remove') {
        unset($_SESSION['cart'][(int) ($_POST['pid'] ?? 0)]);
        redirect('pos.php');
    }

    if ($action === 'clear') {
        $_SESSION['cart'] = [];
        redirect('pos.php');
    }

    if ($action === 'checkout') {
        if (empty($_SESSION['cart'])) {
            flash_set('error', 'The cart is empty.');
            redirect('pos.php');
        }
        $method = $_POST['method'] ?? 'cash';
        try {
            $pdo->beginTransaction();
            $ids = array_keys($_SESSION['cart']);
            $in  = implode(',', array_fill(0, count($ids), '?'));
            $st  = $pdo->prepare("SELECT * FROM products WHERE id IN ($in) FOR UPDATE");
            $st->execute($ids);
            $prods = [];
            foreach ($st->fetchAll() as $p) { $prods[$p['id']] = $p; }

            $total = 0.0;
            foreach ($_SESSION['cart'] as $pid => $qty) {
                if (!isset($prods[$pid])) { continue; }
                $total += (float) $prods[$pid]['price'] * $qty;
            }
            $vat = $total - ($total / (1 + VAT_RATE));

            $ins = $pdo->prepare(
                'INSERT INTO sales (branch_id, user_id, total, vat, method)
                 VALUES (?, ?, ?, ?, ?)'
            );
            $ins->execute([$user['branch'] ?: 1, $user['id'], round($total, 2), round($vat, 2), $method]);
            $sid = (int) $pdo->lastInsertId();

            $li = $pdo->prepare(
                'INSERT INTO sale_items (sale_id, product_id, name, qty, unit_price, unit_cost)
                 VALUES (?, ?, ?, ?, ?, ?)'
            );
            $dec = $pdo->prepare('UPDATE products SET stock = stock - ? WHERE id = ?');
            foreach ($_SESSION['cart'] as $pid => $qty) {
                if (!isset($prods[$pid])) { continue; }
                $p = $prods[$pid];
                $li->execute([$sid, $pid, $p['name'], $qty, $p['price'], $p['cost']]);
                $dec->execute([$qty, $pid]);
            }
            $pdo->commit();
            $_SESSION['cart'] = [];
            redirect('receipt.php?id=' . $sid);
        } catch (Throwable $e) {
            $pdo->rollBack();
            flash_set('error', 'Checkout failed: ' . $e->getMessage());
            redirect('pos.php');
        }
    }
}

// --- Build the view ---------------------------------------------------------
$products = $pdo->query('SELECT * FROM products WHERE active = 1 ORDER BY name')->fetchAll();
$byId = [];
foreach ($products as $p) { $byId[$p['id']] = $p; }

$cart = [];
$cartTotal = 0.0;
foreach ($_SESSION['cart'] as $pid => $qty) {
    if (!isset($byId[$pid])) { continue; }
    $p = $byId[$pid];
    $line = (float) $p['price'] * $qty;
    $cartTotal += $line;
    $cart[] = ['p' => $p, 'qty' => $qty, 'line' => $line];
}
$cartVat = $cartTotal - ($cartTotal / (1 + VAT_RATE));

require __DIR__ . '/includes/layout_top.php';
?>
<div class="pos">
  <section class="pos-catalog">
    <form method="post" class="scan-bar" autocomplete="off">
      <?= csrf_field() ?>
      <input type="hidden" name="action" value="scan">
      <input type="text" name="code" id="scan-input" placeholder="Scan or type a barcode…" autofocus>
      <button class="btn btn-primary" type="submit">Add</button>
      <button class="btn btn-ghost" type="button" id="cam-btn" title="Use camera">📷 Scan</button>
    </form>
    <div id="cam-wrap" hidden>
      <video id="cam-video" playsinline></video>
      <button class="btn btn-ghost btn-sm" type="button" id="cam-stop">Stop camera</button>
    </div>

    <div class="product-grid">
      <?php foreach ($products as $p): ?>
        <button class="product-card" type="button"
                data-id="<?= (int)$p['id'] ?>"
                data-name="<?= h($p['name']) ?>"
                data-price="<?= h($p['price']) ?>"
                data-stock="<?= (int)$p['stock'] ?>">
          <div class="pc-name"><?= h($p['name']) ?></div>
          <div class="pc-meta"><span class="pc-price"><?= money($p['price']) ?></span>
            <span class="pc-stock<?= $p['stock'] <= 15 ? ' low' : '' ?>"><?= (int)$p['stock'] ?> in stock</span></div>
          <div class="pc-code"><?= h($p['code']) ?></div>
        </button>
      <?php endforeach; ?>
    </div>
  </section>

  <aside class="pos-cart">
    <div class="cart-head">
      <h2>Current sale</h2>
      <?php if ($cart): ?>
        <form method="post" class="inline"><?= csrf_field() ?>
          <input type="hidden" name="action" value="clear">
          <button class="btn btn-ghost btn-sm" type="submit">Clear</button>
        </form>
      <?php endif; ?>
    </div>

    <?php if (!$cart): ?>
      <p class="muted cart-empty">No items yet. Tap a product or scan a barcode.</p>
    <?php else: ?>
      <div class="cart-lines">
        <?php foreach ($cart as $c): ?>
          <div class="cart-line">
            <div class="cl-main">
              <div class="cl-name"><?= h($c['p']['name']) ?></div>
              <div class="cl-price"><?= money($c['p']['price']) ?> each</div>
            </div>
            <form method="post" class="qty-stepper"><?= csrf_field() ?>
              <input type="hidden" name="action" value="setqty">
              <input type="hidden" name="pid" value="<?= (int)$c['p']['id'] ?>">
              <button class="step" type="submit" name="qty" value="<?= $c['qty'] - 1 ?>">−</button>
              <span class="qty"><?= (int)$c['qty'] ?></span>
              <button class="step" type="submit" name="qty" value="<?= $c['qty'] + 1 ?>">+</button>
            </form>
            <div class="cl-total"><?= money($c['line']) ?></div>
            <form method="post" class="inline"><?= csrf_field() ?>
              <input type="hidden" name="action" value="remove">
              <input type="hidden" name="pid" value="<?= (int)$c['p']['id'] ?>">
              <button class="cl-remove" type="submit" title="Remove">×</button>
            </form>
          </div>
        <?php endforeach; ?>
      </div>

      <div class="cart-totals">
        <div class="ct-row"><span>VAT (<?= (int)(VAT_RATE*100) ?>%)</span><span><?= money($cartVat) ?></span></div>
        <div class="ct-row total"><span>Total</span><span><?= money($cartTotal) ?></span></div>
      </div>

      <form method="post" class="checkout"><?= csrf_field() ?>
        <input type="hidden" name="action" value="checkout">
        <label>Payment
          <select name="method">
            <option value="cash">Cash</option>
            <option value="ecocash">EcoCash</option>
            <option value="onemoney">OneMoney</option>
            <option value="card">Card</option>
          </select>
        </label>
        <button class="btn btn-primary btn-block" type="submit">Charge <?= money($cartTotal) ?></button>
      </form>
    <?php endif; ?>
  </aside>
</div>

<!-- Quantity picker dialog (shown when a product is tapped) -->
<div class="modal" id="qty-modal" hidden>
  <div class="modal-card">
    <h3 id="qm-name">Product</h3>
    <p class="muted" id="qm-price"></p>
    <form method="post"><?= csrf_field() ?>
      <input type="hidden" name="action" value="add">
      <input type="hidden" name="pid" id="qm-pid">
      <div class="qty-picker">
        <button type="button" class="step" id="qm-minus">−</button>
        <input type="number" name="qty" id="qm-qty" value="1" min="1" inputmode="numeric">
        <button type="button" class="step" id="qm-plus">+</button>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" id="qm-cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Add to sale</button>
      </div>
    </form>
  </div>
</div>

<?php require __DIR__ . '/includes/layout_bottom.php'; ?>
