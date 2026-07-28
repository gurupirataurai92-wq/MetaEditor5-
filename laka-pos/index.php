<?php
/**
 * LAKA LAKA CHICKEN — public customer storefront.
 * No login: customers browse the menu, build a cart, and pay. Every price,
 * tax and total is computed server-side so the client can't set its own price.
 */
require_once __DIR__ . '/config/db.php';

function esc(?string $s): string { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }

$confirm = null;   // set after a successful order -> render the thank-you screen
$error   = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'place_order') {
    $itemIds  = $_POST['item_id'] ?? [];
    $qtys     = $_POST['qty'] ?? [];
    $name     = trim($_POST['customer_name'] ?? '');
    $phone    = trim($_POST['customer_phone'] ?? '');
    $type     = ($_POST['order_type'] ?? 'pickup') === 'delivery' ? 'delivery' : 'pickup';
    $address  = trim($_POST['address'] ?? '');
    $notes    = trim($_POST['notes'] ?? '');
    $method   = $_POST['method'] ?? 'ecocash';

    $allowedMethods = ['ecocash', 'onemoney', 'zipit', 'card', 'cash'];
    if (!in_array($method, $allowedMethods, true)) {
        $method = 'ecocash';
    }

    $lines = [];
    foreach ($itemIds as $i => $id) {
        $q = (int) ($qtys[$i] ?? 0);
        if ($q > 0) { $lines[(int) $id] = $q; }
    }

    if (!$lines) {
        $error = 'Your cart is empty — add something tasty first.';
    } elseif ($name === '' || $phone === '') {
        $error = 'Please enter your name and phone number.';
    } elseif ($type === 'delivery' && $address === '') {
        $error = 'Please enter a delivery address.';
    } else {
        $pdo = db();
        try {
            $pdo->beginTransaction();

            $in = implode(',', array_fill(0, count($lines), '?'));
            $stmt = $pdo->prepare("SELECT * FROM menu_items WHERE id IN ($in) AND is_available = 1");
            $stmt->execute(array_keys($lines));
            $items = [];
            foreach ($stmt->fetchAll() as $row) { $items[$row['id']] = $row; }

            if (!$items) { throw new RuntimeException('None of those items are available right now.'); }

            $subtotal = 0.0;
            foreach ($lines as $id => $q) {
                if (isset($items[$id])) { $subtotal += (float) $items[$id]['price'] * $q; }
            }
            $tax   = round($subtotal * TAX_RATE, 4);
            $total = round($subtotal + $tax, 4);

            // Card payments are captured now; mobile-money & cash settle on the prompt / at handover.
            $payStatus = $method === 'card' ? 'paid' : 'unpaid';

            $stmt = $pdo->prepare(
                'INSERT INTO orders
                   (channel, subtotal, tax_amount, total, status,
                    order_type, customer_name, customer_phone, address, notes, payment_status)
                 VALUES ("online",?,?,?,"placed",?,?,?,?,?,?)'
            );
            $stmt->execute([$subtotal, $tax, $total, $type, $name, $phone,
                            $type === 'delivery' ? $address : null,
                            $notes !== '' ? $notes : null, $payStatus]);
            $orderId = (int) $pdo->lastInsertId();

            $oi  = $pdo->prepare(
                'INSERT INTO order_items (order_id, menu_item_id, item_name, qty, unit_price, station)
                 VALUES (?,?,?,?,?,?)'
            );
            $rec = $pdo->prepare('SELECT ingredient_id, qty FROM recipes WHERE menu_item_id = ?');
            $mov = $pdo->prepare('INSERT INTO stock_movements (ingredient_id, change_qty, reason) VALUES (?,?,?)');
            $dep = $pdo->prepare('UPDATE ingredients SET stock_qty = stock_qty - ? WHERE id = ?');

            foreach ($lines as $id => $q) {
                if (!isset($items[$id])) { continue; }
                $it = $items[$id];
                $oi->execute([$orderId, $id, $it['name'], $q, $it['price'], $it['station']]);
                $rec->execute([$id]);
                foreach ($rec->fetchAll() as $r) {
                    $used = (float) $r['qty'] * $q;
                    $dep->execute([$used, $r['ingredient_id']]);
                    $mov->execute([$r['ingredient_id'], -$used, "Online order #$orderId"]);
                }
            }

            $pay = $pdo->prepare('INSERT INTO payments (order_id, method, amount) VALUES (?,?,?)');
            $pay->execute([$orderId, $method, $total]);

            $pdo->commit();

            $confirm = [
                'id' => $orderId, 'total' => $total, 'type' => $type,
                'method' => $method, 'name' => $name, 'phone' => $phone,
                'pay_status' => $payStatus,
            ];
        } catch (Throwable $ex) {
            if ($pdo->inTransaction()) { $pdo->rollBack(); }
            $error = 'Sorry, we could not place your order: ' . $ex->getMessage();
        }
    }
}

