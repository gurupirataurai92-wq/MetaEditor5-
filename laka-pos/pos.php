<?php
require_once __DIR__ . '/includes/auth.php';
require_login(['owner', 'manager', 'cashier']);

$flash = '';
$flash_ok = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $itemIds = $_POST['item_id'] ?? [];
    $qtys    = $_POST['qty'] ?? [];
    $channel = $_POST['channel'] ?? 'counter';
    $method  = $_POST['method'] ?? 'cash';

    $lines = [];
    foreach ($itemIds as $i => $id) {
        $q = (int) ($qtys[$i] ?? 0);
        if ($q > 0) {
            $lines[(int) $id] = $q;
        }
    }

    if (!$lines) {
        $flash = 'Add at least one item before charging.';
    } else {
        $pdo = db();
        try {
            $pdo->beginTransaction();

            // Load the ordered items.
            $in = implode(',', array_fill(0, count($lines), '?'));
            $stmt = $pdo->prepare("SELECT * FROM menu_items WHERE id IN ($in)");
            $stmt->execute(array_keys($lines));
            $items = [];
            foreach ($stmt->fetchAll() as $row) {
                $items[$row['id']] = $row;
            }

            // Compute totals.
            $subtotal = 0.0;
            foreach ($lines as $id => $q) {
                $subtotal += (float) $items[$id]['price'] * $q;
            }
            $tax   = round($subtotal * TAX_RATE, 4);
            $total = round($subtotal + $tax, 4);

            // Create the order.
            $stmt = $pdo->prepare(
                'INSERT INTO orders (channel, cashier_id, subtotal, tax_amount, total, status)
                 VALUES (?,?,?,?,?,?)'
            );
            $stmt->execute([$channel, current_user()['id'], $subtotal, $tax, $total, 'placed']);
            $orderId = (int) $pdo->lastInsertId();

            // Order lines (routed to the item's station) + recipe-driven depletion.
            $oi   = $pdo->prepare(
                'INSERT INTO order_items (order_id, menu_item_id, item_name, qty, unit_price, station)
                 VALUES (?,?,?,?,?,?)'
            );
            $rec  = $pdo->prepare('SELECT ingredient_id, qty FROM recipes WHERE menu_item_id = ?');
            $mov  = $pdo->prepare('INSERT INTO stock_movements (ingredient_id, change_qty, reason) VALUES (?,?,?)');
            $dep  = $pdo->prepare('UPDATE ingredients SET stock_qty = stock_qty - ? WHERE id = ?');

            foreach ($lines as $id => $q) {
                $it = $items[$id];
                $oi->execute([$orderId, $id, $it['name'], $q, $it['price'], $it['station']]);

                $rec->execute([$id]);
                foreach ($rec->fetchAll() as $r) {
                    $used = (float) $r['qty'] * $q;
                    $dep->execute([$used, $r['ingredient_id']]);
                    $mov->execute([$r['ingredient_id'], -$used, "Order #$orderId"]);
                }
            }

            // Record the payment.
            $pay = $pdo->prepare('INSERT INTO payments (order_id, method, amount) VALUES (?,?,?)');
            $pay->execute([$orderId, $method, $total]);

            $pdo->commit();
            log_action('sale', "Order #$orderId total $" . money($total));
            $flash    = "Order #$orderId charged — $" . money($total) . " ($method). Sent to kitchen.";
            $flash_ok = true;
        } catch (Throwable $ex) {
            $pdo->rollBack();
            $flash = 'Could not complete the sale: ' . $ex->getMessage();
        }
    }
}

// Menu grouped by category for the grid.
$rows = db()->query(
    'SELECT m.*, c.name AS category FROM menu_items m
     JOIN categories c ON c.id = m.category_id
     WHERE m.is_available = 1
     ORDER BY c.sort_order, m.name'
)->fetchAll();

$byCat = [];
foreach ($rows as $r) {
    $byCat[$r['category']][] = $r;
}

$page_title = 'Point of Sale';
require __DIR__ . '/includes/header.php';
?>
<h1 class="ph">Point of Sale</h1>
<?php if ($flash): ?>
  <div class="flash <?= $flash_ok ? 'ok' : 'bad' ?>"><?= e($flash) ?></div>
<?php endif; ?>

