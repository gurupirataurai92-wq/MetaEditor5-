<?php
/**
 * One-time setup. Open http://localhost/sims-ai/install.php once, after
 * starting Apache + MySQL in XAMPP. It creates the database and tables, seeds
 * demo branches / products / sales, and creates the three operator accounts —
 * hashing their passwords with password_hash() (never stored in clear text).
 *
 * Re-running is safe: it only tops up missing rows.
 */
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/functions.php';

$steps = [];
$err   = null;

try {
    // 1) Connect WITHOUT a database and create it + all tables from schema.sql.
    $root = new PDO(
        'mysql:host=' . DB_HOST . ';port=' . DB_PORT . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $sql = file_get_contents(__DIR__ . '/sql/schema.sql');
    $root->exec($sql);
    $steps[] = 'Database "' . DB_NAME . '" and tables created (or already present).';

    // 2) Switch to the app connection.
    require_once __DIR__ . '/config/db.php';
    $pdo = db();

    // 3) Seed branches.
    if ((int) $pdo->query('SELECT COUNT(*) FROM branches')->fetchColumn() === 0) {
        $pdo->exec("INSERT INTO branches (name, location) VALUES
            ('Main Branch', 'Harare CBD'),
            ('Bulawayo Branch', 'Bulawayo')");
        $steps[] = 'Seeded 2 branches.';
    }

    // 4) Seed the three operator accounts (passwords hashed).
    $accounts = [
        ['Rudo Ncube',    'owner@simsai.co.zw',   'owner1234',   'owner',   1],
        ['Nyasha Chikafu', 'manager@simsai.co.zw', 'manager1234', 'manager', 1],
        ['Tatenda M.',    'till@simsai.co.zw',    'till1234',    'cashier', 1],
    ];
    $ins = $pdo->prepare(
        'INSERT INTO users (name, email, password_hash, role, branch_id, on_duty, active)
         VALUES (?, ?, ?, ?, ?, ?, 1)
         ON DUPLICATE KEY UPDATE name = VALUES(name)'
    );
    foreach ($accounts as [$name, $email, $pass, $role, $branch]) {
        $ins->execute([$name, $email, password_hash($pass, PASSWORD_DEFAULT), $role, $branch, 1]);
    }
    $steps[] = 'Created operator accounts (owner / manager / till operator).';

    // 5) Seed products (each with a required product code / barcode).
    if ((int) $pdo->query('SELECT COUNT(*) FROM products')->fetchColumn() === 0) {
        $prods = [
            ['6001240001', 'Mealie Meal 10kg',  8.50, 6.20, 40],
            ['6001240002', 'Cooking Oil 2L',    4.20, 3.10, 35],
            ['6001240003', 'Sugar 2kg',         2.80, 2.00, 60],
            ['6001240004', 'Bread Loaf',        1.10, 0.75, 80],
            ['6001240005', 'Milk 1L',           1.40, 1.00, 50],
            ['6001240006', 'Rice 5kg',          6.90, 5.10, 25],
            ['6001240007', 'Salt 1kg',          0.90, 0.55, 70],
            ['6001240008', 'Soap Bar',          0.80, 0.45, 90],
            ['6001240009', 'Tea Leaves 250g',   2.30, 1.60, 30],
            ['6001240010', 'Matches (box)',     0.40, 0.20, 120],
        ];
        $pins = $pdo->prepare(
            'INSERT INTO products (code, name, price, cost, stock) VALUES (?, ?, ?, ?, ?)'
        );
        foreach ($prods as $p) {
            $pins->execute($p);
        }
        $steps[] = 'Seeded ' . count($prods) . ' products.';
    }

    // 6) Seed a little sales history so the dashboard has figures.
    if ((int) $pdo->query('SELECT COUNT(*) FROM sales')->fetchColumn() === 0) {
        $products = $pdo->query('SELECT * FROM products')->fetchAll();
        $till = (int) $pdo->query("SELECT id FROM users WHERE role='cashier' LIMIT 1")->fetchColumn();
        $methods = ['cash', 'ecocash', 'onemoney', 'card'];
        mt_srand(42);
        for ($d = 13; $d >= 0; $d--) {
            $sales_today = mt_rand(3, 8);
            for ($s = 0; $s < $sales_today; $s++) {
                $lines = mt_rand(1, 4);
                $total = 0.0;
                $picked = [];
                for ($l = 0; $l < $lines; $l++) {
                    $p = $products[array_rand($products)];
                    $qty = mt_rand(1, 3);
                    $picked[] = [$p, $qty];
                    $total += $p['price'] * $qty;
                }
                $vat = $total - ($total / (1 + VAT_RATE));
                $ts  = date('Y-m-d H:i:s', strtotime("-$d days") + mt_rand(28800, 61200));
                $branch = mt_rand(1, 2);
                $method = $methods[array_rand($methods)];
                $si = $pdo->prepare(
                    'INSERT INTO sales (branch_id, user_id, total, vat, method, created_at)
                     VALUES (?, ?, ?, ?, ?, ?)'
                );
                $si->execute([$branch, $till, round($total, 2), round($vat, 2), $method, $ts]);
                $sid = (int) $pdo->lastInsertId();
                $li = $pdo->prepare(
                    'INSERT INTO sale_items (sale_id, product_id, name, qty, unit_price, unit_cost)
                     VALUES (?, ?, ?, ?, ?, ?)'
                );
                foreach ($picked as [$p, $qty]) {
                    $li->execute([$sid, $p['id'], $p['name'], $qty, $p['price'], $p['cost']]);
                }
            }
        }
        $steps[] = 'Seeded 2 weeks of demo sales.';
    }

    // 7) A couple of expenses.
    if ((int) $pdo->query('SELECT COUNT(*) FROM expenses')->fetchColumn() === 0) {
        $pdo->exec("INSERT INTO expenses (branch_id, label, amount) VALUES
            (1, 'Rent',        350.00),
            (1, 'Electricity', 90.00),
            (2, 'Rent',        280.00)");
        $steps[] = 'Seeded expenses.';
    }
} catch (Throwable $e) {
    $err = $e->getMessage();
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Setup — <?= h(APP_NAME) ?></title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body class="auth-body">
  <div class="auth-card" style="max-width:640px">
    <div class="brand"><span class="brand-mark">◆</span> <?= h(APP_NAME) ?></div>
    <h1>First-time setup</h1>

    <?php if ($err): ?>
      <div class="alert error">
        <b>Setup could not finish.</b><br>
        <?= h($err) ?>
        <p style="margin:.6rem 0 0">Start <b>Apache</b> and <b>MySQL</b> in the XAMPP
        Control Panel, then reload this page.</p>
      </div>
    <?php else: ?>
      <div class="alert ok"><b>Setup complete.</b> Your system is ready.</div>
      <ul class="steps">
        <?php foreach ($steps as $st): ?><li><?= h($st) ?></li><?php endforeach; ?>
      </ul>

      <h2 style="margin-top:1.4rem">Sign-in credentials</h2>
      <p class="muted">Use these to open each role's dashboard. (For security,
      passwords are shown here <b>only</b> on this one-time setup page — never
      inside the running system.)</p>
      <table class="cred-table">
        <thead><tr><th>Role</th><th>Email</th><th>Password</th><th>Lands on</th></tr></thead>
        <tbody>
          <tr><td>Owner</td><td>owner@simsai.co.zw</td><td>owner1234</td><td>Dashboard</td></tr>
          <tr><td>Manager</td><td>manager@simsai.co.zw</td><td>manager1234</td><td>Staff &amp; Duty</td></tr>
          <tr><td>Till Operator</td><td>till@simsai.co.zw</td><td>till1234</td><td>Point of Sale</td></tr>
        </tbody>
      </table>

      <a class="btn btn-primary btn-block" href="login.php" style="margin-top:1.2rem">Go to sign in →</a>
      <p class="muted" style="margin-top:1rem">Tip: delete <code>install.php</code>
      after setup on a real deployment.</p>
    <?php endif; ?>
  </div>
</body>
</html>