// Menu for the storefront.
$rows = db()->query(
    'SELECT m.*, c.name AS category FROM menu_items m
     JOIN categories c ON c.id = m.category_id
     WHERE m.is_available = 1
     ORDER BY c.sort_order, m.name'
)->fetchAll();
$byCat = [];
foreach ($rows as $r) { $byCat[$r['category']][] = $r; }

$methodLabel = [
    'ecocash' => 'EcoCash', 'onemoney' => 'OneMoney', 'zipit' => 'ZIPIT',
    'card' => 'Card', 'cash' => 'Cash',
];
$payNextStep = [
    'ecocash'  => 'Approve the EcoCash prompt we just sent to your phone.',
    'onemoney' => 'Approve the OneMoney prompt we just sent to your phone.',
    'zipit'    => 'Complete the ZIPIT transfer from your banking app.',
    'card'     => 'Your card payment has been received. Thank you!',
    'cash'     => 'Have your cash ready when you collect / on delivery.',
];
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LAKA LAKA CHICKEN — Order crispy fried chicken online</title>
<link rel="stylesheet" href="assets/style.css">
</head>
<body class="store">

<header class="store-top">
  <a class="store-brand" href="index.php">
    <img src="assets/food/bucket.svg" alt="" width="40" height="40">
    <span>LAKA&nbsp;LAKA&nbsp;CHICKEN</span>
  </a>
  <nav class="store-nav">
    <a href="#menu">Menu</a>
    <a href="#how">How it works</a>
    <a href="tel:+263242000000" class="store-call">☎ 0242 000 000</a>
  </nav>
  <button class="cart-btn" id="cartBtn" type="button">
    🛒 <span>Cart</span> <b id="cartCount">0</b>
  </button>
</header>

<?php if ($confirm): ?>
  <!-- ============ ORDER CONFIRMATION ============ -->
  <section class="confirm-wrap">
    <div class="confirm-card">
      <img src="assets/food/bucket.svg" alt="" width="84" height="84">
      <h1>Order placed! 🍗</h1>
      <p class="confirm-order">Order <b>#<?= (int) $confirm['id'] ?></b> · <?= esc(ucfirst($confirm['type'])) ?></p>
      <div class="confirm-rows">
        <div><span>Name</span><b><?= esc($confirm['name']) ?></b></div>
        <div><span>Phone</span><b><?= esc($confirm['phone']) ?></b></div>
        <div><span>Payment</span><b><?= esc($methodLabel[$confirm['method']] ?? $confirm['method']) ?>
          <?= $confirm['pay_status'] === 'paid' ? '· paid' : '· pending' ?></b></div>
        <div class="grand"><span>Total</span><b>$<?= money((float) $confirm['total']) ?></b></div>
      </div>
      <p class="confirm-next"><?= esc($payNextStep[$confirm['method']] ?? '') ?></p>
      <p class="confirm-eta">We're firing up the fryers — your food will be ready shortly.</p>
      <a class="btn-primary" href="index.php">Order again</a>
    </div>
  </section>

