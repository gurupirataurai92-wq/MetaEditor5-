<?php
require_once __DIR__ . '/includes/functions.php';
require_login();
$__page = 'Wallet';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $uid    = (int)current_user($pdo)['id'];
    $action = $_POST['action'] ?? '';
    $amount = (float)($_POST['amount'] ?? 0);
    $method = $_POST['method'] ?? 'demo';
    try {
        if ($amount <= 0) throw new RuntimeException('Enter an amount greater than zero.');

        if ($action === 'deposit') {
            if ($method === 'demo') {
                // Instant demo top-up so the app is playable
                wallet_move($pdo, $uid, 'deposit', $amount, 'demo', 'Instant demo top-up');
                flash('Added ' . money($amount) . ' demo credits. 🍯', 'success');
            } else {
                // Real methods are recorded as PENDING — a gateway/agent would confirm them
                wallet_move($pdo, $uid, 'deposit', 0.00, $method,
                    ucfirst($method) . ' deposit request: ' . money($amount), 'pending',
                    strtoupper(substr($method, 0, 3)) . '-' . strtoupper(bin2hex(random_bytes(3))));
                flash('Deposit request via ' . strtoupper($method) . ' recorded as PENDING. In production this confirms when the ' . $method . ' gateway/agent completes the payment.', 'info');
            }
        } elseif ($action === 'withdraw') {
            $bal = (float)current_user($pdo)['balance'];
            if ($amount > $bal) throw new RuntimeException('You cannot withdraw more than your balance.');
            // Debit immediately, mark payout request pending in the note
            wallet_move($pdo, $uid, 'withdraw', -$amount, $method,
                'Withdrawal via ' . $method . ' (pending payout)');
            flash('Withdrawal of ' . money($amount) . ' via ' . strtoupper($method) . ' requested. 🐝', 'success');
        }
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    header('Location: wallet.php');
    exit;
}

$user = current_user($pdo);
$tx = $pdo->prepare('SELECT * FROM transactions WHERE user_id = ? ORDER BY id DESC LIMIT 15');
$tx->execute([$user['id']]);
$tx = $tx->fetchAll();
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">🍯 Wallet</h2>

<div class="card center" style="background:radial-gradient(400px 200px at 50% 0%,rgba(255,176,0,.16),transparent),linear-gradient(180deg,var(--panel),var(--bg-2))">
  <p class="muted">Available balance</p>
  <div style="font-size:2.8rem;font-weight:900;color:var(--gold);text-shadow:var(--glow)"><?= money($user['balance']) ?></div>
</div>

<div class="grid grid--2 mt">
  <div class="card">
    <h3>Deposit</h3>
    <form method="post">
      <?= csrf_field() ?>
      <input type="hidden" name="action" value="deposit">
      <div class="field"><label>Amount (<?= CURRENCY ?>)</label><input type="number" name="amount" step="0.01" min="1" value="50" required></div>
      <label class="method mt"><input type="radio" name="method" value="ecocash" checked><span class="method__emoji">📱</span><div><b>EcoCash</b><br><span class="muted">Mobile money · via Paynow</span></div></label>
      <label class="method mt"><input type="radio" name="method" value="card"><span class="method__emoji">💳</span><div><b>Visa / MasterCard</b><br><span class="muted">Local &amp; international cards</span></div></label>
      <label class="method mt"><input type="radio" name="method" value="agent"><span class="method__emoji">🏪</span><div><b>Cash agent</b><br><span class="muted">Pay cash at a HiveBet agent</span></div></label>
      <label class="method mt"><input type="radio" name="method" value="voucher"><span class="method__emoji">🎟️</span><div><b>Voucher PIN</b><br><span class="muted">Prepaid scratch voucher</span></div></label>
      <label class="method mt"><input type="radio" name="method" value="paypal"><span class="method__emoji">🅿️</span><div><b>PayPal</b><br><span class="muted">Diaspora only (where permitted)</span></div></label>
      <label class="method mt" style="border-color:var(--gold)"><input type="radio" name="method" value="demo"><span class="method__emoji">⚡</span><div><b>Instant demo credit</b><br><span class="muted">Top up play credits now</span></div></label>
      <button class="btn btn--gold btn--block mt">Deposit</button>
    </form>
    <p class="muted mt" style="font-size:.82rem">Only <b>demo</b> credits instantly. Real methods are recorded as pending — connect Paynow/Flutterwave/DPO and the agent network in production.</p>
  </div>

  <div class="card">
    <h3>Withdraw</h3>
    <form method="post" data-confirm="Request this withdrawal?">
      <?= csrf_field() ?>
      <input type="hidden" name="action" value="withdraw">
      <div class="field"><label>Amount (<?= CURRENCY ?>)</label><input type="number" name="amount" step="0.01" min="1" value="20" required></div>
      <div class="field"><label>Payout method</label>
        <select name="method">
          <option value="ecocash">EcoCash</option>
          <option value="card">Bank card</option>
          <option value="agent">Cash agent</option>
        </select>
      </div>
      <button class="btn btn--ghost btn--block">Request withdrawal</button>
    </form>
    <p class="muted mt" style="font-size:.82rem">AML rule: winnings pay back to the method you deposited with. Withdrawals queue for review in a real deployment.</p>
  </div>
</div>

<h2 class="section-title">Recent transactions</h2>
<div class="card">
  <table class="table">
    <tr><th>When</th><th>Type</th><th>Method</th><th>Amount</th><th>Balance</th><th>Status</th></tr>
    <?php foreach ($tx as $t): ?>
      <tr>
        <td class="muted"><?= date('d M H:i', strtotime($t['created_at'])) ?></td>
        <td><?= e(ucfirst($t['type'])) ?></td>
        <td class="muted"><?= e($t['method'] ?? '—') ?></td>
        <td class="<?= $t['amount'] >= 0 ? 'pos' : 'neg' ?>"><?= ($t['amount'] >= 0 ? '+' : '') . money($t['amount']) ?></td>
        <td><?= money($t['balance_after']) ?></td>
        <td><span class="badge badge--<?= $t['status'] === 'pending' ? 'pending' : ($t['status'] === 'rejected' ? 'lost' : 'won') ?>"><?= e(ucfirst($t['status'])) ?></span></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$tx): ?><tr><td colspan="6" class="muted center">No transactions yet.</td></tr><?php endif; ?>
  </table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