<form method="post" id="posform" class="pos-grid">
  <section class="menu-col">
    <?php foreach ($byCat as $cat => $items): ?>
      <h2 class="cat"><?= e($cat) ?></h2>
      <div class="tiles">
        <?php foreach ($items as $it): ?>
          <button type="button" class="tile"
                  data-id="<?= (int) $it['id'] ?>"
                  data-name="<?= e($it['name']) ?>"
                  data-price="<?= (float) $it['price'] ?>"
                  data-station="<?= e($it['station']) ?>">
            <span class="tile-img"><img src="assets/food/<?= menu_icon($it['name']) ?>.svg" alt="" width="86" height="86"></span>
            <span class="tile-body">
              <span class="tile-name"><?= e($it['name']) ?></span>
              <span class="tile-meta"><?= e($it['station']) ?></span>
            </span>
            <span class="tile-foot">
              <span class="tile-price">$<?= money((float) $it['price']) ?></span>
              <span class="tile-add">Add +</span>
            </span>
          </button>
        <?php endforeach; ?>
      </div>
    <?php endforeach; ?>
  </section>

  <aside class="cart-col">
    <h2 class="cart-h">Current order</h2>
    <div id="cart" class="cart-lines"><p class="cart-empty">Tap items to add them.</p></div>

    <div class="cart-tot">
      <div><span>Subtotal</span><b id="sub">$0.00</b></div>
      <div><span>VAT (15%)</span><b id="tax">$0.00</b></div>
      <div class="grand"><span>Total</span><b id="grand">$0.00</b></div>
    </div>

    <label class="fld">Channel
      <select name="channel">
        <option value="counter">Counter</option>
        <option value="drive_thru">Drive-thru</option>
        <option value="kiosk">Kiosk</option>
        <option value="online">Online</option>
      </select>
    </label>
    <label class="fld">Payment
      <select name="method">
        <option value="cash">Cash</option>
        <option value="ecocash">EcoCash</option>
        <option value="onemoney">OneMoney</option>
        <option value="zipit">ZIPIT</option>
        <option value="card">Card</option>
      </select>
    </label>

    <div id="hidden-inputs"></div>
    <button type="submit" class="charge" id="charge" disabled>Charge order</button>
  </aside>
</form>

<script>
(function () {
  var cart = {};                                   // id -> {name, price, qty, station}
  var cartEl = document.getElementById('cart');
  var hidden = document.getElementById('hidden-inputs');
  var chargeBtn = document.getElementById('charge');

  function fmt(n) { return '$' + n.toFixed(2); }

  function render() {
    var ids = Object.keys(cart);
    hidden.innerHTML = '';
    if (!ids.length) {
      cartEl.innerHTML = '<p class="cart-empty">Tap items to add them.</p>';
    } else {
      var html = '';
      ids.forEach(function (id) {
        var c = cart[id];
        html += '<div class="cl">' +
          '<div class="cl-main"><b>' + c.name + '</b><span>' + fmt(c.price) + ' · ' + c.station + '</span></div>' +
          '<div class="cl-qty">' +
            '<button type="button" data-dec="' + id + '">−</button>' +
            '<span>' + c.qty + '</span>' +
            '<button type="button" data-inc="' + id + '">+</button>' +
          '</div></div>';
        html += '<input type="hidden" name="item_id[]" value="' + id + '">';
        html += '<input type="hidden" name="qty[]" value="' + c.qty + '">';
      });
      cartEl.innerHTML = html;
    }
    var sub = 0;
    ids.forEach(function (id) { sub += cart[id].price * cart[id].qty; });
    var tax = sub * 0.15, grand = sub + tax;
    document.getElementById('sub').textContent = fmt(sub);
    document.getElementById('tax').textContent = fmt(tax);
    document.getElementById('grand').textContent = fmt(grand);
    chargeBtn.disabled = ids.length === 0;
  }

  document.querySelectorAll('.tile').forEach(function (t) {
    t.addEventListener('click', function () {
      var id = t.dataset.id;
      if (!cart[id]) {
        cart[id] = { name: t.dataset.name, price: parseFloat(t.dataset.price), qty: 0, station: t.dataset.station };
      }
      cart[id].qty++;
      render();
    });
  });

  cartEl.addEventListener('click', function (ev) {
    var inc = ev.target.getAttribute('data-inc');
    var dec = ev.target.getAttribute('data-dec');
    if (inc) { cart[inc].qty++; render(); }
    if (dec) { cart[dec].qty--; if (cart[dec].qty <= 0) delete cart[dec]; render(); }
  });

  render();
})();
</script>
<?php require __DIR__ . '/includes/footer.php'; ?>