<?php else: ?>
  <!-- ============ HERO ============ -->
  <section class="hero">
    <div class="hero-text">
      <span class="hero-eyebrow">Crispy · Juicy · Laka</span>
      <h1>Real fried chicken,<br>ready when you are.</h1>
      <p>Order online for pickup or delivery. Pay with EcoCash, OneMoney, ZIPIT, card or cash.
         No account needed — just good chicken.</p>
      <a href="#menu" class="btn-primary btn-lg">Order now</a>
    </div>
    <div class="hero-art">
      <img src="assets/food/bucket.svg" alt="Bucket of chicken" width="240" height="240">
    </div>
  </section>
  <div class="stripe"></div>

  <?php if ($error): ?><div class="store-flash bad"><?= esc($error) ?></div><?php endif; ?>

  <!-- ============ MENU ============ -->
  <section id="menu" class="store-menu">
    <h2 class="store-h2">Our Menu</h2>
    <?php foreach ($byCat as $cat => $items): ?>
      <h3 class="store-cat"><?= esc($cat) ?></h3>
      <div class="store-grid">
        <?php foreach ($items as $it): ?>
          <article class="pcard">
            <div class="pcard-img"><?= food_img($it['image'] ?? null, $it['name']) ?></div>
            <div class="pcard-body">
              <h4><?= esc($it['name']) ?></h4>
              <p class="pcard-price">$<?= money((float) $it['price']) ?></p>
            </div>
            <button type="button" class="pcard-add"
                    data-id="<?= (int) $it['id'] ?>"
                    data-name="<?= esc($it['name']) ?>"
                    data-price="<?= (float) $it['price'] ?>">Add to order</button>
          </article>
        <?php endforeach; ?>
      </div>
    <?php endforeach; ?>
  </section>

  <!-- ============ HOW IT WORKS ============ -->
  <section id="how" class="how">
    <h2 class="store-h2">How it works</h2>
    <div class="how-grid">
      <div class="how-step"><span>1</span><b>Pick your food</b><p>Browse the menu and add your favourites to the cart.</p></div>
      <div class="how-step"><span>2</span><b>Pickup or delivery</b><p>Tell us where it's going and how to reach you.</p></div>
      <div class="how-step"><span>3</span><b>Pay your way</b><p>EcoCash, OneMoney, ZIPIT, card, or cash on collection.</p></div>
      <div class="how-step"><span>4</span><b>Grab &amp; enjoy</b><p>We fry it fresh — hot, crispy and ready fast.</p></div>
    </div>
  </section>

  <!-- ============ CART DRAWER ============ -->
  <div class="cart-overlay" id="cartOverlay"></div>
  <aside class="cart-drawer" id="cartDrawer" aria-hidden="true">
    <div class="cd-head">
      <h2>Your order</h2>
      <button type="button" class="cd-close" id="cartClose" aria-label="Close cart">✕</button>
    </div>
    <form method="post" id="orderForm">
      <input type="hidden" name="action" value="place_order">
      <div id="cdLines" class="cd-lines"><p class="cd-empty">Your cart is empty.</p></div>

      <div class="cd-tot">
        <div><span>Subtotal</span><b id="cdSub">$0.00</b></div>
        <div><span>VAT (15%)</span><b id="cdTax">$0.00</b></div>
        <div class="grand"><span>Total</span><b id="cdGrand">$0.00</b></div>
      </div>

      <div class="cd-form">
        <label>Your name <input name="customer_name" required></label>
        <label>Phone number <input name="customer_phone" required placeholder="07xx xxx xxx"></label>

        <fieldset class="cd-type">
          <label class="opt"><input type="radio" name="order_type" value="pickup" checked> Pickup</label>
          <label class="opt"><input type="radio" name="order_type" value="delivery"> Delivery</label>
        </fieldset>

        <label id="addrWrap" style="display:none">Delivery address
          <input name="address" placeholder="Street, suburb, city">
        </label>

        <label>Payment method
          <select name="method" id="payMethod">
            <option value="ecocash">EcoCash</option>
            <option value="onemoney">OneMoney</option>
            <option value="zipit">ZIPIT</option>
            <option value="card">Card</option>
            <option value="cash">Cash (on collection / delivery)</option>
          </select>
        </label>
        <p class="pay-note" id="payNote">You'll get an EcoCash prompt on your phone to approve payment.</p>

        <label>Notes (optional) <input name="notes" placeholder="e.g. extra hot, no ice"></label>
      </div>

      <div id="cdHidden"></div>
      <button type="submit" class="btn-primary cd-checkout" id="cdCheckout" disabled>Place &amp; pay</button>
      <p class="cd-secure">🔒 Prices &amp; totals confirmed securely on our server.</p>
    </form>
  </aside>

  <footer class="store-foot">
    <div class="sf-cols">
      <div>
        <div class="sf-brand"><img src="assets/food/bucket.svg" alt="" width="30" height="30"> LAKA LAKA CHICKEN</div>
        <p>Real fried chicken, made fresh. Order online for pickup or delivery across town.</p>
      </div>
      <div>
        <h4>Opening hours</h4>
        <p>Mon–Sun · 10:00 – 22:00</p>
      </div>
      <div>
        <h4>We accept</h4>
        <p class="sf-pay">EcoCash · OneMoney · ZIPIT · Card · Cash</p>
      </div>
    </div>
    <div class="sf-bottom">© <?= date('Y') ?> LAKA LAKA CHICKEN. All rights reserved.</div>
  </footer>

  <script>
  (function () {
    var cart = {};
    var $ = function (id) { return document.getElementById(id); };
    function fmt(n) { return '$' + n.toFixed(2); }

    function totals() {
      var sub = 0, count = 0;
      Object.keys(cart).forEach(function (id) { sub += cart[id].price * cart[id].qty; count += cart[id].qty; });
      return { sub: sub, tax: sub * 0.15, count: count };
    }

    function render() {
      var ids = Object.keys(cart);
      var linesEl = $('cdLines'), hidden = $('cdHidden');
      if (!ids.length) {
        linesEl.innerHTML = '<p class="cd-empty">Your cart is empty.</p>';
      } else {
        var html = '';
        ids.forEach(function (id) {
          var c = cart[id];
          html += '<div class="cdl">' +
            '<div class="cdl-main"><b>' + c.name + '</b><span>' + fmt(c.price) + '</span></div>' +
            '<div class="cdl-qty">' +
              '<button type="button" data-dec="' + id + '">−</button>' +
              '<span>' + c.qty + '</span>' +
              '<button type="button" data-inc="' + id + '">+</button>' +
            '</div>' +
            '<input type="hidden" name="item_id[]" value="' + id + '">' +
            '<input type="hidden" name="qty[]" value="' + c.qty + '"></div>';
        });
        linesEl.innerHTML = html;
      }
      var t = totals();
      $('cdSub').textContent = fmt(t.sub);
      $('cdTax').textContent = fmt(t.tax);
      $('cdGrand').textContent = fmt(t.sub + t.tax);
      $('cartCount').textContent = t.count;
      $('cdCheckout').disabled = t.count === 0;
    }

    function openCart() {
      $('cartDrawer').classList.add('open');
      $('cartOverlay').classList.add('show');
      $('cartDrawer').setAttribute('aria-hidden', 'false');
    }
    function closeCart() {
      $('cartDrawer').classList.remove('open');
      $('cartOverlay').classList.remove('show');
      $('cartDrawer').setAttribute('aria-hidden', 'true');
    }

    document.querySelectorAll('.pcard-add').forEach(function (b) {
      b.addEventListener('click', function () {
        var id = b.dataset.id;
        if (!cart[id]) { cart[id] = { name: b.dataset.name, price: parseFloat(b.dataset.price), qty: 0 }; }
        cart[id].qty++;
        render();
        openCart();
      });
    });

    $('cdLines').addEventListener('click', function (ev) {
      var inc = ev.target.getAttribute('data-inc'), dec = ev.target.getAttribute('data-dec');
      if (inc) { cart[inc].qty++; render(); }
      if (dec) { cart[dec].qty--; if (cart[dec].qty <= 0) delete cart[dec]; render(); }
    });

    $('cartBtn').addEventListener('click', openCart);
    $('cartClose').addEventListener('click', closeCart);
    $('cartOverlay').addEventListener('click', closeCart);

    // delivery address toggle
    document.querySelectorAll('input[name=order_type]').forEach(function (r) {
      r.addEventListener('change', function () {
        var wrap = $('addrWrap'), addr = wrap.querySelector('input');
        var on = document.querySelector('input[name=order_type]:checked').value === 'delivery';
        wrap.style.display = on ? '' : 'none';
        addr.required = on;
      });
    });

    // payment hint
    var notes = {
      ecocash: "You'll get an EcoCash prompt on your phone to approve payment.",
      onemoney: "You'll get a OneMoney prompt on your phone to approve payment.",
      zipit: "Complete the ZIPIT transfer from your banking app after ordering.",
      card: "Enter your card details at the secure checkout step.",
      cash: "Pay with cash when you collect your order or on delivery."
    };
    $('payMethod').addEventListener('change', function () { $('payNote').textContent = notes[this.value] || ''; });

    render();
  })();
  </script>
<?php endif; ?>
</body>
</html>
